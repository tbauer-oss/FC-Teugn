import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/user.dart';
import 'package:fc_teugn_app/features/trainer/trainer_approvals_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final configuration in const [
    (Size(320, 568), 1.0),
    (Size(320, 568), 1.5),
    (Size(673, 841), 1.0),
    (Size(673, 841), 1.5),
    (Size(1280, 720), 1.0),
    (Size(1280, 720), 1.5),
  ]) {
    testWidgets(
      'permissions fit ${configuration.$1.width}x${configuration.$1.height} at ${configuration.$2}',
      (tester) async {
        final repository = _PermissionRepository();
        await _pumpDialog(
          tester,
          viewport: configuration.$1,
          scale: configuration.$2,
          repository: repository,
        );

        final title = find.text('Individuelle Rechte · Michael Stark');
        expect(title, findsOneWidget);
        expect(tester.getSize(title).width, greaterThan(150));
        final label = find.byKey(const ValueKey('permission-label-VIEW_TEAM'));
        expect(label, findsOneWidget);
        expect(tester.getSize(label).width, greaterThan(100));
        expect(find.text('Alle auf Rollenstandard'), findsOneWidget);
        expect(find.text('Schließen'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('permission-category-Organisation')),
          300,
          scrollable: find.descendant(
            of: find.byKey(
              const ValueKey('adaptive-dialog-scroll-view'),
            ),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('permission-category-Organisation')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('permissions reset and close actions remain tappable on phone',
      (tester) async {
    final repository = _PermissionRepository();
    await _pumpDialog(
      tester,
      viewport: const Size(320, 568),
      scale: 1.5,
      repository: repository,
    );

    await tester.tap(find.text('Alle auf Rollenstandard'));
    await tester.pump();
    expect(repository.resetCalls, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberPermissionsDialog), findsNothing);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Size viewport,
  required double scale,
  required _PermissionRepository repository,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: viewport,
          textScaler: TextScaler.linear(scale),
        ),
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => MemberPermissionsDialog(
                    user: _user,
                    repository: repository,
                  ),
                ),
                child: const Text('Rechte öffnen'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Rechte öffnen'));
  await tester.pumpAndSettle();
}

final _user = AppUser(
  id: 'member-1',
  email: 'michael@example.test',
  name: 'Michael Stark',
  role: UserRole.coach,
  status: AccountStatus.approved,
  teamId: 'team-e1',
);

class _PermissionRepository extends DataRepository {
  _PermissionRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  int resetCalls = 0;

  MemberPermissionProfile get value => const MemberPermissionProfile(
        userId: 'member-1',
        rolePermissions: {
          'VIEW_TEAM',
          'MANAGE_PLAYERS',
          'MANAGE_EVENTS',
          'MANAGE_LINEUPS',
          'VIEW_TEAM_OPERATIONS',
        },
        effectivePermissions: {
          'VIEW_TEAM',
          'MANAGE_PLAYERS',
          'MANAGE_EVENTS',
          'SEND_ANNOUNCEMENTS',
          'VIEW_TEAM_OPERATIONS',
        },
        overrides: {
          'SEND_ANNOUNCEMENTS': 'ALLOW',
          'MANAGE_LINEUPS': 'DENY',
        },
      );

  @override
  Future<MemberPermissionProfile> memberPermissions(String userId) async =>
      value;

  @override
  Future<MemberPermissionProfile> updateMemberPermission({
    required String userId,
    required String permission,
    required String state,
  }) async =>
      value;

  @override
  Future<MemberPermissionProfile> resetMemberPermissions(String userId) async {
    resetCalls++;
    return value;
  }
}
