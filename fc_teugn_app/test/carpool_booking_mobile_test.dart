import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/carpool/carpool_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _event({int free = 5, int needs = 0, bool guest = false}) =>
    EventModel.fromJson({
      'id': 'match-ride',
      'teamId': 'team',
      'type': 'MATCH',
      'category': 'FRIENDLY_MATCH',
      'status': 'SCHEDULED',
      'visibility': 'TEAM',
      'title': 'Gastmannschaft – FC Teugn E1',
      'startAt': '2030-09-17T15:30:00Z',
      'location': 'Sportplatz',
      'capabilities': {'canOfferRide': true, 'canRespond': true},
      if (guest) 'carpoolPlayerIds': ['guest-child'],
      'carpoolSummary': {
        'freeSeats': free,
        'openNeeds': needs,
        'bookedSeats': 5 - free,
        'offers': 1
      },
      'carpoolOffers': [
        {
          'id': 'offer',
          'driverId': 'driver',
          'driver': {'name': 'Fahrerin Beispiel', 'phone': '000000'},
          'seatsTotal': 5,
          'freeSeats': free,
          'departureAt': '2030-09-17T14:30:00Z',
          'departureLocation': 'Vereinsheim FC Teugn',
          'notes': 'Treffpunkt am Haupteingang',
          'passengers': [],
          'canManage': false,
        }
      ],
      'carpoolNeeds': [
        if (needs > 0)
          {
            'id': 'need',
            'playerId': 'waiting',
            'player': {'firstName': 'Wartendes', 'lastName': 'Kind'},
            'status': 'OPEN'
          }
      ],
    });

const _players = [
  PlayerModel(
      id: 'child-1',
      firstName: 'Erstes',
      lastName: 'Kind',
      teamId: 'team',
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right),
  PlayerModel(
      id: 'child-2',
      firstName: 'Zweites',
      lastName: 'Kind',
      teamId: 'team',
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right),
];

