import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  final Dio dio;

  ApiClient._internal(this.dio);

  factory ApiClient({String? baseUrl, String? accessToken}) {
    final envBaseUrl = const String.fromEnvironment('API_BASE_URL');

    String inferredWebBaseUrl = '';
    if (kIsWeb) {
      // Vercel preview deployments render the frontend on temporary domains
      // (e.g., *.vercel.app) that do not serve the backend. In that case we
      // want to talk to the canonical backend host instead of the preview
      // origin that would return a 404 for API routes.
      final origin = Uri.base.origin;
      if (origin.contains('.vercel.app') && !origin.contains('fc-teugn.vercel.app')) {
        inferredWebBaseUrl = 'https://fc-teugn.vercel.app';
      } else {
        inferredWebBaseUrl = origin;
      }
    }

    String resolvedBaseUrl;
    if (baseUrl != null) {
      resolvedBaseUrl = baseUrl;
    } else if (envBaseUrl.isNotEmpty) {
      resolvedBaseUrl = envBaseUrl;
    } else {
      final defaultBase = kIsWeb ? inferredWebBaseUrl : 'http://localhost:4000';
      resolvedBaseUrl = kIsWeb ? _withApiPath(defaultBase) : defaultBase;
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

String _withApiPath(String base) {
  final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$normalized/api';
}
