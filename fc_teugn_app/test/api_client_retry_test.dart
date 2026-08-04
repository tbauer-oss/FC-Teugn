import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
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
}
