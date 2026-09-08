import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/push/apple_push_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple registration waits for APNs before requesting an FCM token',
      () async {
    var attempts = 0;
    var fcmCalls = 0;
    final token = await applePushRegistrationToken(
      readApnsToken: () async => ++attempts == 3 ? 'apns-ready' : null,
      readFcmToken: () async {
        fcmCalls++;
        return 'fcm-ready';
      },
      retryDelay: Duration.zero,
    );
    expect(token, 'fcm-ready');
    expect(attempts, 3);
    expect(fcmCalls, 1);
  });
  test('missing APNs is retryable and never calls FCM prematurely', () async {
    var fcmCalls = 0;
    await expectLater(
        applePushRegistrationToken(
          readApnsToken: () async => null,
          readFcmToken: () async {
            fcmCalls++;
            return 'invalid';
          },
          retryDelay: Duration.zero,
          attempts: 3,
        ),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'IOS_APNS_NOT_READY')));
    expect(fcmCalls, 0);
  });
  test('native iOS device registers as IOS without browser subscription keys',
      () async {
    final client = ApiClient(baseUrl: 'https://example.test');
    RequestOptions? request;
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      request = options;
      handler.resolve(Response(
          requestOptions: options,
          data: {'id': 'ios-device'},
          statusCode: 201));
    }));
    expect(
        await DataRepository(client).registerNativePushSubscription('fcm-token',
            platform: 'IOS', silent: true),
        'ios-device');
    expect(request!.data['platform'], 'IOS');
    expect(request!.data['deviceName'], contains('iPhone'));
    expect(request!.data['p256dh'], isNull);
    expect(request!.extra['suppressLoading'], isTrue);
  });
}
