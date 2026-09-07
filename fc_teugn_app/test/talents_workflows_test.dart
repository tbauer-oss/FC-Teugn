import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/core/push/push_action_route.dart';
import 'package:fc_teugn_app/features/talents/pending_operation_keys.dart';
import 'package:fc_teugn_app/features/talents/polls_page.dart';
import 'package:fc_teugn_app/features/talents/talents_repository.dart';
import 'package:fc_teugn_app/features/talents/talents_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'pending operation survives repository recreation without storing private form text',
      () async {
    final first = PendingOperationKeys('parent');
    const input = 'POST|/absences|private absence reason';
    final key = await first.get(input);
    expect(await PendingOperationKeys('parent').get(input), key);
    expect(await PendingOperationKeys('other').get(input), isNot(key));
    final stored = await const FlutterSecureStorage().readAll();
    expect(stored.toString(), isNot(contains('private absence reason')));
    await first.complete(input);
    expect(await PendingOperationKeys('parent').get(input), isNot(key));
  });
  test(
      'Talents push targets retain the audience and choose an existing section',
      () {
    expect(roleCorrectPushActionRoute('/talents/polls', isTrainer: false),
        '/parent/talents/polls');
    expect(roleCorrectPushActionRoute('/talents/invitations', isTrainer: true),
        '/trainer/talents/invitations');
    expect(roleCorrectPushActionRoute('/talents/expired', isTrainer: false),
        '/parent/talents/assistant');
  });
  testWidgets('failed online save retains input and permits a successful retry',
      (tester) async {
    var attempts = 0;
    var done = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    child: const Text('Öffnen'),
                    onPressed: () async {
                      done = await talentsForm(context,
                          title: 'Abwesenheit',
                          initial: {},
                          fields: (v, set) =>
                              [textInput(v, set, 'reason', 'Grund')],
                          save: (v) async {
                            attempts++;
                            expect(v['reason'], 'Familienurlaub');
                            if (attempts == 1) {
                              throw DioException(
                                  requestOptions:
                                      RequestOptions(path: '/absences'),
                                  type: DioExceptionType.connectionError);
                            }
                          });
                    })))));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Familienurlaub');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Familienurlaub'), findsOneWidget);
    expect(find.textContaining('Eingaben bleiben erhalten'), findsOneWidget);
    expect(done, false);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(done, true);
    expect(attempts, 2);
  });
  testWidgets('saving a poll refreshes the actual page after closing the form',
      (tester) async {
    final repository = _SavingPollRepository();
    await tester.pumpWidget(ProviderScope(
        overrides: [talentsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: PollsPage(options: {
          'teams': [
            {'id': 'team', 'name': 'E-Jugend'}
          ],
          'capabilities': {'polls': true}
        }))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neue Umfrage'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'Gemeinsamer Ausflug');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'Samstag\nSonntag');
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Gemeinsamer Ausflug'), findsOneWidget);
    expect(repository.loads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'poll results and family vote remain readable at 320 px and double text size',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          talentsRepositoryProvider.overrideWithValue(_PollRepository())
        ],
        child: const MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(
              size: Size(320, 720), textScaler: TextScaler.linear(2)),
          child: Scaffold(
              body: SingleChildScrollView(
                  padding: EdgeInsets.all(14),
                  child: PollsPage(options: {
                    'teams': [],
                    'capabilities': {'polls': false}
                  }))),
        ))));
    await tester.pumpAndSettle();
    expect(find.text('Wann machen wir unseren Mannschaftsausflug?'),
        findsOneWidget);
    expect(find.textContaining('1 von 2 Antworten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SavingPollRepository extends _PollRepository {
  String? question;
  int loads = 0;
  @override
  Future<dynamic> get(String path, [Json? query]) async {
    loads++;
    if (question == null) return [];
    final rows = await super.get(path, query) as List;
    return [
      {...rows.first as Json, 'question': question}
    ];
  }

  @override
  Future<dynamic> save(String path, Json body, {String method = 'POST'}) async {
    expect(path, '/polls');
    expect(body['options'], ['Samstag', 'Sonntag']);
    question = body['question'] as String;
    return {'id': 'poll'};
  }
}

class _PollRepository extends TalentsRepository {
  _PollRepository() : super(Dio());
  @override
  Future<dynamic> get(String path, [Json? query]) async => [
        {
          'id': 'poll',
          'question': 'Wann machen wir unseren Mannschaftsausflug?',
          'options': ['Samstag nach dem Training', 'Sonntag am Nachmittag'],
          'closed': false,
          'endsAt': '2030-09-21T21:59:00Z',
          'responseCount': 1,
          'totalUnits': 2,
          'results': [1, 0],
          'myUnits': [
            {
              'id': 'family',
              'label': 'Mia und Leon',
              'choices': [0]
            }
          ],
          'canManage': false
        },
      ];
}
