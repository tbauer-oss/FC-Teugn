import 'dart:convert';
import 'pending_operation_keys.dart';
import '../auth/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

typedef Json = Map<String, dynamic>;
List<Json> objects(dynamic value) => (value as List? ?? const [])
    .whereType<Map>()
    .map((item) => Map<String, dynamic>.from(item))
    .toList();

final talentsDataVersionProvider = StateProvider<int>((ref) => 0);

final talentsRepositoryProvider = Provider<TalentsRepository>((ref) =>
    TalentsRepository(ref.watch(repositoryProvider).client.dio,
        keys:
            PendingOperationKeys(ref.watch(authProvider).user?.id ?? 'public'),
        onSaved: () => ref.read(talentsDataVersionProvider.notifier).state++));
final talentsOptionsProvider = FutureProvider.autoDispose<Json>((ref) {
  ref.watch(manualDataRefreshProvider);
  return ref.watch(talentsRepositoryProvider).object('/options');
});

class TalentsRepository {
  TalentsRepository(this.dio, {this.onSaved, PendingOperationKeys? keys})
      : keys = keys ?? PendingOperationKeys('test');
  final PendingOperationKeys keys;
  final void Function()? onSaved;
  final Dio dio;
  Future<dynamic> get(String path, [Json? query]) async =>
      (await dio.get<dynamic>('/talents$path', queryParameters: query)).data;
  Future<Json> object(String path, [Json? query]) async =>
      Map<String, dynamic>.from(await get(path, query) as Map);
  Future<dynamic> save(String path, Json body, {String method = 'POST'}) async {
    final fingerprint = '$method|$path|${jsonEncode(body)}';
    final key = await keys.get(fingerprint);
    try {
      final result = await dio.request<dynamic>('/talents$path',
          data: body,
          options: Options(
              method: method,
              headers: {'x-idempotency-key': key},
              extra: {'requireOnline': true},
              receiveTimeout: const Duration(seconds: 28)));
      await keys.complete(fingerprint);
      onSaved?.call();
      return result.data;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429) {
        await keys.complete(fingerprint);
      }
      rethrow;
    }
  }
}

String talentsError(Object error) {
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map && body['message'] is String) {
      return body['message'] as String;
    }
    return 'Die Verbindung ist gerade nicht verfügbar. Deine Eingaben bleiben erhalten. Bitte erneut versuchen.';
  }
  return 'Der Vorgang konnte nicht abgeschlossen werden. Bitte die Angaben prüfen und erneut versuchen.';
}

String personName(Json value) =>
    value['preferredName']?.toString().isNotEmpty == true
        ? value['preferredName'] as String
        : value['name']?.toString() ??
            '${value['firstName'] ?? ''} ${value['lastName'] ?? ''}'.trim();
String dateString(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String showDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return date == null
      ? '—'
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
