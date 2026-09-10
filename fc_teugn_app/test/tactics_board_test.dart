import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:dio/dio.dart';
import 'package:fc_teugn_app/core/models/tactics_board.dart';
import 'package:fc_teugn_app/features/matches/tactics_board_page.dart';
import 'package:fc_teugn_app/features/matches/tactics_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TacticsDocument document() => TacticsDocument([
      TacticsScene(id: 'scene', name: 'Grundordnung', tokens: const [
        TacticsToken(
            id: 'own',
            kind: 'own',
            label: 'Spieler Eins',
            position: Offset(.5, .75)),
        TacticsToken(
            id: 'opponent',
            kind: 'opponent',
            label: 'Gegner 4',
            position: Offset(.3, .25)),
      ])
    ]);

void main() {
  test('normalized coordinates roundtrip across portrait and landscape', () {
    for (final landscape in [false, true]) {
      for (final size in [const Size(320, 480), const Size(850, 550)]) {
        const point = Offset(.28, .76);
        final restored = tacticsFromScreen(
            tacticsToScreen(point, size, landscape), size, landscape);
        expect((restored - point).distance, lessThan(.00001));
      }
    }
  });
  test('document serialization and scene undo/redo preserve the original', () {
    final initial = document();
    final editor = TacticsEditor(initial);
    editor.updateScene(editor.scene.copyWith(name: 'Ecke'));
    expect(editor.document.scenes.first.name, 'Ecke');
    editor.undo();
    expect(editor.document.fingerprint, initial.fingerprint);
    editor.redo();
    expect(editor.scene.name, 'Ecke');
    expect(TacticsDocument.fromJson(editor.document.toJson()).fingerprint,
        editor.document.fingerprint);
    expect(initial.scenes.first.name, 'Grundordnung');
    editor.dispose();
  });

  Future<void> mount(WidgetTester tester,
      {Future<int> Function(TacticsDocument, int)? save,
      Size size = const Size(390, 844),
      double scale = 1,
      List<DisplayFeature> features = const []}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 24, bottom: 24),
                displayFeatures: features),
            child: child!),
        home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: TacticsBoardPage(
              title: 'FC Teugn – Gast',
              ownTeam: 'FC Teugn E1',
              opponent: 'Gastmannschaft E1',
              initialPositions: const [],
              players: const [],
              load: () async =>
                  TacticsBoardSnapshot(revision: 1, document: document()),
              save: save ?? (_, revision) async => revision + 1,
            ))));
    await tester.pumpAndSettle();
  }

  Future<void> tool(WidgetTester tester, String name) async {
    final button = find.byKey(ValueKey('tactics-$name'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('draw, move, opponents, undo and save/reopen data',
      (tester) async {
    TacticsDocument? saved;
    await mount(tester, save: (doc, revision) async {
      saved = doc;
      expect(revision, 1);
      return 2;
    });
    final pitch = find.byKey(const ValueKey('tactics-pitch'));
    await tool(tester, 'Passpfeil');
    final rect = tester.getRect(pitch);
    await tester.dragFrom(rect.center, const Offset(30, -65));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ungespeichert'), findsOneWidget);
    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Wiederholen'));
    await tester.pumpAndSettle();
    await tool(tester, 'Verschieben');
    final moveRect = tester.getRect(pitch);
    final own = moveRect.topLeft +
        tacticsToScreen(const Offset(.5, .75), moveRect.size, false);
    await tester.dragFrom(own, const Offset(35, -20));
    await tester.pumpAndSettle();
    await tool(tester, 'Gegner');
    await tester.enterText(find.byType(TextField), '9 Stürmer');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Taktik speichern'));
    await tester.pumpAndSettle();
    expect(saved!.scenes.first.strokes.single.kind, 'arrow');
    expect(saved!.scenes.first.tokens.length, 3);
    expect(saved!.scenes.first.tokens.first.position != const Offset(.5, .75),
        isTrue,
        reason: saved!.fingerprint);
    expect(saved!.scenes.first.tokens.last.label, '9 Stürmer');
    expect(TacticsDocument.fromJson(saved!.toJson()).fingerprint,
        saved!.fingerprint);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dynamic phone/foldable/landscape sizes retain board and have no overflows',
      (tester) async {
    await mount(tester);
    for (final size in [
      const Size(320, 640),
      const Size(360, 740),
      const Size(375, 812),
      const Size(390, 844),
      const Size(412, 915),
      const Size(430, 932),
      const Size(650, 850),
      const Size(850, 900),
      const Size(740, 360),
      const Size(320, 640)
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tactics-pitch')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
      final rect = tester.getRect(find.byKey(const ValueKey('tactics-pitch')));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
    }
    await tester.tap(find.byTooltip('Präsentieren'));
    await tester.pumpAndSettle();
    expect(find.text('Gastmannschaft E1'),
        findsNothing); // legend includes its color marker
    expect(find.textContaining('Gastmannschaft E1'), findsOneWidget);
    expect(find.byKey(const ValueKey('tactics-Stift')), findsNothing);
    await tester.tap(find.byTooltip('Werkzeuge anzeigen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tactics-Stift')), findsOneWidget);
  });

  testWidgets('large text and a separating fold do not cover controls',
      (tester) async {
    await mount(tester,
        size: const Size(850, 900),
        scale: 1.6,
        features: const [
          DisplayFeature(
              bounds: Rect.fromLTWH(419, 0, 12, 900),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened),
        ]);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byKey(const ValueKey('tactics-pitch')));
    expect(rect.right <= 419 || rect.left >= 431, isTrue);
  });

  testWidgets('conflicting saves keep draft; closing requires confirmation',
      (tester) async {
    await mount(tester, save: (doc, __) async {
      throw DioException(
          requestOptions: RequestOptions(),
          response:
              Response(requestOptions: RequestOptions(), statusCode: 409));
    });
    await tool(tester, 'Stift');
    await tester.drag(
        find.byKey(const ValueKey('tactics-pitch')), const Offset(20, 50));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Taktik speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Ein anderer Trainer war schneller'), findsOneWidget);
    await tester.tap(find.text('Entwurf behalten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ungespeichert'), findsOneWidget);
    await tester.tap(find.byTooltip('Taktikboard schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Ungespeicherte Taktik'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tactics-pitch')), findsOneWidget);
  });

  testWidgets('capture tactics board for visual review', (tester) async {
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await tester.runAsync(() async {
        final font = FontLoader('Roboto')
          ..addFont(File(const String.fromEnvironment('UI_FONT_PATH'))
              .readAsBytes()
              .then(ByteData.sublistView));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
    }
    await mount(tester, size: const Size(850, 900));
    await tool(tester, 'Passpfeil');
    await tester.drag(
        find.byKey(const ValueKey('tactics-pitch')), const Offset(65, -90));
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      for (final entry in {
        'foldable': const Size(850, 900),
        'phone': const Size(390, 844)
      }.entries) {
        tester.view.physicalSize = entry.value;
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')));
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 1.5);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory('../artifacts/tactics-board').create(recursive: true);
          await File('../artifacts/tactics-board/${entry.key}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
    }
  });
}
