import 'package:dio/dio.dart';
import 'package:fc_teugn_app/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException failure({int? statusCode}) {
    final request = RequestOptions(path: '/auth/refresh');
    return DioException(
      requestOptions: request,
      response: statusCode == null
          ? null
          : Response<void>(requestOptions: request, statusCode: statusCode),
      type: statusCode == null
          ? DioExceptionType.connectionError
          : DioExceptionType.badResponse,
    );
  }

  test('temporary connection failures keep the stored automatic login', () {
    expect(
      discardStoredSessionAfterRefreshFailure(failure()),
      isFalse,
    );
    expect(
      discardStoredSessionAfterRefreshFailure(failure(statusCode: 503)),
      isFalse,
    );
  });

  test('only definitively invalid sessions remove the stored login', () {
    for (final statusCode in [400, 401, 403]) {
      expect(
        discardStoredSessionAfterRefreshFailure(
          failure(statusCode: statusCode),
        ),
        isTrue,
        reason: 'HTTP $statusCode muss eine ungültige Sitzung beenden.',
      );
    }
  });
}
