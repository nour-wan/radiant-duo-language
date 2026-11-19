import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/admin_api.dart';

/// Sends this phone's position to the server for every order the employee is delivering, so the
/// customer sees the driver on a map. Runs as a foreground service ("delivering" notification),
/// so it keeps going with the screen off, and stops once the server says the order was delivered,
/// cancelled or taken over by someone else.
class DeliveryTracker extends ChangeNotifier {
  DeliveryTracker(this._prefs, this._api);

  final SharedPreferences _prefs;
  final AdminApi _api;
  static const _key = 'delivery.orders';
  static const _every = Duration(seconds: 10);

  StreamSubscription<Position>? _sub;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sending = false;
  String _title = '', _text = '';

  Set<int> get orders => {...?_prefs.getStringList(_key)?.map(int.tryParse).whereType<int>()};
  bool isTracking(int orderId) => orders.contains(orderId) && _sub != null;

  Future<void> _save(Set<int> ids) async {
    await _prefs.setStringList(_key, [for (final i in ids) '$i']);
    notifyListeners();
  }

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
    _send(force: true);
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
      _send(force: true);
    }
  }

  Future<void> _cancel() async {
    await _sub?.cancel();
    _sub = null;
    notifyListeners();
  }

  void _listen() {
    if (_sub != null) return;
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
            intervalDuration: _every,
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: _title.isEmpty ? 'Alas' : _title,
              notificationText: _text,
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _last = pos;
        _send();
      },
      onError: (_) {},
    );
    notifyListeners();
  }

  Position? _last;

  /// Where this phone was last seen (to show it on the order map).
  LatLng? get lastPosition => _last == null ? null : LatLng(_last!.latitude, _last!.longitude);

  Future<void> _send({bool force = false}) async {
    if (_sending || (!force && DateTime.now().difference(_lastSent) < _every)) return;
    var pos = _last;
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
        _last = pos;
      } catch (_) {
        return;
      }
    }
    _sending = true;
    _lastSent = DateTime.now();
    try {
      for (final id in orders) {
        final keep = await _api.reportLocation(id, pos.latitude, pos.longitude);
        if (!keep) await stop(id);
      }
    } catch (_) {
      // No connection for a moment: the next position will be sent
    } finally {
      _sending = false;
    }
  }
}
