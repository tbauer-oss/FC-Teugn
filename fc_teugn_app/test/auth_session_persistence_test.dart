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
    for (final statusCode in [401, 403]) {
      expect(
        discardStoredSessionAfterRefreshFailure(
          failure(statusCode: statusCode),
        ),
        isTrue,
        reason: 'HTTP $statusCode muss eine ungültige Sitzung beenden.',
      );
    }
  });

  test('validation and refresh races preserve the stored login', () {
    expect(
      discardStoredSessionAfterRefreshFailure(failure(statusCode: 400)),
      isFalse,
    );
    expect(
      discardStoredSessionAfterRefreshFailure(failure(statusCode: 409)),
      isFalse,
    );
  });

  test('rotated refresh token conflicts are recognized explicitly', () {
    final request = RequestOptions(path: '/auth/refresh');
    final conflict = DioException(
      requestOptions: request,
      response: Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: 409,
        data: const {'code': 'REFRESH_TOKEN_ROTATED'},
      ),
      type: DioExceptionType.badResponse,
    );
    expect(isRefreshRotationConflict(conflict), isTrue);
    expect(isRefreshRotationConflict(failure(statusCode: 409)), isFalse);
  });
}
