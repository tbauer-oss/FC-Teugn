import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/core/push/web_push_registration.dart';
import 'package:fc_teugn_app/core/push/web_push_status.dart';

void main() {
  Future<bool> restore(Map<String, dynamic> state, List<String> calls,
      {bool optIn = true, bool failSave = false}) {
    return restoreWebPushRegistration(
      accountOptIn: optIn,
      vapidPublicKey: 'current-key',
      readStatus: (_) async => WebPushStatus.fromJson({
        'supported': true,
        'permission': 'granted',
        ...state,
      }),
      restoreSubscription: (_) async {
        calls.add('restore');
        return {'endpoint': 'https://push.example/device'};
      },
      saveSubscription: (subscription) async {
        expect(subscription['endpoint'], 'https://push.example/device');
        calls.add('save');
        if (failSave) throw StateError('offline');
      },
    );
  }

  test('valid browser subscription is uploaded again after a failed save',
      () async {
    final calls = <String>[];
    await expectLater(
        restore({'subscribed': true}, calls, failSave: true), throwsStateError);
    expect(await restore({'subscribed': true}, calls), isTrue);
    expect(calls, ['restore', 'save', 'restore', 'save']);
  });

  test('existing device consent works without an old registration form',
      () async {
    final calls = <String>[];
    expect(await restore({'subscribed': true}, calls, optIn: false), isTrue);
    expect(await restore({'keyMismatch': true}, calls, optIn: false), isTrue);
    expect(calls, ['restore', 'save', 'restore', 'save']);
  });

  test('missing subscription is repaired for an opted-in, permitted account',
      () async {
    final calls = <String>[];
    expect(await restore({'subscribed': false}, calls), isTrue);
    expect(calls, ['restore', 'save']);
  });

  test('automatic repair respects device permission and iOS installation',
      () async {
    for (final state in [
      {'permission': 'default'},
      {'permission': 'denied'},
      {'supported': false},
      {'isIos': true, 'isStandalone': false},
    ]) {
      final calls = <String>[];
      expect(await restore(state, calls), isFalse);
      expect(calls, isEmpty);
    }
    final calls = <String>[];
    expect(await restore({}, calls, optIn: false), isFalse);
    expect(calls, isEmpty);
  });
}
