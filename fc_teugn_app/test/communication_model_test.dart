import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses targeted announcements and read state', () {
    final announcement = AnnouncementModel.fromJson({
      'id': 'announcement-1',
      'title': 'Turnier am Samstag',
      'body': 'Treffpunkt ist um 08:30 Uhr.',
      'audience': 'PARENTS',
      'priority': 'URGENT',
      'status': 'PUBLISHED',
      'author': {'name': 'Trainerteam'},
      'targetTeams': [
        {
          'team': {'name': 'E1', 'shortName': 'E1'},
        },
      ],
      'requireReadReceipt': true,
      'pushEnabled': true,
      'isRead': false,
      'readCount': 12,
      'publishAt': '2026-08-01T08:00:00.000Z',
      'attachments': [
        {
          'name': 'Turnierplan.pdf',
          'url': 'https://example.test/turnierplan.pdf',
          'mimeType': 'application/pdf',
        },
      ],
    });

    expect(announcement.audience, AnnouncementAudience.parents);
    expect(announcement.priority, AnnouncementPriority.urgent);
    expect(announcement.teamNames, ['E1']);
    expect(announcement.readCount, 12);
    expect(announcement.attachments.single.name, 'Turnierplan.pdf');
  });

  test('serializes communication enums for the API', () {
    expect(
      communicationApiEnum(NotificationCategory.eventReminder),
      'EVENT_REMINDER',
    );
    expect(
      communicationApiEnum(AnnouncementAudience.allMembers),
      'ALL_MEMBERS',
    );
  });

  test('parses notification preferences and push configuration', () {
    final preference = NotificationPreferenceModel.fromJson({
      'category': 'LIVE_TICKER',
      'inApp': true,
      'push': false,
    });
    final configuration = PushConfiguration.fromJson({
      'webPushConfigured': true,
      'androidConfigured': false,
      'vapidPublicKey': 'public-key',
    });

    expect(preference.category, NotificationCategory.liveTicker);
    expect(preference.push, false);
    expect(configuration.webPushConfigured, true);
    expect(configuration.androidConfigured, false);
  });

  test('parses recreational pitch priority as information-only conflict', () {
    final conflict = PitchConflictPreview.fromJson({
      'kind': 'RECREATIONAL',
      'requiresApproval': false,
      'trainingTeamId': 'recreational:season-1',
      'trainingTeamName': 'Freizeitkicker',
      'ageGroupCode': '',
      'trainingScheduleValue': 'Dienstag 17:30–19:00 · Platz: Platz 1 unten',
      'weekday': 'Dienstag',
      'startLabel': '17:30',
      'endLabel': '19:00',
      'pitch': 'Platz 1 unten',
      'headCoach': null,
    });

    expect(conflict.kind, 'RECREATIONAL');
    expect(conflict.requiresApproval, isFalse);
    expect(conflict.headCoach, isNull);
  });
}
