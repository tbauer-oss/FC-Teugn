import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/lineup_planner.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/features/matches/modern_lineup_view.dart';

List<MatchPlayer> players(int count) => List.generate(
    count,
    (i) => MatchPlayer(
        id: '$i',
        name: [
          'Levin Baumann',
          'Anna Jackermeier',
          'Andreas Bauer',
          'Alexander Schmid',
          'Luan Hallbauer',
          'Felix Lorenz',
          'Lukas Wagner',
          'Jonas Meier',
          'Max Muster',
          'Moritz Huber',
          'Johannes-Alexander Schmidbauer'
        ][i],
        shirtNumber: [1, 3, 4, 14, 10, 7, 6, 8, 9, 11, 12][i],
        position: i == 0 ? 'TW' : 'MF'));

void main() {
  Future<void> mount(WidgetTester tester,
      {double scale = 1,
      bool editable = true,
      int count = 7,
      List<ui.DisplayFeature> features = const [],
      ValueChanged<String>? action}) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                displayFeatures: features,
                padding: const EdgeInsets.only(top: 24, bottom: 24)),
            child: child!),
        home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Scaffold(
                body: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(children: [
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Aufstellung',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700)),
                                Text('FC Teugn E1 · 2–3–1',
                                    style: TextStyle(fontSize: 13)),
                              ])),
                          Icon(Icons.close_rounded),
                        ])),
                    Expanded(
                        child: StatefulBuilder(
                            builder: (context, setState) => ModernLineupView(
                                  positions: planInitialLineup(
                                      players: players(count),
                                      fieldSize: count,
                                      formation: count == 7 ? '2-3-1' : '4-4-2',
                                      hasGoalkeeper: true),
                                  bench: players(9).skip(7).toList(),
                                  formation: count == 7 ? '2-3-1' : '4-4-2',
                                  formations: const ['2-3-1', '3-2-1', '4-4-2'],
                                  strength: '$count gegen $count',
                                  editable: editable,
                                  saving: false,
                                  shared: false,
                                  onFormation: (v) =>
                                      action?.call('formation:$v'),
                                  onAutomatic: () => action?.call('automatic'),
                                  onTactics: () => action?.call('tactics'),
                                  onFullscreen: () =>
                                      action?.call('fullscreen'),
                                  onSave: () => action?.call('save'),
                                  onShare: () => action?.call('share'),
                                  onMove: (i, point) => action?.call('move:$i'),
                                  onMoveEnd: () => action?.call('move-end'),
                                  onEdit: (i) => action?.call('edit:$i'),
                                  onBench: (p) => action?.call('bench:${p.id}'),
                                ))),
                  ])),
            )))));
    await tester.pumpAndSettle();
  }

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'all controls remain reachable during phone/foldable/landscape resizing',
      (tester) async {
    size(tester, const Size(390, 844));
    final actions = <String>[];
    await mount(tester, action: actions.add);
    for (final width in [
      320.0,
      360.0,
      375.0,
      390.0,
      412.0,
      430.0,
      650.0,
      850.0,
      900.0,
      320.0
    ]) {
      tester.view.physicalSize = Size(width, width == 900 ? 430 : 844);
      await tester.pumpAndSettle();
      expect(find.byType(JerseyIcon), findsNWidgets(9));
      await tap(tester, find.byKey(const ValueKey('lineup-save-action')));
      await tap(tester, find.byKey(const ValueKey('lineup-publish-action')));
      await tap(tester, find.byKey(const ValueKey('open-tactics-board')));
      expect(tester.takeException(), isNull, reason: 'width $width');
      final rect =
          tester.getRect(find.byKey(const ValueKey('modern-lineup-scroll')));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
      expect(find.byKey(const ValueKey('modern-lineup-wide')),
          width >= 680 ? findsOneWidget : findsNothing);
    }
    expect(actions.where((a) => a == 'save').length, 10);
    expect(actions.where((a) => a == 'share').length, 10);
    expect(actions.where((a) => a == 'tactics').length, 10);
    await tap(tester, find.byKey(const ValueKey('lineup-automatic')));
    await tap(tester, find.byKey(const ValueKey('lineup-player-6')));
    await tap(tester, find.text('Jonas Meier'));
    final editedIndex = planInitialLineup(
            players: players(7),
            fieldSize: 7,
            formation: '2-3-1',
            hasGoalkeeper: true)
        .indexWhere((position) => position.player.id == '6');
    expect(actions, containsAll(['automatic', 'edit:$editedIndex', 'bench:7']));
  });

  testWidgets('large text and eleven players never clip controls or labels',
      (tester) async {
    size(tester, const Size(320, 640));
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final width in [320.0, 430.0, 850.0]) {
        tester.view.physicalSize = Size(width, 640);
        await mount(tester, scale: scale, count: 11);
        await tap(tester, find.byKey(const ValueKey('lineup-save-action')));
        await tap(tester, find.byKey(const ValueKey('open-tactics-board')));
        expect(tester.takeException(), isNull,
            reason: 'width $width scale $scale');
        final field =
            tester.getRect(find.byKey(const ValueKey('modern-lineup-pitch')));
        for (var i = 0; i < 11; i++) {
          final player =
              tester.getRect(find.byKey(ValueKey('lineup-player-$i')));
          expect(field.contains(player.topLeft), isTrue);
          expect(player.bottom, lessThanOrEqualTo(field.bottom));
        }
      }
    }
  });

  testWidgets('family sees every player and full name without editing controls',
      (tester) async {
    size(tester, const Size(390, 844));
    await mount(tester, editable: false);
    expect(find.byKey(const ValueKey('open-tactics-board')), findsNothing);
    expect(find.byKey(const ValueKey('lineup-save-action')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('lineup-player-6')));
    expect(find.text('Lukas Wagner'), findsOneWidget);
    await tap(tester, find.text('Schließen'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('physical hinge separates field and sidebar', (tester) async {
    size(tester, const Size(850, 900));
    await mount(tester, features: [
      const ui.DisplayFeature(
          bounds: Rect.fromLTWH(410, 0, 30, 900),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureFlat)
    ]);
    final field =
        tester.getRect(find.byKey(const ValueKey('modern-lineup-pitch')));
    final tactics =
        tester.getRect(find.byKey(const ValueKey('open-tactics-board')));
    expect(field.right, lessThanOrEqualTo(410));
    expect(tactics.left, greaterThanOrEqualTo(440));
    await tap(tester, find.byKey(const ValueKey('lineup-save-action')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('visual captures of the real responsive lineup', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.runAsync(() async {
      final font = FontLoader('Arial')
        ..addFont(File(const String.fromEnvironment('UI_FONT_PATH'))
            .readAsBytes()
            .then(ByteData.sublistView));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([font.load(), icons.load()]);
    });
    for (final entry in {
      'phone': const Size(390, 844),
      'foldable': const Size(850, 900)
    }.entries) {
      size(tester, entry.value);
      await mount(tester);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')));
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        await Directory('../artifacts/modern-lineup').create(recursive: true);
        await File('../artifacts/modern-lineup/${entry.key}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
    }
  });
}
