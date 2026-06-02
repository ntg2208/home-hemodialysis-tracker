import 'package:dio/dio.dart';

/// Faithful port of frontend/src/api/cloudRun.ts error model.
enum CloudErrorCode { unauthorized, network, badData, server }

class CloudRunError implements Exception {
  CloudRunError(this.code, this.message);
  final CloudErrorCode code;
  final String message;
  @override
  String toString() => 'CloudRunError($code): $message';
}

/// Base origin for the Cloud Run API. On Flutter web served from homehd.web.app this
/// is same-origin (no CORS preflight); on mobile it's a plain absolute call (no CORS).
const String kApiBase = 'https://homehd.web.app';

const _timeout = Duration(milliseconds: 35000); // above Cloud Run's 30s timeout
const _retryDelays = [Duration(seconds: 1), Duration(seconds: 3)];

/// Wraps a dio instance with Bearer auth and the project's error semantics.
class RestClient {
  RestClient({
    required String Function() mainKey,
    void Function()? onUnauthorized,
    Dio? dio,
  })  : _mainKey = mainKey,
        _onUnauthorized = onUnauthorized,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = kApiBase
      ..connectTimeout = _timeout
      ..receiveTimeout = _timeout
      ..responseType = ResponseType.json
      ..validateStatus = (_) => true; // we map statuses ourselves
  }

  final Dio _dio;
  final String Function() _mainKey;
  final void Function()? _onUnauthorized;

  Map<String, String> get _headers => {'Authorization': 'Bearer ${_mainKey()}'};

  /// GET is idempotent → retried on transient network failures only.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await _once(() => _dio.get(
              path,
              queryParameters: query,
              options: Options(headers: _headers),
            ));
      } on CloudRunError catch (e) {
        if (e.code == CloudErrorCode.network && attempt < _retryDelays.length) {
          await Future.delayed(_retryDelays[attempt]);
          attempt++;
          continue;
        }
        rethrow;
      }
    }
  }

  /// POST/PUT/PATCH are not retried (no idempotency key → double-write risk).
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Object? body,
  }) {
    return _once(() => _dio.request(
          path,
          data: body,
          options: Options(method: method, headers: _headers),
        ));
  }

  Future<Map<String, dynamic>> _once(Future<Response> Function() run) async {
    Response res;
    try {
      res = await run();
    } catch (_) {
      throw CloudRunError(CloudErrorCode.network, 'Could not reach the server.');
    }
    if (res.statusCode == 401) {
      _onUnauthorized?.call();
      throw CloudRunError(CloudErrorCode.unauthorized, 'Access key rejected.');
    }
    if (res.statusCode == null || res.statusCode! < 200 || res.statusCode! >= 300) {
      throw CloudRunError(
          CloudErrorCode.server, 'Server error (${res.statusCode}).');
    }
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw CloudRunError(CloudErrorCode.badData, 'Server returned invalid JSON.');
  }
}
