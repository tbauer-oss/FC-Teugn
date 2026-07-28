import 'package:fc_teugn_app/core/models/emergency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a minimal, event-scoped emergency view', () {
    final view = EmergencyView.fromJson({
      'event': {
        'id': 'event-1',
        'title': 'Auswärtsspiel',
        'startAt': '2026-08-10T08:00:00.000Z',
        'location': 'Musterstadt',
      },
      'generatedAt': '2026-08-10T08:15:00.000Z',
      'presenceSource': 'ACTUAL_ATTENDANCE',
      'players': [
        {
          'id': 'player-1',
          'firstName': 'Mia',
          'lastName': 'Muster',
          'guardians': [
            {
              'id': 'parent-1',
              'name': 'Max Muster',
              'phone': '+491701234567',
              'relationship': 'FATHER',
              'isLegalGuardian': true,
              'canPickup': true,
            },
          ],
          'emergencyContacts': [
            {
              'id': 'contact-1',
              'name': 'Erika Muster',
              'phone': '+491709876543',
              'priority': 1,
              'isAuthorizedPickup': false,
            },
          ],
          'medical': {
            'allergies': 'Erdnüsse',
            'medications': null,
            'conditions': null,
            'emergencyNotes': 'Notfallset im Rucksack',
          },
        },
      ],
    });

    expect(view.usesActualAttendance, isTrue);
    expect(view.players.single.name, 'Mia Muster');
    expect(view.players.single.guardians.single.phone, '+491701234567');
    expect(view.players.single.emergencyContacts.single.priority, 1);
    expect(view.players.single.medical.hasInformation, isTrue);
  });

  test('emergency access grant parses its local expiry', () {
    final grant = EmergencyAccessGrant.fromJson({
      'token': 'temporary',
      'expiresAt': '2026-08-10T08:20:00.000Z',
    });

    expect(grant.token, 'temporary');
    expect(grant.expiresAt.isUtc, isFalse);
  });
}
