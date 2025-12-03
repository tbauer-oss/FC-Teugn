import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  final Dio dio;

  ApiClient._internal(this.dio);

  factory ApiClient({String? baseUrl, String? accessToken}) {
    final envBaseUrl = const String.fromEnvironment('API_BASE_URL');
    final resolvedBaseUrl = baseUrl ??
        (envBaseUrl.isNotEmpty
            ? envBaseUrl
            : (kIsWeb ? '' : 'http://localhost:4000'));

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

    return ApiClient._internal(dio);
  }
}
