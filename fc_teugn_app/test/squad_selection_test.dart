import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/squad_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes unavailable historic members before saving the squad', () {
    final selection = <String, NominationStatus>{
      'active-player': NominationStatus.nominated,
      'moved-player': NominationStatus.nominated,
      'paused-player': NominationStatus.onCall,
    };

    final eligible = retainEligibleSquadSelection(
      selection,
      const ['active-player'],
    );

    expect(eligible, {
      'active-player': NominationStatus.nominated,
    });
    expect(selection, hasLength(3),
        reason: 'The helper must not mutate input.');
  });
}
