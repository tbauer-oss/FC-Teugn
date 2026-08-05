import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/communications/communications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CommunicationRepository extends DataRepository {
  _CommunicationRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  @override
  Future<List<AnnouncementModel>> announcements({
    bool includeDrafts = false,
  }) async =>
      const [];
}

Widget _page({required bool staffView}) {
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(_CommunicationRepository()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CommunicationsPage(staffView: staffView),
      ),
    ),
  );
}

void main() {
  testWidgets('Eltern und Spieler sehen keine Platzanfragen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(staffView: false));
    await tester.pumpAndSettle();

    expect(find.text('Mitteilungen'), findsOneWidget);
    expect(find.text('Platzanfragen'), findsNothing);
    expect(find.text('Benachrichtigungen'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });

  testWidgets('Vereinsmitarbeiter sehen Platzanfragen weiterhin',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(staffView: true));
    await tester.pumpAndSettle();

    expect(find.text('Platzanfragen'), findsOneWidget);
  });
}
