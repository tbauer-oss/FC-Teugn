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
    expect(scaffold, contains('final bool hideHeader'));
  });
}
