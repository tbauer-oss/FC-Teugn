import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  final Dio dio;

  ApiClient._internal(this.dio);

  factory ApiClient({String? baseUrl, String? accessToken}) {
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

    return ApiClient._internal(dio);
  }
}
