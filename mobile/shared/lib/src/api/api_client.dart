import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API base URL. Override at build time: --dart-define=API_BASE_URL=https://...
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.alasfoodstuff.com');

/// An error from the server with a stable code (translated in the app) or a network problem.
class ApiException implements Exception {
  ApiException(this.code, [this.message = '', this.status, this.extra = const {}]);

  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> extra;

  bool get isNetwork => code == 'network';
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($code, $message)';
}

class TokenStore {
  TokenStore(this.namespace);

  final String namespace;
  // Android: encrypted with a Keystore-backed key (default since flutter_secure_storage 10).
  static const _storage = FlutterSecureStorage();
  String? access;
  String? refresh;

  Future<void> load() async {
    access = await _storage.read(key: '$namespace.access');
    refresh = await _storage.read(key: '$namespace.refresh');
  }

  Future<void> save(String a, String r) async {
    access = a;
    refresh = r;
    await _storage.write(key: '$namespace.access', value: a);
    await _storage.write(key: '$namespace.refresh', value: r);
  }

  Future<void> clear() async {
    access = null;
    refresh = null;
    await _storage.delete(key: '$namespace.access');
    await _storage.delete(key: '$namespace.refresh');
  }

  bool get hasSession => refresh != null;
}

/// Thin wrapper around Dio: adds the JWT, refreshes it once on 401, and turns
/// every failure into an [ApiException].
class ApiClient {
  ApiClient({required this.tokens, this.onSessionExpired, String? baseUrl})
      : dio = Dio(BaseOptions(
          baseUrl: '${baseUrl ?? apiBaseUrl}/api/v1',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokens.access;
        if (token != null && options.extra['noAuth'] != true) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final req = error.requestOptions;
        if (error.response?.statusCode == 401 && tokens.refresh != null && req.extra['retried'] != true && req.extra['noAuth'] != true) {
          if (await _refresh()) {
            req.extra['retried'] = true;
            req.headers['Authorization'] = 'Bearer ${tokens.access}';
            try {
              return handler.resolve(await dio.fetch(req));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
          await tokens.clear();
          onSessionExpired?.call();
        }
        handler.next(error);
      },
    ));
  }

  final Dio dio;
  final TokenStore tokens;
  void Function()? onSessionExpired;
  Completer<bool>? _refreshing;

  Future<bool> _refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final completer = _refreshing = Completer<bool>();
    try {
      final r = await dio.post('/auth/refresh/', data: {'refresh': tokens.refresh}, options: Options(extra: {'noAuth': true}));
      await tokens.save(r.data['access'] as String, (r.data['refresh'] ?? tokens.refresh) as String);
      completer.complete(true);
    } catch (_) {
      completer.complete(false);
    } finally {
      _refreshing = null;
    }
    return completer.future;
  }

  Future<T> _wrap<T>(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      return r.data as T;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  static ApiException _toApiException(DioException e) {
    final res = e.response;
    if (res == null) return ApiException('network', e.message ?? '');
    final data = res.data;
    if (data is Map) {
      final extra = Map<String, dynamic>.from(data);
      return ApiException((data['code'] ?? 'error').toString(), (data['detail'] ?? '').toString(), res.statusCode, extra);
    }
    if (res.statusCode == 404) return ApiException('not_found', '', 404);
    if (res.statusCode == 429) return ApiException('throttled', '', 429);
    return ApiException('server_error', '', res.statusCode);
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) => _wrap<T>(() => dio.get(path, queryParameters: query));
  Future<T> post<T>(String path, {Object? data, bool noAuth = false}) =>
      _wrap<T>(() => dio.post(path, data: data, options: Options(extra: {'noAuth': noAuth})));
  Future<T> patch<T>(String path, {Object? data}) => _wrap<T>(() => dio.patch(path, data: data));
  Future<T> put<T>(String path, {Object? data}) => _wrap<T>(() => dio.put(path, data: data));
  Future<T> delete<T>(String path) => _wrap<T>(() => dio.delete(path));

  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) async {
    try {
      final r = await dio.get<List<int>>(path, queryParameters: query, options: Options(responseType: ResponseType.bytes));
      return r.data ?? [];
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }
}

/// Paginated list response from DRF.
class PageResult<T> {
  PageResult(this.items, this.count, this.hasMore);

  factory PageResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) => PageResult(
        (json['results'] as List).map((e) => parse(e as Map<String, dynamic>)).toList(),
        json['count'] as int? ?? 0,
        json['next'] != null,
      );

  final List<T> items;
  final int count;
  final bool hasMore;
}
