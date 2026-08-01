import 'package:fc_teugn_app/core/push/web_push_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS web push requires the installed home-screen app', () {
    final status = WebPushStatus.fromJson(const {
      'supported': false,
      'subscribed': false,
      'isIos': true,
      'isStandalone': false,
      'permission': 'unavailable',
    });

    expect(status.requiresHomeScreen, isTrue);
    expect(status.canSubscribe, isFalse);
  });

  test('installed iOS web app can subscribe to standards-based push', () {
    final status = WebPushStatus.fromJson(const {
      'supported': true,
      'subscribed': false,
      'isIos': true,
      'isStandalone': true,
      'permission': 'default',
    });

    expect(status.requiresHomeScreen, isFalse);
    expect(status.canSubscribe, isTrue);
    expect(status.permission, WebPushPermission.prompt);
  });

  test('existing browser subscription is shown as active', () {
    final status = WebPushStatus.fromJson(const {
      'supported': true,
      'subscribed': true,
      'isIos': false,
      'isStandalone': false,
      'permission': 'granted',
    });

    expect(status.subscribed, isTrue);
    expect(status.permission, WebPushPermission.granted);
  });

  test('subscription with an outdated VAPID key is offered for renewal', () {
    final status = WebPushStatus.fromJson(const {
      'supported': true,
      'subscribed': false,
      'keyMismatch': true,
      'isIos': false,
      'isStandalone': false,
      'permission': 'granted',
    });

    expect(status.keyMismatch, isTrue);
    expect(status.canSubscribe, isTrue);
  });
}
