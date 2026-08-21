import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/communication.dart';
import 'package:fc_teugn_app/features/communications/communications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final devices = [
    _device(
      id: 'active',
      name: 'Verena · Android',
      health: PushDeviceHealth.active,
      active: true,
    ),
    _device(
      id: 'stale',
      name: 'Familien-Browser mit langem Gerätenamen',
      health: PushDeviceHealth.stale,
      active: true,
      platform: 'WEB',
    ),
    _device(
      id: 'disabled',
      name: 'Altes Smartphone',
      health: PushDeviceHealth.disabled,
      active: false,
      administrativelyDisabled: true,
    ),
  ];

  for (final width in const [320.0, 360.0, 599.0, 1000.0]) {
    testWidgets('push device management is compact at $width px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var filter = 'ALL';

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => AdminPushDeviceManagementCard(
                  devices: devices,
                  searchController: controller,
                  filter: filter,
                  changing: false,
                  onSearchChanged: (_) => setState(() {}),
                  onFilterChanged: (value) => setState(() => filter = value),
                  onRefresh: () {},
                  onToggle: (_) {},
                  onDelete: (_) {},
                  onDeleteDisabled: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Alle 3'), findsOneWidget);
      expect(find.text('Aktiv 1'), findsOneWidget);
      expect(find.text('Länger inaktiv 1'), findsOneWidget);
      expect(find.text('Deaktiviert 1'), findsOneWidget);
      expect(find.text('Verena · Android'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('status chips filter the compact device list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var filter = 'ALL';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => AdminPushDeviceManagementCard(
                devices: devices,
                searchController: controller,
                filter: filter,
                changing: false,
                onSearchChanged: (_) => setState(() {}),
                onFilterChanged: (value) => setState(() => filter = value),
                onRefresh: () {},
                onToggle: (_) {},
                onDelete: (_) {},
                onDeleteDisabled: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Deaktiviert 1'));
    await tester.tap(find.text('Deaktiviert 1'));
    await tester.pump();

    expect(find.text('Altes Smartphone'), findsOneWidget);
    expect(find.text('Verena · Android'), findsNothing);
    expect(find.text('Familien-Browser mit langem Gerätenamen'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

AdminPushDevice _device({
  required String id,
  required String name,
  required PushDeviceHealth health,
  required bool active,
  String platform = 'ANDROID',
  bool administrativelyDisabled = false,
}) {
  final timestamp = DateTime(2026, 8, 21, 10, 30);
  return AdminPushDevice(
    id: id,
    platform: platform,
    deviceName: name,
    isActive: active,
    health: health,
    lastUsedAt: timestamp,
    createdAt: timestamp,
    updatedAt: timestamp,
    administrativelyDisabledAt: administrativelyDisabled ? timestamp : null,
    userId: 'user-$id',
    userName: 'Test Mitglied mit langem Namen',
    userEmail: 'mitglied@example.test',
    userRole: 'PARENT',
    userStatus: 'APPROVED',
    teamName: 'E1-Jugend',
    deliveryCount: 12,
  );
}
