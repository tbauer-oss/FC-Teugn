import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/loading/loading_controller.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/offline_outbox.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GET requests recover automatically from transient server failures',
      () async {
    var getCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      getCalls++;
      request.response.headers.contentType = ContentType.json;
      if (getCalls < 3) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(jsonEncode({'message': 'warming up'}));
      } else {
        request.response.write(jsonEncode({'ready': true}));
      }
      await request.response.close();
    });

    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );
    final response = await client.dio.get<Map<String, dynamic>>('/startup');

    expect(response.data, {'ready': true});
    expect(getCalls, 3);
  });

  test('write requests are never repeated automatically', () async {
    var postCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      postCalls++;
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'not available'}));
      await request.response.close();
    });

    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );

    await expectLater(
      client.dio.post<void>('/events', data: {'title': 'Training'}),
      throwsA(isA<DioException>()),
    );
    expect(postCalls, 1);
  });

  test('explicitly idempotent writes survive two transient failures', () async {
    var putCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      putCalls++;
      request.response.headers.contentType = ContentType.json;
      if (putCalls < 3) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(jsonEncode({'message': 'warming up'}));
      } else {
        request.response.write(jsonEncode({'saved': true}));
      }
      await request.response.close();
    });

    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );
    final response = await client.dio.put<Map<String, dynamic>>(
      '/matches/match-1/squad',
      data: {'members': const []},
      options: Options(
        extra: const {'retryTransientWrite': true},
      ),
    );

    expect(response.data, {'saved': true});
    expect(putCalls, 3);
  });

  test('permanent client errors are not repeated', () async {
    var getCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      getCalls++;
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'forbidden'}));
      await request.response.close();
    });

    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );

    await expectLater(
      client.dio.get<void>('/protected'),
      throwsA(isA<DioException>()),
    );
    expect(getCalls, 1);
  });

  test('member approval retries safely but is never put into offline outbox',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    var postCalls = 0;
    final idempotencyKeys = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      postCalls++;
      idempotencyKeys.add(request.headers.value('x-idempotency-key'));
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'warming up'}));
      await request.response.close();
    });
    final outbox = GeneralOfflineOutbox();
    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
      offlineOutbox: outbox,
      userId: 'admin-1',
    );
    final repository = DataRepository(client);

    await expectLater(
      repository.approveUser(
        'pending-1',
        status: AccountStatus.approved,
      ),
      throwsA(isA<DioException>()),
    );

    expect(postCalls, 3);
    final uniqueIdempotencyKeys = idempotencyKeys.toSet();
    expect(uniqueIdempotencyKeys, hasLength(1));
    expect(uniqueIdempotencyKeys.single, isNotEmpty);
    expect(await outbox.pending('admin-1'), isEmpty);
  });

  test('legacy queued admin and schedule writes are discarded', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    FlutterSecureStorage.setMockInitialValues({
      'fc_teugn_general_outbox_v1_admin-2': jsonEncode([
        {
          'id': 'approval',
          'method': 'POST',
          'path': '/admin/approve',
          'query': <String, dynamic>{},
          'data': {'userId': 'pending-1'},
          'createdAt': now,
        },
        {
          'id': 'schedule',
          'method': 'PATCH',
          'path': '/organization/teams/e1/training-schedule',
          'query': <String, dynamic>{},
          'data': {'trainingTimes': const []},
          'createdAt': now,
        },
        {
          'id': 'reminder',
          'method': 'POST',
          'path': '/events/event-1/attendance/reminders',
          'query': <String, dynamic>{},
          'data': {'audience': 'OPEN', 'pushEnabled': true},
          'createdAt': now,
        },
        {
          'id': 'attendance',
          'method': 'PUT',
          'path': '/events/event-1/attendance/player-1',
          'query': <String, dynamic>{},
          'data': {'status': 'YES'},
          'createdAt': now,
        },
      ]),
    });

    final pending = await GeneralOfflineOutbox().pending('admin-2');

    expect(pending.map((write) => write.id), ['attendance']);
  });

  test('manual reminders are never queued or automatically repeated', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var postCalls = 0;
    final idempotencyKeys = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      postCalls++;
      idempotencyKeys.add(request.headers.value('x-idempotency-key'));
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'not available'}));
      await request.response.close();
    });
    final outbox = GeneralOfflineOutbox();
    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
      offlineOutbox: outbox,
      userId: 'trainer-1',
    );
    final repository = DataRepository(client);

    await expectLater(
      repository.sendAttendanceReminders('event-1'),
      throwsA(isA<DioException>()),
    );

    expect(postCalls, 1);
    expect(idempotencyKeys.single, isNotEmpty);
    expect(await outbox.pending('trainer-1'), isEmpty);
  });

  test('routine writes use one non-blocking loading operation', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      arrived.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'saved': true}));
      await request.response.close();
    });
    final loading = AppLoadingController(
      showDelay: Duration.zero,
      minimumVisibleDuration: Duration.zero,
    );
    addTearDown(loading.dispose);
    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
      loadingController: loading,
    );

    final request = client.dio.post<void>(
      '/matches/match-1/squad',
      data: {'members': const []},
    );
    await arrived.future;
    expect(loading.blockingVisible, isFalse);
    expect(loading.backgroundVisible, isTrue);
    expect(loading.backgroundOperation?.message, 'Kader wird gespeichert …');

    release.complete();
    await request;
    expect(loading.hasOperations, isFalse);
    expect(loading.blockingVisible, isFalse);
    expect(loading.backgroundVisible, isFalse);
  });

  test('automatic outbox replay stays visually silent', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      arrived.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'saved': true}));
      await request.response.close();
    });
    final loading = AppLoadingController(
      showDelay: Duration.zero,
      minimumVisibleDuration: Duration.zero,
    );
    addTearDown(loading.dispose);
    final client = ApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
      loadingController: loading,
    );

    final request = client.dio.post<void>(
      '/events/offline-event',
      data: {'title': 'Offline-Training'},
      options: Options(extra: const {'outboxReplay': true}),
    );
    await arrived.future;

    expect(loading.hasOperations, isFalse);
    expect(loading.backgroundVisible, isFalse);
    expect(loading.blockingVisible, isFalse);

    release.complete();
    await request;
  });
}
