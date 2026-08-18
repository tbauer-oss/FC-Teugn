import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/competition_import.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/providers.dart';
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

class _ImportRepository extends DataRepository {
  _ImportRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  Set<String>? appliedRowIds;

  @override
  Future<CompetitionImportPreview> previewCompetitionImport({
    required String teamId,
    required CompetitionImportFormat format,
    required String provider,
    required String content,
    String? fileName,
  }) async =>
      CompetitionImportPreview.fromJson({
        'id': 'import-1',
        'totalRows': 2,
        'createCount': 2,
        'updateCount': 0,
        'skipCount': 0,
        'conflictCount': 0,
        'invalidCount': 0,
        'rows': [
          {
            'id': 'row-match',
            'rowNumber': 1,
            'action': 'CREATE',
            'normalized': {
              'opponent': 'TSV Muster E1',
              'startAt': '2026-08-22T09:00:00.000Z',
            },
            'messages': <String>[],
          },
          {
            'id': 'row-free',
            'rowNumber': 2,
            'action': 'CREATE',
            'normalized': {
              'opponent': 'SPIELFREI',
              'startAt': '2026-08-29T21:59:00.000Z',
            },
            'messages': <String>[],
          },
        ],
      });

  @override
  Future<void> applyCompetitionImport(
    String importId, {
    bool sourceWinsConflicts = false,
    Set<String>? selectedRowIds,
  }) async {
    appliedRowIds = selectedRowIds;
  }
}

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

  testWidgets('all matches start selected and SPIELFREI can be excluded',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ImportRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
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
    );

    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    final manualImport = find.text('Erweitert: Inhalt manuell einfügen');
    await tester.ensureVisible(manualImport);
    await tester.tap(manualImport);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'BEGIN:VCALENDAR\nEND:VCALENDAR',
    );
    await tester.pump();
    final previewButton = find.widgetWithText(FilledButton, 'Spiele prüfen');
    expect(previewButton, findsOneWidget);
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.text('2 von 2 Terminen ausgewählt'), findsOneWidget);
    expect(find.textContaining('„SPIELFREI“ ist kein echtes Spiel'),
        findsOneWidget);
    final freeCheckbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('competition-import-row-row-free')),
    );
    expect(freeCheckbox.value, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('competition-import-row-row-free')),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 von 2 Terminen ausgewählt'), findsOneWidget);
    expect(find.text('1 Spiel importieren'), findsOneWidget);

    await tester.tap(find.text('1 Spiel importieren'));
    await tester.pumpAndSettle();
    expect(repository.appliedRowIds, {'row-match'});
    expect(tester.takeException(), isNull);
  });
}
