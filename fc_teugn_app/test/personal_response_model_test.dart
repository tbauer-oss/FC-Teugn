import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personal response parses child, deadline and guardian action state',
      () {
    final response = PersonalResponseModel.fromJson({
      'eventId': 'event-1',
      'playerId': 'player-2',
      'playerName': 'Max',
      'teamName': 'E1',
      'ageGroupCode': 'E',
      'title': 'FC Teugn gegen Musterverein',
      'category': 'FRIENDLY_MATCH',
      'startAt': '2026-08-14T15:00:00.000Z',
      'location': 'Stadion am Kreutweg, Teugn',
      'responseDeadline': '2026-08-13T15:00:00.000Z',
      'responseStatus': 'UNKNOWN',
      'canRespond': true,
      'isOverdue': false,
    });

    expect(response.playerName, 'Max');
    expect(response.responseStatus, AttendanceStatus.unknown);
    expect(response.isOpen, isTrue);
    expect(response.canRespond, isTrue);
    expect(response.responseDeadline, isNotNull);
  });

  test('legacy maybe response remains actionable as open', () {
    final response = PersonalResponseModel.fromJson({
      'eventId': 'event-legacy',
      'playerId': 'player-legacy',
      'playerName': 'Legacy',
      'title': 'Training',
      'category': 'TRAINING',
      'startAt': '2026-08-26T15:15:00.000Z',
      'responseStatus': 'MAYBE',
      'canRespond': true,
      'isOverdue': false,
    });

    expect(response.responseStatus, AttendanceStatus.unknown);
    expect(response.isOpen, isTrue);
  });
}
