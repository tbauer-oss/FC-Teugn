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

  test('FAQ contains the complete iPhone home-screen and push guide', () {
    final article = helpArticles.singleWhere(
      (article) => article.title.contains('auf dem iPhone als App'),
    );

    expect(article.steps.join(' '), contains('Zum Home-Bildschirm'));
    expect(article.steps.join(' '), contains('Als Web-App öffnen'));
    expect(article.steps.join(' '), contains('Push aktivieren'));
    expect(article.steps.join(' '), contains('Mitteilungen erlauben'));
  });

  testWidgets('family help hides staff-only administration instructions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(staffView: false));
    await tester.pumpAndSettle();

    expect(find.text('Hilfe & Anleitungen'), findsOneWidget);
    expect(find.byKey(const ValueKey('help-search-field')), findsOneWidget);
    expect(find.text('Wie gebe ich eine Rückmeldung ab?'), findsOneWidget);
    expect(find.text('Wie führe ich einen sicheren Saisonwechsel durch?'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unresolved questions lead directly to technical support',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(staffView: true));
    await tester.pumpAndSettle();
    final supportButton =
        find.byKey(const ValueKey('help-technical-support-button'));
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -6000),
    );
    await tester.pumpAndSettle();

    expect(supportButton, findsOneWidget);
    expect(find.text('Nachrichten öffnen'), findsNothing);
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

  test('FAQ explains the latest response and match publication flows', () {
    final responseArticle = helpArticles.singleWhere(
      (article) => article.title == 'Wie gebe ich eine Rückmeldung ab?',
    );
    final responseText = responseArticle.steps.join(' ');
    expect(responseText, isNot(contains('„Vielleicht“')));
    expect(responseText, contains('verbindlich „Zusagen“ oder „Absagen“'));
    expect(responseText, contains('Grund'));
    expect(responseText, contains('„1 Woche“'));
    expect(responseText, contains('Kalender synchronisiert'));

    final opponentArticle = helpArticles.singleWhere(
      (article) => article.title == 'Wie lege ich Gegner, Liga und Spiel an?',
    );
    expect(
      opponentArticle.steps.join(' '),
      contains('gemeinsamen Vereins-Pool'),
    );
    expect(
      opponentArticle.steps.join(' '),
      contains('zuerst den Verein und danach die Jugendmannschaft'),
    );
    expect(opponentArticle.steps.join(' '), contains('ausschließlich'));

    final publicationArticle = helpArticles.singleWhere(
      (article) =>
          article.title ==
          'Wie veröffentliche ich ein Spiel intern oder für Familien?',
    );
    expect(publicationArticle.steps.join(' '), contains('Treffpunktzeit'));
    expect(publicationArticle.steps.join(' '), contains('Empfängerliste'));
    expect(publicationArticle.steps.join(' '), contains('Familienfreigabe'));
  });

  test('FAQ covers family assistant, emoji calendar and direct contact', () {
    final assistant = helpArticles.singleWhere(
      (article) => article.title == 'Was zeigt mir der Familien-Assistent?',
    );
    expect(assistant.steps.join(' '), contains('Heute wichtig'));
    expect(assistant.steps.join(' '), contains('Alles erledigt'));

    final calendar = helpArticles.singleWhere(
      (article) =>
          article.title == 'Woran erkenne ich die Terminarten im Kalender?',
    );
    expect(calendar.steps.join(' '), contains('🏃 Training'));
    expect(calendar.steps.join(' '), contains('Kategorien'));

    final period = helpArticles.singleWhere(
      (article) =>
          article.title == 'Wie wähle ich den Zeitraum meiner Rückmeldungen?',
    );
    expect(period.steps.join(' '), contains('„1 Woche“'));
    expect(period.steps.join(' '), contains('„Alle kommenden“'));

    final contact = helpArticles.singleWhere(
      (article) => article.title.contains('Direktkontakt zwischen Eltern'),
    );
    expect(contact.steps.join(' '), contains('30 Tagen'));
    expect(contact.steps.join(' '), contains('2.000 Zeichen'));
    expect(contact.route, '/messages?section=contact');
  });
}
