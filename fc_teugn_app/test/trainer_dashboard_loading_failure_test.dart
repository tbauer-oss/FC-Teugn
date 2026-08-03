import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/trainer/trainer_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('player loading error keeps the dashboard usable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playersProvider.overrideWith(
            (ref) => Future.error(Exception('temporarily unavailable')),
          ),
          eventsProvider.overrideWith((ref) async => <EventModel>[]),
          pendingUsersProvider.overrideWith((ref) async => <AppUser>[]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: TrainerDashboardPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut laden'), findsOneWidget);
    expect(find.textContaining('vollständig bedienbar'), findsOneWidget);
    expect(find.text('Nächste Termine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
