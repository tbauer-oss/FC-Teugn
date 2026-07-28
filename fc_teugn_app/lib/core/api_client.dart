import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  final Dio dio;

  ApiClient._internal(this.dio);

  factory ApiClient({
    String? baseUrl,
    String? accessToken,
    Future<String?> Function()? refreshAccessToken,
    VoidCallback? onSessionExpired,
  }) {
    const envBaseUrl = String.fromEnvironment('API_BASE_URL');

    String inferredWebBaseUrl = '';
    if (kIsWeb) {
      if (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1') {
        inferredWebBaseUrl = 'http://localhost:4000';
      } else {
        // Frontend and API are deployed as separate Vercel projects.
        inferredWebBaseUrl = 'https://fc-teugn-backend.vercel.app';
      }
    }

    String resolvedBaseUrl;
    if (baseUrl != null) {
      resolvedBaseUrl = baseUrl;
    } else if (envBaseUrl.isNotEmpty) {
      resolvedBaseUrl = envBaseUrl;
    } else {
      resolvedBaseUrl = kIsWeb ? inferredWebBaseUrl : 'http://localhost:4000';
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

    return ApiClient._internal(dio);
  }
}
