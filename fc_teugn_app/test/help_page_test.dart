import 'package:fc_teugn_app/features/help/help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required bool staffView}) => MaterialApp(
      home: Scaffold(body: HelpPage(staffView: staffView)),
    );

void main() {
  test('FAQ catalog covers every functional help category', () {
    expect(helpArticles.length, greaterThanOrEqualTo(25));
    for (final category in HelpCategory.values.where(
      (category) => category != HelpCategory.all,
    )) {
      expect(
        helpArticles.any((article) => article.category == category),
        isTrue,
        reason: '${category.label} benötigt mindestens einen Hilfeartikel.',
      );
    }
  });

  testWidgets('family help hides staff-only administration instructions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(staffView: false));
    await tester.pumpAndSettle();

    expect(find.text('Hilfe & FAQ'), findsOneWidget);
    expect(find.byKey(const ValueKey('help-search-field')), findsOneWidget);
    expect(find.text('Wie gebe ich eine Zu- oder Absage ab?'), findsOneWidget);
    expect(find.text('Wie führe ich einen sicheren Saisonwechsel durch?'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FAQ search filters the staff catalog across keywords',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(staffView: true));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('help-search-field')),
      'Kader speichern',
    );
    await tester.pumpAndSettle();

    expect(find.text('Wie speichere und veröffentliche ich den Kader?'),
        findsOneWidget);
    expect(find.text('Wie führe ich einen sicheren Saisonwechsel durch?'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
