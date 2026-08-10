import 'package:fc_teugn_app/core/football_options.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the event category when match details have no competition', () {
    expect(
      footballCompetitionForEvent(category: EventCategory.friendlyMatch),
      'Freundschaftsspiel',
    );
    expect(
      footballCompetitionForEvent(category: EventCategory.leagueMatch),
      'Liga',
    );
    expect(
      footballCompetitionForEvent(category: EventCategory.cupMatch),
      'Pokal',
    );
  });

  test('keeps the competition explicitly stored with the match', () {
    expect(
      footballCompetitionForEvent(
        category: EventCategory.friendlyMatch,
        storedCompetition: 'Testspiel',
      ),
      'Testspiel',
    );
  });
}
