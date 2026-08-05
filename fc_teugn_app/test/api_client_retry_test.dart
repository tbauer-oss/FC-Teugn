import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/loading/loading_controller.dart';
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

  test('explicitly idempotent squad PUT retries once', () async {
    var putCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      putCalls++;
      request.response.headers.contentType = ContentType.json;
      if (putCalls == 1) {
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
    expect(putCalls, 2);
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
}
