import 'dart:async';
import 'dart:convert';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/admin_api.dart';

/// Sends this phone's position to the server for every order the employee is delivering, so the
/// customer (and the store) see the driver and the route on a map.
///
/// - Runs as a foreground service ("delivering" notification), so it keeps going with the screen off.
/// - Records a point every few seconds even when standing still, and sends them every 10 seconds.
/// - Points that couldn't be sent (no signal) are kept, also across app restarts, and sent in one
///   batch when the connection is back, so the route has no gaps.
/// - Stops once the server says the order was delivered, cancelled or handed to someone else.
class DeliveryTracker extends ChangeNotifier {
  DeliveryTracker(this._prefs, this._api) {
    _restoreQueue();
  }

  final SharedPreferences _prefs;
  final AdminApi _api;
  static const _key = 'delivery.orders';
  static const _queueKey = 'delivery.queue';
  static const _sendEvery = Duration(seconds: 10);
  static const _recordEvery = Duration(seconds: 5);
  static const _maxQueue = 3000; // ~4 hours of points at one every 5 s

  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;
  bool _sending = false;
  String _title = '', _text = '';
  Position? _last;
  DateTime _lastRecorded = DateTime.fromMillisecondsSinceEpoch(0);

  /// Points not yet accepted by the server: {latitude, longitude, at}.
  final List<Map<String, dynamic>> _queue = [];

  /// When the server last accepted this phone's position (for the "last sent" line).
  DateTime? lastSentAt;

  Set<int> get orders => {...?_prefs.getStringList(_key)?.map(int.tryParse).whereType<int>()};
  bool isTracking(int orderId) => orders.contains(orderId) && _sub != null;

  /// Points waiting for a connection.
  int get pending => _queue.length;

  /// Where this phone was last seen (to show it on the order map).
  LatLng? get lastPosition => _last == null ? null : LatLng(_last!.latitude, _last!.longitude);

  Future<void> _save(Set<int> ids) async {
    await _prefs.setStringList(_key, [for (final i in ids) '$i']);
    notifyListeners();
  }

  void _restoreQueue() {
    try {
      final raw = _prefs.getString(_queueKey);
      if (raw != null) _queue.addAll((jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
  }

  void _persistQueue() => _prefs.setString(_queueKey, jsonEncode(_queue));

  /// Notification texts (in the app language) for the foreground service.
  void setTexts(String title, String text) {
    _title = title;
    _text = text;
  }

  /// Asks for location permission if needed. Returns false when it isn't available.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Start sharing the position for [orderId]. Returns false if location isn't allowed.
  Future<bool> start(int orderId) async {
    if (!await ensurePermission()) return false;
    await _save({...orders, orderId});
    _listen();
    _record(force: true);
    return true;
  }

  Future<void> stop(int orderId) async {
    final left = orders..remove(orderId);
    await _save(left);
    if (left.isEmpty) await _cancel();
  }

  /// After the app restarts: carry on for orders still being delivered.
  Future<void> resume() async {
    if (orders.isEmpty) return;
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.whileInUse || p == LocationPermission.always) {
      _listen();
      _record(force: true);
    }
  }

  Future<void> _cancel() async {
    await _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _queue.clear();
    _persistQueue();
    notifyListeners();
  }

  void _listen() {
    if (_sub != null) return;
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0, // a point every few seconds, also when standing still
            intervalDuration: _recordEvery,
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: _title.isEmpty ? 'Alas' : _title,
              notificationText: _text,
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _last = pos;
        _record();
      },
      onError: (_) {},
    );
    // Sends what was recorded, and keeps a point coming even if the phone gives no new fix
    _heartbeat = Timer.periodic(_sendEvery, (_) {
      if (_last != null && DateTime.now().difference(_lastRecorded) > _sendEvery * 2) _record(force: true);
      _flush();
    });
    notifyListeners();
  }

  /// Adds the current position to the queue (at most one point every few seconds).
  Future<void> _record({bool force = false}) async {
    if (!force && DateTime.now().difference(_lastRecorded) < _recordEvery) return;
    var pos = _last;
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
        _last = pos;
      } catch (_) {
        return;
      }
    }
    _lastRecorded = DateTime.now();
    _queue.add({
      'latitude': pos.latitude.toStringAsFixed(6),
      'longitude': pos.longitude.toStringAsFixed(6),
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length > _maxQueue) _queue.removeRange(0, _queue.length - _maxQueue);
    _persistQueue();
    if (force) _flush();
  }

  /// Sends every waiting point, oldest first, to each order being delivered.
  Future<void> _flush() async {
    if (_sending || _queue.isEmpty || orders.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_queue.take(500));
    try {
      for (final id in orders) {
        final keep = await _api.reportLocation(id, batch);
        if (!keep) await stop(id);
      }
      _queue.removeRange(0, batch.length.clamp(0, _queue.length));
      _persistQueue();
      lastSentAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // No connection: the points stay queued and go with the next try
    } finally {
      _sending = false;
    }
  }
}
