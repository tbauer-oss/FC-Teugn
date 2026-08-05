import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'offline_outbox.dart';

class ApiClient {
  static const productionBaseUrl = 'https://fc-teugn-backend.vercel.app';

  final Dio dio;

  ApiClient._internal(this.dio);

  factory ApiClient({
    String? baseUrl,
    String? accessToken,
    Future<String?> Function()? refreshAccessToken,
    VoidCallback? onSessionExpired,
    GeneralOfflineOutbox? offlineOutbox,
    String? userId,
  }) {
    const envBaseUrl = String.fromEnvironment('API_BASE_URL');

    String inferredWebBaseUrl = '';
    if (kIsWeb) {
      if (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1') {
        inferredWebBaseUrl = 'http://localhost:4000';
      } else {
        // Frontend and API are deployed as separate Vercel projects.
        inferredWebBaseUrl = productionBaseUrl;
      }
    }

    String resolvedBaseUrl;
    if (baseUrl != null) {
      resolvedBaseUrl = baseUrl;
    } else if (envBaseUrl.isNotEmpty) {
      resolvedBaseUrl = envBaseUrl;
    } else {
      resolvedBaseUrl = kIsWeb ? inferredWebBaseUrl : productionBaseUrl;
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: resolvedBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    if (accessToken != null) {
      dio.options.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (refreshAccessToken != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) async {
            final request = error.requestOptions;
            if (error.response?.statusCode != 401 ||
                request.extra['sessionRetry'] == true ||
                request.path.startsWith('/auth/')) {
              handler.next(error);
              return;
            }
            final token = await refreshAccessToken();
            if (token == null) {
              onSessionExpired?.call();
              handler.next(error);
              return;
            }
            request.headers['Authorization'] = 'Bearer $token';
            request.extra['sessionRetry'] = true;
            try {
              handler.resolve(await dio.fetch<dynamic>(request));
            } catch (_) {
              onSessionExpired?.call();
              handler.next(error);
            }
          },
        ),
      );
    }
    dio.interceptors.add(_TransientGetRetryInterceptor(dio));
    if (offlineOutbox != null && userId?.isNotEmpty == true) {
      dio.interceptors.add(
        OfflineOutboxInterceptor(
          dio: dio,
          outbox: offlineOutbox,
          userId: userId!,
        ),
      );
    }

    return ApiClient._internal(dio);
  }
}

/// Wiederholt ausschließlich fehlgeschlagene Lesezugriffe. GET-Aufrufe sind
/// idempotent und können deshalb nach einem kurzen Netzwechsel oder Vercel-
/// Kaltstart sicher erneut gesendet werden. Schreibzugriffe bleiben bewusst
/// unangetastet, damit keine Termine oder anderen Datensätze doppelt entstehen.
class _TransientGetRetryInterceptor extends Interceptor {
  _TransientGetRetryInterceptor(this._dio);

  static const _attemptKey = 'transientGetRetryAttempt';
  static const _maximumRetries = 3;

  final Dio _dio;

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    final attempt = request.extra[_attemptKey] as int? ?? 0;
    if (request.method.toUpperCase() != 'GET' ||
        attempt >= _maximumRetries ||
        !_isTransient(error)) {
      handler.next(error);
      return;
    }

    request.extra[_attemptKey] = attempt + 1;
    await Future<void>.delayed(
      Duration(milliseconds: 300 * (1 << attempt)),
    );
    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _isTransient(DioException error) {
    final status = error.response?.statusCode;
    if (status != null) {
      return status == 408 || status == 429 || status >= 500;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        true,
      _ => false,
    };
  }
}
