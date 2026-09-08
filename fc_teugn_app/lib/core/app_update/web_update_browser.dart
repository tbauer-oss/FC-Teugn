import 'dart:js_interop';
import 'package:dio/dio.dart';
import 'app_release.dart';

@JS('window.location.reload')
external void reloadWebApp();

Future<String?> checkWebUpdate() async {
  final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8)));
  try {
    final uri = Uri.base.resolve('/version.json').replace(queryParameters: {
      'update': '${DateTime.now().millisecondsSinceEpoch}'
    });
    final response = await dio.getUri<Map<String, dynamic>>(uri,
        options: Options(headers: {'Cache-Control': 'no-cache'}));
    final build = int.tryParse('${response.data?['build_number']}');
    if (build == null) {
      throw const FormatException('Ungültige Versionsinformation');
    }
    return build > appReleaseBuild ? '${response.data?['version']}' : null;
  } finally {
    dio.close();
  }
}
