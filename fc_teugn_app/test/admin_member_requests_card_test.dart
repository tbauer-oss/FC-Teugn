import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/features/trainer/trainer_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows pending member requests and opens the review',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminMemberRequestsCard(
            pending: AsyncData([
              AppUser(
                id: 'pending-1',
                email: 'parent@example.test',
                name: 'Neue Anfrage',
                role: UserRole.parent,
                status: AccountStatus.pending,
                teamId: 'team-e1',
              ),
            ]),
            onOpen: () => opened = true,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('1 offene Mitgliedsanfrage'), findsOneWidget);
    expect(find.textContaining('warten auf Prüfung'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-member-requests-card')));
    expect(opened, isTrue);
  });

  testWidgets('shows the all-clear state even without requests',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminMemberRequestsCard(
            pending: const AsyncData(<AppUser>[]),
            onOpen: () {},
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('Keine offenen Mitgliedsanfragen'), findsOneWidget);
    expect(
        find.text('Aktuell ist keine Freigabe erforderlich.'), findsOneWidget);
  });
}
