import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OfflineWriteQueuedException implements Exception {
  const OfflineWriteQueuedException();

  @override
  String toString() =>
      'Die Änderung ist vorgemerkt und wird automatisch erneut übertragen.';
}

class QueuedApiWrite {
  const QueuedApiWrite({
    required this.id,
    required this.method,
    required this.path,
    required this.query,
    required this.data,
    required this.createdAt,
  });

  final String id;
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final dynamic data;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'query': query,
        'data': data,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory QueuedApiWrite.fromJson(Map<String, dynamic> json) => QueuedApiWrite(
        id: json['id'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        query: Map<String, dynamic>.from(
          json['query'] as Map<dynamic, dynamic>? ?? const {},
        ),
        data: json['data'],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class GeneralOfflineOutbox {
  GeneralOfflineOutbox({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _maximumWrites = 250;
  static const _maximumAge = Duration(days: 14);
  final FlutterSecureStorage _storage;
  final _random = Random.secure();
  var _syncing = false;

  String _key(String userId) => 'fc_teugn_general_outbox_v1_$userId';

  Future<List<QueuedApiWrite>> pending(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null) return [];
    try {
      final cutoff = DateTime.now().subtract(_maximumAge);
      final values = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(QueuedApiWrite.fromJson)
          .where((item) => item.createdAt.isAfter(cutoff))
          // Freigaben, Trainingsplanänderungen und Benachrichtigungsversand
          // dürfen nach einem Antwort-Timeout nie später unbemerkt erneut
          // abgespielt werden, weil der Server sie bereits ausgeführt haben
          // kann oder inzwischen ein neuerer Stand gespeichert wurde.
          .where(_isSafeToReplay)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _write(userId, values);
      return values;
    } catch (_) {
      await _storage.delete(key: _key(userId));
      return [];
    }
  }

  Future<void> enqueue(String userId, RequestOptions request) async {
    final writes = await pending(userId);
    if (writes.length >= _maximumWrites) {
      throw StateError('Die Offline-Warteschlange ist voll.');
    }
    final id = request.headers['X-Idempotency-Key']?.toString() ??
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    if (writes.any((item) => item.id == id)) return;
    await _write(userId, [
      ...writes,
      QueuedApiWrite(
        id: id,
        method: request.method.toUpperCase(),
        path: request.path,
        query: Map<String, dynamic>.from(request.queryParameters),
        data: request.data,
        createdAt: DateTime.now(),
      ),
    ]);
  }

  Future<void> clearUser(String userId) => _storage.delete(key: _key(userId));

  bool _isSafeToReplay(QueuedApiWrite write) {
    final path = write.path.split('?').first;
    if (path == '/admin/approve') return false;
    if (RegExp(r'^/events/[^/]+/attendance/reminders$').hasMatch(path)) {
      return false;
    }
    if (RegExp(r'^/organization/teams/[^/]+/training-schedule$')
        .hasMatch(path)) {
      return false;
    }
    if (write.method == 'PATCH' &&
        RegExp(r'^/organization/teams/[^/]+$').hasMatch(path)) {
      return false;
    }
    return true;
  }

  Future<int> synchronize(Dio dio, String userId) async {
    if (_syncing) return 0;
    _syncing = true;
    var synchronized = 0;
    try {
      final writes = await pending(userId);
      final remaining = [...writes];
      for (var index = 0; index < writes.length; index++) {
        final write = writes[index];
        try {
          await dio.request<dynamic>(
            write.path,
            data: write.data,
            queryParameters: write.query,
            options: Options(
              method: write.method,
              headers: {'X-Idempotency-Key': write.id},
              extra: {
                'outboxReplay': true,
                'loadingCompletedItems': index,
                'loadingTotalItems': writes.length,
              },
            ),
          );
          remaining.removeWhere((item) => item.id == write.id);
          await _write(userId, remaining);
          synchronized += 1;
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if (status != null &&
              status != 408 &&
              status != 429 &&
              status < 500) {
            // Fachlich abgelehnte, veraltete Änderungen blockieren spätere
            // Einträge nicht dauerhaft.
            remaining.removeWhere((item) => item.id == write.id);
            await _write(userId, remaining);
            continue;
          }
          break;
        }
      }
    } finally {
      _syncing = false;
    }
    return synchronized;
  }

  Future<void> _write(String userId, List<QueuedApiWrite> values) =>
      values.isEmpty
          ? _storage.delete(key: _key(userId))
          : _storage.write(
              key: _key(userId),
              value: jsonEncode(values.map((item) => item.toJson()).toList()),
            );
}

class OfflineOutboxInterceptor extends Interceptor {
  OfflineOutboxInterceptor({
    required this.dio,
    required this.outbox,
    required this.userId,
    this.onSynchronizationComplete,
    this.onQueued,
  });

  final Dio dio;
  final GeneralOfflineOutbox outbox;
  final String userId;
  final void Function(int synchronized)? onSynchronizationComplete;
  final void Function()? onQueued;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra['outboxReplay'] != true) {
      unawaited(
        outbox.synchronize(dio, userId).then((count) {
          if (count > 0) onSynchronizationComplete?.call(count);
        }),
      );
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    if (!_canQueue(request, err)) {
      handler.next(err);
      return;
    }
    try {
      await outbox.enqueue(userId, request);
      onQueued?.call();
      handler.reject(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          error: const OfflineWriteQueuedException(),
          message:
              'Änderung vorgemerkt; die Übertragung wird automatisch erneut versucht.',
        ),
      );
    } catch (_) {
      handler.next(err);
    }
  }

  bool _canQueue(RequestOptions request, DioException error) {
    final method = request.method.toUpperCase();
    if (request.extra['outboxReplay'] == true ||
        request.extra['requireOnline'] == true ||
        method == 'GET' ||
        method == 'HEAD' ||
        request.path.startsWith('/auth/') ||
        request.data is FormData) {
      return false;
    }
    final status = error.response?.statusCode;
    if (status != null) return status == 408 || status == 429 || status >= 500;
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
