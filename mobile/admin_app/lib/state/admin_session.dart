import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/foundation.dart';

/// Staff-only session. The server's /admin/auth/login rejects customer accounts.
class AdminSession extends ChangeNotifier {
  AdminSession(this.client);

  final ApiClient client;
  AppUser? user;

  bool get loggedIn => user != null;

  Future<void> restore() async {
    await client.tokens.load();
    if (!client.tokens.hasSession) return;
    try {
      final me = AppUser.fromJson(await client.get('/me/'));
      if (me.isStaff) {
        user = me;
      } else {
        await client.tokens.clear();
      }
    } on ApiException catch (e) {
      if (e.isUnauthorized) await client.tokens.clear();
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await client.post<Map<String, dynamic>>('/admin/auth/login/', data: {'email': email.trim(), 'password': password}, noAuth: true);
    final tokens = data['tokens'] as Map;
    await client.tokens.save(tokens['access'] as String, tokens['refresh'] as String);
    user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async {
    final data = await client.post<Map<String, dynamic>>('/me/password/', data: {'current_password': current, 'new_password': next});
    final tokens = data['tokens'] as Map;
    await client.tokens.save(tokens['access'] as String, tokens['refresh'] as String);
  }

  Future<void> logout({String? deviceToken}) async {
    try {
      await client.post('/auth/logout/', data: {'refresh': client.tokens.refresh, 'device_token': deviceToken});
    } catch (_) {}
    await client.tokens.clear();
    user = null;
    notifyListeners();
  }

  void expired() {
    user = null;
    notifyListeners();
  }
}
