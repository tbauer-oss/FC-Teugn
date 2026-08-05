import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matchday exposes player confirmations for automatic lineup planning',
      () {
    final match = MatchdayModel.fromJson({
      'id': 'match-1',
      'title': 'FC Teugn – Test',
      'startAt': '2026-08-08T10:00:00.000Z',
      'teamId': 'team-1',
      'attendance': [
        {
          'id': 'reply-1',
          'playerId': 'player-1',
          'status': 'YES',
          'player': {
            'id': 'player-1',
            'firstName': 'Max',
            'lastName': 'Stark',
          },
        },
      ],
    });

    expect(match.attendance, hasLength(1));
    expect(match.attendance.single.playerId, 'player-1');
    expect(match.attendance.single.status, AttendanceStatus.yes);
  });
}
