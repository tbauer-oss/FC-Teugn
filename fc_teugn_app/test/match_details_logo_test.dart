import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('match details preserve the opponent crest for matchday and ticker', () {
    final details = MatchDetailsModel.fromJson({
      'opponent': 'ATSV Kelheim E2',
      'opponentLogoUrl': 'https://cdn.example.test/kelheim.png',
      'isHome': false,
      'status': 'PLANNED',
      'durationMinutes': 60,
      'periodMinutes': 15,
      'periodCount': 4,
    });

    expect(details.opponentLogoUrl, 'https://cdn.example.test/kelheim.png');
    expect(details.periodCount, 4);
  });
}