class _Repository implements DataRepository {
  List<String>? booked;
  bool? self;
  bool fail = false;
  int calls = 0;
  @override
  Future<void> bookCarpoolSeats(
      {required String eventId,
      required String offerId,
      required List<String> playerIds,
      bool includeSelf = false}) async {
    calls++;
    if (fail) {
      throw DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: 409,
              data: {'message': 'Inzwischen nur ein Platz frei.'}));
    }
    booked = playerIds;
    self = includeSelf;
  }

  @override
  Future<EventModel> event(String id) async => _event();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child,
    {double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
    _Repository? repository}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  FlutterSecureStorage.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository ?? _Repository()),
        carpoolEventProvider('match-ride')
            .overrideWith((ref) async => _event(free: 0, needs: 1)),
      ],
      child: MaterialApp(
          theme: buildAppTheme(brightness: brightness),
          builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: MobileAppTheme(child: child!),
              ),
          home: Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12), child: child)))));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'nominated guest and parent book without a host team assignment at $width',
        (tester) async {
      const guest = PlayerModel(
          id: 'guest-child',
          firstName: 'Gastkind',
          lastName: 'Beispiel',
          teamId: 'another-youth',
          status: PlayerStatus.active,
          dominantFoot: DominantFoot.right);
      const sibling = PlayerModel(
          id: 'not-nominated',
          firstName: 'Geschwisterkind',
          lastName: 'Beispiel',
          teamId: 'another-youth',
          status: PlayerStatus.active,
          dominantFoot: DominantFoot.right);
      final repository = _Repository();
      await _pump(
          tester,
          CarpoolSection(
              event: _event(guest: true),
              players: const [guest, sibling],
              onRefresh: () async {}),
          width: width,
          scale: 2,
          repository: repository);
      await tester.ensureVisible(find.text('Hier eintragen'));
      await tester.tap(find.text('Hier eintragen'));
      await tester.pumpAndSettle();
      expect(find.text('Gastkind'), findsOneWidget);
      expect(find.text('Geschwisterkind'), findsNothing);
      await tester.tap(find.text('Gastkind'));
      await tester.pump();
      await tester.tap(find.text('Ich selbst'));
      await tester.pump();
      await tester.ensureVisible(find.text('2 Plätze buchen'));
      await tester.tap(find.text('2 Plätze buchen'));
      await tester.pumpAndSettle();
      expect(repository.booked, ['guest-child']);
      expect(repository.self, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  test('adult passengers retain identity and name with nullable playerId', () {
    final person = CarpoolPassenger.fromJson({
      'id': 'p',
      'playerId': null,
      'passengerUserId': 'parent',
      'passengerUser': {'name': 'Elternteil'},
      'status': 'CONFIRMED'
    });
    expect(person.personKey, 'user:parent');
    expect(person.playerName, 'Elternteil');
    expect(person.playerId, isEmpty);
  });

  testWidgets(
      'book an adult and both children in one atomic request; count updates',
      (tester) async {
    final repository = _Repository();
    var current = _event();
    await _pump(
        tester,
        StatefulBuilder(
            builder: (context, setState) => CarpoolSection(
                  event: current,
                  players: _players,
                  onRefresh: () async =>
                      setState(() => current = _event(free: 2)),
                )),
        repository: repository);
    expect(find.text('5 Plätze frei'), findsOneWidget);
    expect(find.text('Treffpunkt am Haupteingang'), findsNothing,
        reason: 'Extra details start collapsed');
    await tester.tap(find.text('Hier eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ich selbst'));
    await tester.tap(find.text('Erstes'));
    await tester.tap(find.text('Zweites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 Plätze buchen'));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(repository.booked, ['child-1', 'child-2']);
    expect(repository.self, isTrue);
    expect(find.text('2 Plätze frei'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity conflict retains selected people and permits retry',
      (tester) async {
    final repository = _Repository()..fail = true;
    await _pump(
        tester,
        CarpoolSection(
            event: _event(free: 1), players: _players, onRefresh: () async {}),
        repository: repository);
    await tester.tap(find.text('Hier eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ich selbst'));
    await tester.pump();
    final disabled = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Erstes'));
    expect(disabled.onChanged, isNull,
        reason: 'Selected adult already uses the last seat');
    await tester.tap(find.text('1 Platz buchen'));
    await tester.pumpAndSettle();
    expect(find.text('Inzwischen nur ein Platz frei.'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Ich selbst'))
            .value,
        isTrue);
    repository.fail = false;
    await tester.tap(find.text('1 Platz buchen'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'compact carpool and red unmet need at $width / $brightness / 200% text',
          (tester) async {
        await _pump(
            tester,
            Column(children: [
              const CarpoolDashboardCard(eventId: 'match-ride'),
              const SizedBox(height: 8),
              CarpoolSection(
                  event: _event(free: 0, needs: 1),
                  players: _players,
                  onRefresh: () async {}),
            ]),
            width: width,
            scale: 2,
            brightness: brightness);
        expect(find.text('0 Plätze frei · 1 gesucht'), findsOneWidget);
        final label =
            tester.widget<Text>(find.text('0 Plätze frei · 1 gesucht'));
        final context = tester.element(find.text('0 Plätze frei · 1 gesucht'));
        expect(label.style?.color, context.appDanger);
        expect(find.text('Mitfahren'), findsOneWidget);
        expect(find.text('Anbieten'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('booking dialog fits a narrow phone with doubled text',
      (tester) async {
    await _pump(
        tester,
        CarpoolSection(
            event: _event(), players: _players, onRefresh: () async {}),
        width: 320,
        scale: 2);
    await tester.ensureVisible(find.text('Hier eintragen'));
    await tester.tap(find.text('Hier eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ich selbst'));
    await tester.pumpAndSettle();
    expect(find.text('1 Platz buchen').hitTestable(), findsOneWidget);
    expect(find.text('Abbrechen').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('organisation card stays compact at standard phone text size',
      (tester) async {
    await _pump(tester, const CarpoolDashboardCard(eventId: 'match-ride'));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('carpool-dashboard-match-ride')))
            .height,
        lessThan(110));
    expect(tester.takeException(), isNull);
  });
}
