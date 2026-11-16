import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/foundation.dart';

class Session extends ChangeNotifier {
  Session(this.client);

  final ApiClient client;
  AppUser? user;

  bool get loggedIn => user != null;

  Future<void> restore() async {
    await client.tokens.load();
    if (!client.tokens.hasSession) return;
    try {
      user = AppUser.fromJson(await client.get('/me/'));
    } on ApiException catch (e) {
      if (e.isUnauthorized) await client.tokens.clear();
    }
    notifyListeners();
  }

  Future<void> _accept(Map<String, dynamic> data) async {
    final tokens = data['tokens'] as Map;
    await client.tokens.save(tokens['access'] as String, tokens['refresh'] as String);
    user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    notifyListeners();
  }

  /// Customers sign in with their phone number and password.
  Future<void> login(String phone, String password) async =>
      _accept(await client.post('/auth/login/', data: {'phone': phone, 'password': password}, noAuth: true));

  Future<void> register(
          {required String phone, required String code, required String password, required Map<String, dynamic> profile, required String lang}) async =>
      _accept(await client.post('/auth/register/', noAuth: true, data: {
        ...profile,
        'phone': phone,
        'code': code,
        'password': password,
        'language': lang,
      }));

  /// Sends a 6-digit code on WhatsApp. Returns 'whatsapp' (sent automatically) or 'manual' (the store sends it).
  Future<String> requestCode(String phone, String purpose, String lang) async {
    final r = await client.post('/auth/phone-code/', data: {'phone': phone, 'purpose': purpose, 'language': lang}, noAuth: purpose != 'change');
    return (r as Map)['channel'] as String? ?? 'whatsapp';
  }

  Future<void> changePhone(String phone, String code) async {
    user = AppUser.fromJson(await client.post('/me/phone/', data: {'phone': phone, 'code': code}));
    notifyListeners();
  }

  Future<void> confirmReset(String phone, String code, String password) => client.post('/auth/password-reset/confirm/',
      data: {'phone': phone, 'code': code, 'new_password': password}, noAuth: true);

  Future<void> updateProfile(Map<String, dynamic> data) async {
    user = AppUser.fromJson(await client.patch('/me/', data: data));
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async =>
      _accept(await client.post('/me/password/', data: {'current_password': current, 'new_password': next}));

  Future<void> logout({String? deviceToken}) async {
    try {
      await client.post('/auth/logout/', data: {'refresh': client.tokens.refresh, 'device_token': deviceToken});
    } catch (_) {}
    await _clear();
  }

  Future<void> deleteAccount(String password) async {
    await client.post('/me/delete/', data: {'password': password, 'confirm': true});
    await _clear();
  }

  Future<void> _clear() async {
    await client.tokens.clear();
    user = null;
    notifyListeners();
  }

  void expired() {
    user = null;
    notifyListeners();
  }
}
