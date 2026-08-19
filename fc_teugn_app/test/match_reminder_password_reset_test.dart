import 'dart:io';

import 'package:fc_teugn_app/app.dart';
import 'package:fc_teugn_app/features/help/help_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calendar =
      File('lib/features/calendar/calendar_page.dart').readAsStringSync();
  final matches =
      File('lib/features/trainer/trainer_matches_page.dart').readAsStringSync();
  final dashboard = File('lib/features/shared/dashboard_notifications.dart')
      .readAsStringSync();

  test('match editors expose the default 24 hour reminder', () {
    expect(calendar, contains("reminderMode = '1440'"));
    expect(calendar, contains('24 Stunden vorher'));
    expect(matches, contains('24 Stunden vorher erinnern'));
    expect(matches, contains('reminder24hEnabled'));
  });

  test('dashboard notification can be acknowledged without navigation', () {
    expect(dashboard, contains('Ohne Öffnen als gelesen markieren'));
    expect(dashboard, contains('_markRead(latest, showConfirmation: true)'));
    expect(dashboard, contains('_locallyReadIds.add(item.id)'));
  });

  test('legacy reset deep links remain compatible during rollout', () {
    const action = '/reset-password?requestId=reset-anfrage';
    expect(
      normalizePushActionRoute(action, isTrainer: false),
      action,
    );
    expect(
      normalizePushActionRoute(action, isTrainer: true),
      action,
    );
  });

  test('FAQ explains match reminder and password reset by email', () {
    final password = helpArticles.singleWhere(
      (article) => article.title.contains('Passwort vergessen'),
    );
    expect(password.summary, contains('E-Mail-Adresse'));
    expect(password.steps.join(' '), contains('15 Minuten'));
    expect(password.steps.join(' '), contains('Spam- oder Junk-Ordner'));

    final reminder = helpArticles.singleWhere(
      (article) => article.title.contains('24 Stunden vor einem Spiel'),
    );
    expect(reminder.steps.join(' '), contains('standardmäßig aktiviert'));
    expect(reminder.steps.join(' '), contains('neu geplant'));
  });
}
