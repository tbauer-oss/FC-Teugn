import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/loading/loading_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic Android push registration remains visually silent', () async {
    final loading = AppLoadingController(
      showDelay: Duration.zero,
      minimumVisibleDuration: Duration.zero,
    );
    addTearDown(loading.dispose);
    final client = ApiClient(
      baseUrl: 'https://example.test',
      loadingController: loading,
    );
    final requests = <RequestOptions>[];
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('/subscriptions')
                  ? <String, dynamic>{'id': 'device-1'}
                  : <String, dynamic>{},
            ),
          );
        },
      ),
    );
    final repository = DataRepository(client);

    await repository.grantPushConsent(silent: true);
    await repository.registerAndroidPushSubscription(
      'token-1',
      silent: true,
    );

    expect(requests, hasLength(2));
    expect(
      requests.every((request) => request.extra['suppressLoading'] == true),
      isTrue,
    );
    expect(loading.operationCount, 0);
    expect(loading.backgroundOperation, isNull);
  });
}
