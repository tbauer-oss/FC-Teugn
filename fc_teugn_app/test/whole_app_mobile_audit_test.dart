import 'package:fc_teugn_app/features/auth/auth_controller.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/features/talents/talents_page.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:fc_teugn_app/features/talents/talents_repository.dart';
import 'package:fc_teugn_app/features/talents/absences_page.dart';
import 'package:fc_teugn_app/features/talents/polls_page.dart';
import 'package:fc_teugn_app/features/talents/goals_page.dart';
import 'package:fc_teugn_app/features/talents/invitations_page.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/support.dart';
import 'package:fc_teugn_app/core/models/team_operations.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/help/help_page.dart';
import 'package:fc_teugn_app/features/operations/team_operations_page.dart';
import 'package:fc_teugn_app/features/privacy/privacy_page.dart';
import 'package:fc_teugn_app/features/support/support_page.dart';
import 'package:fc_teugn_app/features/talents/installation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'support/mobile_audit_fixtures.dart';

class _Auth extends AuthController {
  _Auth({UserRole role = UserRole.coach}) {
    state = AuthState(
        user: AppUser(
            id: 'audit-user',
            email: 'audit@example.test',
            name: 'Testbetreuung',
            role: role,
            status: AccountStatus.approved,
            teamId: 'team-e1'));
  }
  @override
  Future<String?> refreshAccessToken() async => 'local-audit';
}

class _Repository extends DataRepository {
  _Repository() : super(ApiClient(baseUrl: 'http://localhost'));
  @override
  Future<List<Map<String, dynamic>>> privacyRequests() async => [];
  @override
  Future<Map<String, dynamic>> exportPersonalData() async => {
        'name': 'Testfamilie mit einem langen Doppelnamen',
        'events': List.generate(10, (i) => {'name': 'Training $i'}),
      };
}

const _options = <String, dynamic>{
  'capabilities': {'goals': true, 'polls': true, 'invitations': true},
  'players': [
    {
      'id': 'player',
      'firstName': 'Testkind',
      'lastName': 'mit langem Doppelnamen',
      'teamId': 'team-e1'
    }
  ],
  'teams': [
    {'id': 'team-e1', 'name': 'E-Jugend mit langem Mannschaftsnamen'}
  ],
  'members': [
    {
      'id': 'member',
      'name': 'Testbetreuung mit langem Namen',
      'role': 'COACH',
      'teamId': 'team-e1'
    }
  ],
  'exercises': [],
  'trainingPlans': [],
};

class _TalentsRepository extends TalentsRepository {
  _TalentsRepository() : super(Dio());
  @override
  Future<dynamic> get(String path, [Json? query]) async => switch (path) {
        '/options' => _options,
        '/absences' => {
            'players': [
              {
                ...(_options['players'] as List).first as Json,
                'absences': [
                  {
                    'id': 'absence',
                    'startsOn': '2026-09-10',
                    'endsOn': '2026-09-14',
                    'eventTypes': ['MATCH', 'TRAINING'],
                    'weekdays': [1, 3],
                    'reason': 'Familienurlaub in den Ferien'
                  }
                ]
              }
            ]
          },
        '/invitations' => {
            'pending': [],
            'invitations': [
              {
                'id': 'invitation',
                'team': {'name': 'E-Jugend'},
                'role': 'PARENT',
                'expiresAt': '2026-09-15',
                'createdAt': '2026-09-08',
                'claimedCount': 0
              }
            ]
          },
        '/goals' => [
            {
              'id': 'goal',
              'title': 'Ballannahme und sicheres Passspiel verbessern',
              'player': (_options['players'] as List).first,
              'description':
                  'Kontrollierte Ballannahme und präzise Pässe im Training üben.',
              'startsOn': '2026-09-08',
              'endsOn': '2026-10-20',
              'status': 'ACTIVE',
              'visibility': 'FAMILY',
              'observations': [],
              'canManage': true
            }
          ],
        '/polls' => [
            {
              'id': 'poll',
              'question':
                  'Wann soll unser gemeinsames Mannschaftsfest stattfinden?',
              'options': ['Samstag nach dem Training', 'Sonntag am Nachmittag'],
              'closed': false,
              'endsAt': '2026-09-15',
              'responseCount': 1,
              'totalUnits': 2,
              'results': [1, 0],
              'myUnits': [
                {
                  'id': 'family',
                  'label': 'Testfamilie mit zwei Kindern',
                  'choices': [0]
                }
              ],
              'canManage': true
            }
          ],
        _ => [],
      };
}

