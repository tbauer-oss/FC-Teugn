import 'dart:ui';

import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewports = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(375, 667),
  Size(390, 844),
  Size(412, 915),
  Size(480, 800),
  Size(600, 960),
  Size(673, 841),
  Size(841, 673),
  Size(1280, 720),
];

void expectNoFlutterLayoutException(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull, reason: 'Das Layout darf keine Exception melden.');
}

void main() {
  for (final viewport in _viewports) {
    for (final scale in const [1.0, 1.15, 1.3, 1.5, 1.8, 2.0]) {
      testWidgets(
        'adaptive actions fit ${viewport.width}x${viewport.height} at $scale',
        (tester) async {
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
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AdaptiveActionBar(
                        actions: [
                          AdaptiveActionSpec(
                            label: 'Alle auswählen',
                            icon: Icons.select_all_rounded,
                            onPressed: () {},
                          ),
                          AdaptiveActionSpec(
                            label: 'Alle abwählen',
                            icon: Icons.deselect_rounded,
                            onPressed: () {},
                          ),
                          AdaptiveActionSpec(
                            label: 'Veröffentlichen',
                            icon: Icons.campaign_outlined,
                            onPressed: () {},
                          ),
                          AdaptiveActionSpec(
                            label: 'Kader speichern',
                            icon: Icons.save_outlined,
                            onPressed: () {},
                            primary: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expectNoFlutterLayoutException(tester);
          for (final label in const [
            'Alle auswählen',
            'Alle abwählen',
            'Veröffentlichen',
            'Kader speichern',
          ]) {
            final text = find.text(label);
            expect(text, findsOneWidget);
            final rect = tester.getRect(text);
            final button = find.ancestor(
              of: text,
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            );
            expect(button, findsOneWidget);
            final buttonRect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(viewport.width));
            expect(rect.width, greaterThan(44));
            expect(rect.left, greaterThanOrEqualTo(buttonRect.left - .5));
            expect(rect.right, lessThanOrEqualTo(buttonRect.right + .5));
            expect(rect.top, greaterThanOrEqualTo(buttonRect.top - .5));
            expect(rect.bottom, lessThanOrEqualTo(buttonRect.bottom + .5));
          }
        },
      );
    }
  }

  testWidgets('adaptive dialog stays inside the largest foldable pane',
      (tester) async {
    const viewport = Size(673, 841);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            displayFeatures: [
              DisplayFeature(
                bounds: Rect.fromLTWH(330, 0, 13, 841),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: Scaffold(
            body: AdaptiveDialogScaffold(
              title: 'Foldable-Dialog',
              content: const Text('Sicher im nutzbaren Bereich'),
              actions: [
                FilledButton(
                  onPressed: () {},
                  child: const Text('Fertig'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.getRect(
      find.byKey(const ValueKey('adaptive-dialog-surface')),
    );
    final staysLeftOfHinge = dialog.right <= 330;
    final staysRightOfHinge = dialog.left >= 343;
    expect(staysLeftOfHinge || staysRightOfHinge, isTrue);
    expectNoFlutterLayoutException(tester);
  });

  testWidgets('app surface uses one pane and exposes its usable width',
      (tester) async {
    const viewport = Size(673, 841);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    double? usableWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            displayFeatures: [
              DisplayFeature(
                bounds: Rect.fromLTWH(330, 0, 13, 841),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: AdaptiveHingePane(
            child: Builder(
              builder: (context) {
                usableWidth = MediaQuery.sizeOf(context).width;
                return const ColoredBox(
                  key: ValueKey('foldable-app-surface'),
                  color: Colors.white,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(usableWidth, 330);
    final surface = tester.getRect(
      find.byKey(const ValueKey('foldable-app-surface')),
    );
    expect(surface.right, lessThanOrEqualTo(330));
    expectNoFlutterLayoutException(tester);
  });

  testWidgets('horizontal hinge selects a complete usable pane',
      (tester) async {
    const viewport = Size(480, 800);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            displayFeatures: [
              DisplayFeature(
                bounds: Rect.fromLTWH(0, 390, 480, 20),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: AdaptiveHingePane(
            child: ColoredBox(
              key: ValueKey('horizontal-fold-surface'),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = tester.getRect(
      find.byKey(const ValueKey('horizontal-fold-surface')),
    );
    expect(surface.bottom <= 390 || surface.top >= 410, isTrue);
    expectNoFlutterLayoutException(tester);
  });
}
