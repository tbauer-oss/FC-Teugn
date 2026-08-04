import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transient initial API failure is retried before showing an error',
      () async {
    var attempts = 0;

    final result = await loadWithTransientRetry(
      () async {
        attempts++;
        if (attempts == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/admin/pending-users'),
            type: DioExceptionType.connectionError,
          );
        }
        return const ['aktuell'];
      },
      initialDelay: Duration.zero,
    );

    expect(result, const ['aktuell']);
    expect(attempts, 2);
  });

  test('authorization errors are not hidden behind automatic retries',
      () async {
    var attempts = 0;

    await expectLater(
      loadWithTransientRetry(
        () async {
          attempts++;
          throw DioException(
            requestOptions: RequestOptions(path: '/admin/pending-users'),
            response: Response<void>(
              requestOptions: RequestOptions(path: '/admin/pending-users'),
              statusCode: 403,
            ),
          );
        },
        initialDelay: Duration.zero,
      ),
      throwsA(isA<DioException>()),
    );

    expect(attempts, 1);
  });
}
