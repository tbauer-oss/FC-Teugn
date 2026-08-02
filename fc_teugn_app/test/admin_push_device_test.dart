import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('administratively disabled push device exposes owner and state', () {
    final device = AdminPushDevice.fromJson({
      'id': 'device-1',
      'platform': 'ANDROID',
      'deviceName': 'Tobias · Android',
      'isActive': false,
      'health': 'DISABLED',
      'lastUsedAt': '2026-08-01T10:00:00.000Z',
      'createdAt': '2026-07-01T10:00:00.000Z',
      'updatedAt': '2026-08-02T10:00:00.000Z',
      'administrativelyDisabledAt': '2026-08-02T10:00:00.000Z',
      'deliveryCount': 12,
      'lastDelivery': {
        'status': 'FAILED',
        'errorCode': 'DEVICE_DISABLED_BY_ADMIN',
        'createdAt': '2026-08-02T09:00:00.000Z',
      },
      'user': {
        'id': 'user-1',
        'name': 'Tobias Bauer',
        'email': 'tobias@example.test',
        'role': 'SUPER_ADMIN',
        'status': 'APPROVED',
        'team': {'name': 'E1-Jugend'},
      },
    });

    expect(device.isAndroid, isTrue);
    expect(device.isActive, isFalse);
    expect(device.isAdministrativelyDisabled, isTrue);
    expect(device.health, PushDeviceHealth.disabled);
    expect(device.userName, 'Tobias Bauer');
    expect(device.roleLabel, 'Systemadministration');
    expect(device.teamName, 'E1-Jugend');
    expect(device.deliveryCount, 12);
    expect(device.lastDeliveryError, 'DEVICE_DISABLED_BY_ADMIN');
  });

  test('stale web device is parsed without a delivery history', () {
    final device = AdminPushDevice.fromJson({
      'id': 'device-2',
      'platform': 'WEB',
      'deviceName': null,
      'isActive': true,
      'health': 'STALE',
      'lastUsedAt': '2026-04-01T10:00:00.000Z',
      'createdAt': '2026-03-01T10:00:00.000Z',
      'updatedAt': '2026-04-01T10:00:00.000Z',
      'deliveryCount': 0,
      'lastDelivery': null,
      'user': {
        'id': 'user-2',
        'name': 'Elternteil',
        'email': 'eltern@example.test',
        'role': 'PARENT',
        'status': 'APPROVED',
        'team': {'name': 'F1-Jugend'},
      },
    });

    expect(device.deviceName, 'Unbenanntes Gerät');
    expect(device.isStale, isTrue);
    expect(device.isActive, isTrue);
    expect(device.lastDeliveryStatus, isNull);
  });
}