final _ticket = SupportTicketModel.fromJson({
  'id': 'ticket',
  'subject': 'Lange Rückfrage zur Anzeige der Trainingsrückmeldungen',
  'description':
      'Die Informationen zum Training sind auf meinem Smartphone schwer zu lesen. '
          'Bitte die Beschreibung und die Antwort auch mit großer Schrift anzeigen.',
  'createdAt': '2026-09-08T09:00:00Z',
  'updatedAt': '2026-09-08T10:00:00Z',
  'messages': [
    {
      'id': 'message',
      'body':
          'Eine ausführliche Antwort mit Hinweisen zum Training und zum Kalender.',
      'author': {'name': 'Testbetreuung'},
      'createdAt': '2026-09-08T10:00:00Z'
    },
  ],
});

final _operations = TeamOperationsOverview.fromJson({
  'teamId': 'team-e1',
  'canManage': true,
  'tasks': [
    {
      'id': 'task',
      'title': 'Trikots für das nächste Auswärtsspiel vorbereiten',
      'description': 'Bitte alle Trikots und die Torwartausrüstung mitbringen.'
    }
  ],
  'equipment': [
    {
      'id': 'kit',
      'name': 'Torwartausrüstung für die gesamte Mannschaft',
      'quantity': 2
    }
  ],
  'checklistTemplates': [
    {
      'id': 'template',
      'title': 'Vorbereitung für das Auswärtsspiel',
      'items': [
        {
          'id': 'template-item',
          'title': 'Trikots und Erste-Hilfe-Tasche mitnehmen'
        },
      ]
    }
  ],
  'checklistRuns': [
    {
      'id': 'run',
      'title': 'Die gesamte Vorbereitung für den nächsten Spieltag',
      'items': [
        {
          'id': 'run-item-1',
          'title': 'Trikots und Erste-Hilfe-Tasche mitnehmen',
          'isCompleted': true,
          'completedBy': {
            'id': 'member',
            'name': 'Testmitglied mit langem Doppelnamen'
          }
        },
        {
          'id': 'run-item-2',
          'title':
              'Treffpunkt und Mitfahrgelegenheiten mit allen Familien klären'
        },
      ]
    }
  ],
  'members': [
    {'id': 'member', 'name': 'Testmitglied mit langem Doppelnamen'}
  ],
  'players': [
    {'id': 'player', 'name': 'Testkind mit langem Doppelnamen'}
  ],
});

Future<void> _mount(WidgetTester tester, Widget page, double scale,
    {Size viewport = const Size(320, 740), bool administrator = false}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) =>
          _Auth(role: administrator ? UserRole.superAdmin : UserRole.coach)),
      talentsRepositoryProvider.overrideWithValue(_TalentsRepository()),
      repositoryProvider.overrideWithValue(_Repository()),
      organizationProvider
          .overrideWith((ref) async => auditOrganization(twoTeams: true)),
      teamOperationsProvider('team-e1')
          .overrideWith((ref) async => _operations),
      supportTicketsProvider.overrideWith((ref) async => [_ticket]),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: MobileAppTheme(child: child!),
      ),
      home: Scaffold(body: page),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String label) async {
  if (find.text(label).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(label), 200,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last);
    await tester.pumpAndSettle();
  }
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _keyboardAndDismiss(WidgetTester tester) async {
  final input = find.byType(EditableText);
  if (input.evaluate().isNotEmpty) {
    await tester.ensureVisible(input.first);
    await tester.pumpAndSettle();
    await tester.showKeyboard(input.first);
  }
  tester.view.viewInsets = FakeViewPadding(
      bottom: math.min(300, tester.view.physicalSize.height * .4));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final dialog = tester.getRect(find
      .descendant(of: find.byType(Dialog).last, matching: find.byType(Material))
      .first);
  expect(dialog.left, greaterThanOrEqualTo(0));
  expect(dialog.right, lessThanOrEqualTo(tester.view.physicalSize.width));
  expect(
      dialog.bottom,
      lessThanOrEqualTo(
          tester.view.physicalSize.height - tester.view.viewInsets.bottom));
  final close = find.text('Abbrechen');
  if (close.evaluate().isNotEmpty) {
    await tester.ensureVisible(close.last);
    await tester.tap(close.last);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  }
}

