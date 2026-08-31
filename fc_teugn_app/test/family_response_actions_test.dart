import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/shared/family_responses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RefreshingRepository extends DataRepository {
  _RefreshingRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  var calls = 0;

  @override
  Future<List<PersonalResponseModel>> personalResponses({
    DateTime? from,
    DateTime? to,
  }) async {
    calls++;
    return [
      _response(
        eventId: 'event-$calls',
        title: calls == 1 ? 'Training' : 'Freundschaftsspiel',
      ),
    ];
  }
}

class _SeriesRepository extends DataRepository {
  _SeriesRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  var calendarCalls = 0;
  var confirmationCalls = 0;

  @override
  Future<List<EventModel>> events({
    DateTime? from,
    DateTime? to,
    List<String> teamIds = const [],
    List<EventCategory> categories = const [],
    List<EventType> types = const [],
  }) async {
    calendarCalls++;
    return const [];
  }

  @override
  Future<RegularTrainingSeriesConfirmation> confirmRegularTrainingSeries({
    required String eventId,
    required String playerId,
    int? periodMonths,
  }) async {
    confirmationCalls++;
    return (
      validUntil: DateTime.now().add(const Duration(days: 31)),
      appliedCurrent: true,
      preservedDeclines: 0,
    );
  }
}

PersonalResponseModel _response({
  String eventId = 'event-1',
  String title = 'Training',
  AttendanceStatus status = AttendanceStatus.unknown,
  bool canRespond = true,
  String? reason,
  String type = 'TRAINING',
  String category = 'TRAINING',
  DateTime? startAt,
  bool isRegularTraining = false,
}) {
  return PersonalResponseModel(
    eventId: eventId,
    playerId: 'player-1',
    playerName: 'Max Muster',
    teamName: 'E1-Jugend',
    ageGroupCode: 'E1',
    title: title,
    type: type,
    category: category,
    startAt: startAt ?? DateTime.now().add(const Duration(days: 3)),
    location: 'Sportplatz Teugn',
    responseStatus: status,
    reason: reason,
    canRespond: canRespond,
    isOverdue: false,
    isRegularTraining: isRegularTraining,
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  PersonalResponseModel response,
) async {
  tester.view.physicalSize = const Size(1100, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalResponsesProvider.overrideWith((ref) async => [response]),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const FamilyResponsesPage(isTrainer: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'family response offers only yes or no and optional decline reason',
      (tester) async {
    await _pumpPage(tester, _response());

    expect(find.text('Vielleicht'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Zusagen'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Absagen'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Absagen'));
    await tester.pumpAndSettle();

    expect(find.text('Max Muster absagen?'), findsOneWidget);
    expect(find.text('Grund (optional)'), findsOneWidget);
    expect(find.text('z. B. krank oder verhindert'), findsOneWidget);
  });

  testWidgets('match response only offers accept or decline', (tester) async {
    await _pumpPage(
      tester,
      _response(
        title: 'Punktspiel',
        type: 'MATCH',
        category: 'LEAGUE_MATCH',
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Zusagen'), findsOneWidget);
    expect(find.text('Vielleicht'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Absagen'), findsOneWidget);
  });

  testWidgets('regular training offers clear bulk confirmation periods',
      (tester) async {
    await _pumpPage(
      tester,
      _response(isRegularTraining: true),
    );

    expect(find.text('Mehrere Trainings zusagen'), findsOneWidget);
    await tester.tap(find.text('Mehrere Trainings zusagen'));
    await tester.pumpAndSettle();

    expect(find.text('Regeltraining gesammelt zusagen'), findsOneWidget);
    expect(find.text('1 Monat'), findsOneWidget);
    expect(find.text('3 Monate'), findsOneWidget);
    expect(find.text('6 Monate'), findsOneWidget);
    expect(find.text('Bis Saisonende'), findsOneWidget);
    expect(
      find.textContaining('Bereits eingetragene Absagen bleiben bestehen'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk confirmation immediately refreshes the active calendar',
      (tester) async {
    final repository = _SeriesRepository();
    final now = DateTime.now();
    final range = (
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month + 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          personalResponsesProvider.overrideWith(
            (ref) async => [_response(isRegularTraining: true)],
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Consumer(
            builder: (context, ref, child) {
              ref.watch(calendarEventsProvider(range));
              return const Scaffold(
                body: FamilyResponsesPage(isTrainer: false),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calendarCalls, 1);

    await tester.tap(find.text('Mehrere Trainings zusagen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Monat'));
    await tester.pumpAndSettle();

    expect(repository.confirmationCalls, 1);
    expect(repository.calendarCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved decline reason is visible in family response',
      (tester) async {
    await _pumpPage(
      tester,
      _response(
        status: AttendanceStatus.no,
        canRespond: false,
        reason: 'Krank',
      ),
    );

    expect(find.text('Grund: Krank'), findsOneWidget);
  });

  testWidgets('several family responses stay compact at 320 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalResponsesProvider.overrideWith(
            (ref) async => [
              _response(eventId: 'event-1', title: 'Training'),
              _response(eventId: 'event-2', title: 'Freundschaftsspiel'),
              _response(eventId: 'event-3', title: 'Mannschaftsabend'),
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const FamilyResponsesPage(isTrainer: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('family-response-summary-scroll')),
      findsOneWidget,
    );
    expect(find.text('Freundschaftsspiel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual refresh signal reloads visible family responses',
      (tester) async {
    final repository = _RefreshingRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const FamilyResponsesPage(isTrainer: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsOneWidget);
    expect(repository.calls, 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FamilyResponsesPage)),
    );
    container.read(manualDataRefreshProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.text('Freundschaftsspiel'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('one week is selected and parents can extend the response period',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalResponsesProvider.overrideWith(
            (ref) async => [
              _response(
                eventId: 'near',
                title: 'Training diese Woche',
                startAt: now.add(const Duration(days: 2)),
              ),
              _response(
                eventId: 'later',
                title: 'Training in drei Wochen',
                startAt: now.add(const Duration(days: 20)),
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const FamilyResponsesPage(isTrainer: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Woche'), findsOneWidget);
    expect(find.text('Training diese Woche'), findsOneWidget);
    expect(find.text('Training in drei Wochen'), findsNothing);

    await tester.tap(find.text('1 Woche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 Wochen').last);
    await tester.pumpAndSettle();

    expect(find.text('Training in drei Wochen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
