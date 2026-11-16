import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Push notifications via FCM (delivery only — all data stays on our server).
///
/// If google-services.json is not in android/app yet, Firebase fails to start
/// and push is simply disabled; the in-app notification inbox still works.
class PushService {
  PushService({required this.registerToken, required this.onOpen});

  final Future<void> Function(String token) registerToken;
  final void Function(Map<String, dynamic> data) onOpen;
  final _local = FlutterLocalNotificationsPlugin();
  bool enabled = false;
  String? token;

  // A tap that started the app arrives before any screen exists; it is kept
  // here and opened by markReady() once the first frame is on screen.
  bool _ready = false;
  Map<String, dynamic>? _pending;

  void _open(Map<String, dynamic> data) {
    if (_ready) {
      onOpen(data);
    } else {
      _pending = data;
    }
  }

  /// Call after runApp, when the navigator exists.
  void markReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ready = true;
      final data = _pending;
      _pending = null;
      if (data != null) onOpen(data);
    });
  }

  static const channel = AndroidNotificationChannel('alas_default', 'Orders & offers', importance: Importance.high);

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push disabled (Firebase not configured): $e');
      return;
    }
    enabled = true;
    final messaging = FirebaseMessaging.instance;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) => _open(_decode(r.payload)),
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    // Android shows notifications itself when the app is in the background;
    // in the foreground we show them with the local notifications plugin.
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      _local.show(
        id: m.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(channel.id, channel.name,
              importance: Importance.high, priority: Priority.high, icon: '@drawable/ic_notification'),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: _encode(m.data),
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
    // App started by tapping a notification: from FCM (app was closed) or from
    // one we showed ourselves while the app was open and it was closed since.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _open(initial.data);
    } else {
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) _open(_decode(launch!.notificationResponse?.payload));
    }

    // The server sends with FCM HTTP v1 "token" targets, so we use registration tokens.
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((t) {
      token = t;
      registerToken(t).catchError((_) {});
    });
  }

  /// Ask permission (Android 13+ shows a dialog) and send the token to our server.
  Future<void> requestAndRegister() async {
    if (!enabled) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // ignore: deprecated_member_use
      token = await FirebaseMessaging.instance.getToken();
      if (token != null) await registerToken(token!);
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  static String _encode(Map<String, dynamic> data) =>
      data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}').join('&');

  static Map<String, dynamic> _decode(String? payload) => payload == null || payload.isEmpty ? {} : Uri.splitQueryString(payload);
}
