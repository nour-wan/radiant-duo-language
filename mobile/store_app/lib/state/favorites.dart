import 'package:flutter/foundation.dart';

import '../services/store_api.dart';
import 'session.dart';

/// Favorite product ids of the logged-in customer (synced with the server).
class Favorites extends ChangeNotifier {
  Favorites(this._api, this._session) {
    _session.addListener(_onSession);
    _onSession();
  }

  final StoreApi _api;
  final Session _session;
  Set<int> ids = {};
  int? _userId;

  void _onSession() {
    final uid = _session.user?.id;
    if (uid == _userId) return;
    _userId = uid;
    ids = {};
    notifyListeners();
    if (uid != null) {
      _api.favoriteIds().then((v) {
        ids = v;
        notifyListeners();
      }).catchError((_) {});
    }
  }

  bool contains(int productId) => ids.contains(productId);

  /// Returns the new state. Throws if the request fails (state is rolled back).
  Future<bool> toggle(int productId) async {
    final adding = !ids.contains(productId);
    adding ? ids.add(productId) : ids.remove(productId);
    notifyListeners();
    try {
      adding ? await _api.addFavorite(productId) : await _api.removeFavorite(productId);
    } catch (_) {
      adding ? ids.remove(productId) : ids.add(productId);
      notifyListeners();
      rethrow;
    }
    return adding;
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }
}
