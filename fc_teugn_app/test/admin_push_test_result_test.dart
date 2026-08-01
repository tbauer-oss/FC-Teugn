import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin push result parses delivery diagnostics for both platforms', () {
    final result = AdminPushTestResult.fromJson(const {
      'recipients': 4,
      'subscriptions': 5,
      'sent': 3,
      'failed': 1,
      'pending': 1,
      'skipped': 0,
      'byPlatform': {
        'WEB': {'total': 3},
        'ANDROID': {'total': 2},
      },
      'errors': [
        {'code': 'HTTP_403', 'count': 1},
      ],
    });

    expect(result.recipients, 4);
    expect(result.subscriptions, 5);
    expect(result.sent, 3);
    expect(result.webSubscriptions, 3);
    expect(result.androidSubscriptions, 2);
    expect(result.errors, {'HTTP_403': 1});
    expect(result.allSent, isFalse);
  });
}
