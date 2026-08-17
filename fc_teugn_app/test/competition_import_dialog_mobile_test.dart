import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/features/imports/competition_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _ageGroup = AgeGroupSummary(
  id: 'age-e',
  name: 'E-Jugend',
  code: 'E',
);

const _team = TeamSummary(
  id: 'team-e1',
  name: 'E1',
  ageGroup: _ageGroup,
  seasonName: '2026/27',
);

final _organization = OrganizationContext(
  club: const ClubSummary(
    id: 'club-fct',
    name: 'FC Teugn',
    shortName: 'FCT',
    primaryColor: '#171918',
    accentColor: '#FFE600',
  ),
  season: SeasonSummary(
    id: 'season-1',
    name: '2026/27',
    startDate: DateTime(2026, 7, 1),
    endDate: DateTime(2027, 6, 30),
    isActive: true,
  ),
  currentTeam: _team,
  ageGroups: const [_ageGroup],
  teams: const [_team],
  permissions: const {},
  metrics: const OrganizationMetrics(
    players: 0,
    members: 0,
    upcomingEvents: 0,
    pendingApprovals: 0,
  ),
);

void main() {
  testWidgets('file import remains usable on a narrow mobile pane',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => CompetitionImportDialog(
                        organization: _organization,
                      ),
                    ),
                    child: const Text('Öffnen'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Spielplan importieren'), findsOneWidget);
    expect(find.text('ICS- oder CSV-Datei auswählen'), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-dialog-scroll-view')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
