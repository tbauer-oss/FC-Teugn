import 'package:fc_teugn_app/core/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player model accepts numeric variants and incomplete optional data',
      () {
    final player = PlayerModel.fromJson({
      'id': 'player-1',
      'teamId': 'team-e1',
      'firstName': 'Max',
      'lastName': 'Muster',
      'shirtNumber': 8.0,
      'passNumber': 'BFV-001234',
      'status': 'INJURED',
      'injuryType': 'OTHER',
      'injuryDetails': 'Reizung nach Fremdeinwirkung',
      'injurySeverity': 'SEVERE',
      'injuryStartDate': '2026-08-31T00:00:00.000Z',
      'estimatedRecoveryMinDays': '7',
      'estimatedRecoveryMaxDays': 21.0,
      'estimatedReturnFrom': '2026-09-07T00:00:00.000Z',
      'estimatedReturnTo': '2026-09-21T00:00:00.000Z',
      'manualReturnFrom': '2026-09-14T00:00:00.000Z',
      'manualReturnTo': '2026-09-28T00:00:00.000Z',
      'recoveryEstimateOverridden': true,
      'gender': 'DIVERSE',
      'birthDate': '2015-04-08T00:00:00.000Z',
      'joinedAt': '2022-07-01T00:00:00.000Z',
      'team': {
        'name': 'E1-Jugend',
        'teamNumber': '1',
        'ageGroup': {'code': 'E'},
      },
      'statistics': {
        'goals': 4.0,
        'assists': '3',
        'appearances': null,
        'cleanSheets': 5,
        'cleanSheetEligible': true,
      },
      'statisticsBySeason': [
        {
          'seasonId': 'season-1',
          'seasonName': '2026/27',
          'goals': 2.0,
          'assists': '1',
          'cleanSheets': 3,
        },
      ],
      'medicalProfile': 'nicht verfügbar',
    });

    expect(player.fullName, 'Max Muster');
    expect(player.shirtNumber, 8);
    expect(player.passNumber, 'BFV-001234');
    expect(player.status, PlayerStatus.injured);
    expect(player.injuryType, 'OTHER');
    expect(player.injuryDetails, 'Reizung nach Fremdeinwirkung');
    expect(injuryTypeLabel(player.injuryType), 'Sonstige Verletzung');
    expect(player.injurySeverity, InjurySeverity.severe);
    expect(player.injuryStartDate, DateTime.utc(2026, 8, 31));
    expect(player.estimatedRecoveryMinDays, 7);
    expect(player.estimatedRecoveryMaxDays, 21);
    expect(player.effectiveReturnFrom, DateTime.utc(2026, 9, 14));
    expect(player.effectiveReturnTo, DateTime.utc(2026, 9, 28));
    expect(player.recoveryEstimateOverridden, isTrue);
    expect(player.injuryAbsenceLabel, 'ca. 14.09.2026 – 28.09.2026');
    expect(
      player.injuryEstimateNeedsReview(DateTime.utc(2026, 9, 28)),
      isTrue,
    );
    expect(player.gender, PlayerGender.diverse);
    expect(player.birthDate, DateTime.utc(2015, 4, 8));
    expect(player.joinedAt, DateTime.utc(2022, 7, 1));
    expect(player.teamCode, 'E1');
    expect(player.goals, 4);
    expect(player.assists, 3);
    expect(player.appearances, 0);
    expect(player.cleanSheets, 5);
    expect(player.cleanSheetEligible, isTrue);
    expect(player.statisticsBySeason.single.goals, 2);
    expect(player.statisticsBySeason.single.cleanSheets, 3);
    expect(player.medicalProfile, isNull);
  });

  test('player model still rejects responses without a player id', () {
    expect(
      () => PlayerModel.fromJson({
        'firstName': 'Ohne',
        'lastName': 'Kennung',
      }),
      throwsFormatException,
    );
  });

  test('injury estimates stay broad and never clear head injuries', () {
    final strain = estimateInjuryRecovery('STRAIN', InjurySeverity.unknown);
    expect(strain?.minDays, 7);
    expect(strain?.maxDays, 21);
    expect(
      injuryDurationLabel(strain?.minDays, strain?.maxDays),
      'ca. 1–3 Wochen',
    );
    expect(
      estimateInjuryRecovery(
        'HEAD_INJURY_CONCUSSION',
        InjurySeverity.light,
      ),
      isNull,
    );
    expect(injuryDurationLabel(null, null), 'Keine automatische Schätzung');
  });

  test('legacy player responses remain compatible without injury metadata', () {
    final player = PlayerModel.fromJson({
      'id': 'legacy-player',
      'firstName': 'Alt',
      'lastName': 'Bestand',
      'status': 'ACTIVE',
    });

    expect(player.injurySeverity, InjurySeverity.unknown);
    expect(player.injuryStartDate, isNull);
    expect(player.recoveryEstimateOverridden, isFalse);
    expect(player.effectiveReturnTo, isNull);
  });
}
