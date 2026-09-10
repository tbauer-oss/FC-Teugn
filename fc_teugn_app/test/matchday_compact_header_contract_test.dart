import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matchday keeps the fixed desktop header compact', () {
    final matchday =
        File('lib/features/matches/matchday_page.dart').readAsStringSync();
    final scaffold =
        File('lib/features/shared/page_scaffold.dart').readAsStringSync();

    expect(matchday, contains('hideHeader: true'));
    expect(matchday, contains('class _WideMatchTab'));
    expect(matchday, contains('height: 42'));
    final lineup =
        File('lib/features/matches/modern_lineup_view.dart').readAsStringSync();
    expect(lineup, contains("ValueKey('lineup-save-action')"));
    expect(lineup, contains("ValueKey('lineup-publish-action')"));
    expect(lineup, contains("ValueKey('modern-lineup-scroll')"));
    expect(matchday, contains('match-communication-dense-mobile-actions'));
    expect(scaffold, contains('final bool hideHeader'));
  });
}