void main() {
  for (final configuration in [
    (const Size(320, 740), 1.0),
    (const Size(320, 740), 2.0),
    (const Size(390, 844), 1.0),
    (const Size(740, 360), 1.3)
  ]) {
    final (viewport, scale) = configuration;
    testWidgets('Familie-Navigation ${viewport.width}/$scale', (tester) async {
      final router =
          GoRouter(initialLocation: '/trainer/talents/invitations', routes: [
        GoRoute(
            path: '/trainer/talents/:section',
            builder: (_, state) => Scaffold(
                body: TalentsPage(section: state.pathParameters['section']!))),
      ]);
      addTearDown(router.dispose);
      await _mount(tester, Router.withConfig(config: router), scale,
          viewport: viewport);
      expect(tester.takeException(), isNull);
      final tabs = find.byType(TabBar);
      expect(tester.getSize(tabs).height, lessThanOrEqualTo(72));
      await _open(tester, 'Umfragen');
      expect(find.text('Neue Umfrage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Supportverwaltung ${viewport.width}/$scale mit Tastatur',
        (tester) async {
      await _mount(tester, const SupportPage(initialTicketId: 'ticket'), scale,
          viewport: viewport, administrator: true);
      expect(find.text('Nur intern sichtbar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _keyboardAndDismiss(tester);
    });
    for (final entry in <String, Widget>{
      'Teamaufgaben': const TeamOperationsPage(),
      'Datenschutz': const PrivacyPage(),
      'Support': const SupportPage(),
      'Trainerhilfe': const HelpPage(staffView: true),
      'Elternhilfe': const HelpPage(staffView: false),
      'Installation': const InstallationPage(),
    }.entries) {
      testWidgets(
          '${entry.key}: 320 px, Schrift $scale / ${viewport.width.toInt()}×${viewport.height.toInt()}',
          (tester) async {
        await _mount(tester, entry.value, scale, viewport: viewport);
        expect(tester.takeException(), isNull);
        // Traverse the complete scrollable content, not just the first viewport.
        for (var i = 0; i < 12; i++) {
          final scroll = find
              .byWidgetPredicate((w) =>
                  w is Scrollable &&
                  (w.axisDirection == AxisDirection.down ||
                      w.axisDirection == AxisDirection.up))
              .first;
          await tester.drag(scroll, const Offset(0, -520));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
    for (final label in [
      'Antrag auswählen',
      'Löschung beantragen',
      'Datenkopie erstellen'
    ]) {
      testWidgets(
          'Datenschutzdialog $label: Schrift $scale / ${viewport.width.toInt()}×${viewport.height.toInt()} und Tastatur',
          (tester) async {
        await _mount(tester, const PrivacyPage(), scale, viewport: viewport);
        await _open(tester, label);
        expect(tester.takeException(), isNull);
        await _keyboardAndDismiss(tester);
      });
    }
    testWidgets(
        'Supportanfrage: Schrift $scale / ${viewport.width.toInt()}×${viewport.height.toInt()} und Tastatur',
        (tester) async {
      await _mount(tester, const SupportPage(), scale, viewport: viewport);
      await _open(tester, 'Anfrage stellen');
      expect(tester.takeException(), isNull);
      await _keyboardAndDismiss(tester);
    });
    testWidgets(
        'Supportantwort: Schrift $scale / ${viewport.width.toInt()}×${viewport.height.toInt()} und Tastatur',
        (tester) async {
      await _mount(tester, const SupportPage(initialTicketId: 'ticket'), scale,
          viewport: viewport);
      expect(tester.takeException(), isNull);
      await _keyboardAndDismiss(tester);
    });
    for (final scenario in [
      ('Aufgaben', 'Aufgabe anlegen'),
      ('Material', 'Material anlegen'),
      ('Material', 'Ausgeben'),
      ('Checklisten', 'Vorlage anlegen'),
    ]) {
      testWidgets(
          'Teamorganisation ${scenario.$2}: Schrift $scale / ${viewport.width.toInt()}×${viewport.height.toInt()} und Tastatur',
          (tester) async {
        await _mount(tester, const TeamOperationsPage(), scale,
            viewport: viewport);
        await _open(tester, scenario.$1);
        await _open(tester, scenario.$2);
        expect(tester.takeException(), isNull);
        await _keyboardAndDismiss(tester);
      });
    }
    for (final scenario in <(Widget, String)>[
      (const AbsencesPage(options: _options), 'Abwesenheit eintragen'),
      (const PollsPage(options: _options), 'Neue Umfrage'),
      (const GoalsPage(options: _options), 'Lernziel anlegen'),
      (const InvitationsPage(options: _options), 'Einladung erstellen'),
    ]) {
      testWidgets(
          'Familie und Team ${scenario.$2}: Schrift $scale / ${viewport.width.toInt()}×${viewport.height.toInt()} und Tastatur',
          (tester) async {
        await _mount(
            tester,
            SingleChildScrollView(
                padding: const EdgeInsets.all(12), child: scenario.$1),
            scale,
            viewport: viewport);
        expect(tester.takeException(), isNull);
        await _open(tester, scenario.$2);
        expect(tester.takeException(), isNull);
        await _keyboardAndDismiss(tester);
      });
    }
  }
}
