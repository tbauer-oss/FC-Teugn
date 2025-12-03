import 'package:dio/dio.dart';

class ApiClient {
  final Dio dio;

  ApiClient._internal(this.dio);

  factory ApiClient({String? baseUrl, String? accessToken}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? 'http://localhost:4000',
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
