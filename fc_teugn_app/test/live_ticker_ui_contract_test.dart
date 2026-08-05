import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/features/matches/matchday_page.dart',
    ).readAsStringSync();
  });

  test('fullscreen ticker exposes clock and match controls', () {
    final focusView = source.substring(
      source.indexOf('class _TickerFocusView'),
      source.indexOf('class _SmoothClockProgress'),
    );

    expect(focusView, contains('clockControlLabel'));
    expect(focusView, contains("Text('Tor FC Teugn')"));
    expect(focusView, contains("Text('Tor Gegner')"));
    expect(focusView, contains("Text('Spiel beenden')"));
  });

  test('ticker refreshes incrementally and keeps writes off the full reload',
      () {
    expect(source, contains('after: previousSequence'));
    expect(source, contains('onChanged: _refreshTicker'));
    expect(source, isNot(contains('onChanged: _load,')));
  });

  test('desktop ticker history owns a persistent scroll view', () {
    expect(source, contains("ValueKey('desktop-live-ticker-scroll-view')"));
    expect(source, contains("ValueKey('desktop-live-ticker-history-heading')"));
    expect(source, contains("'Spielverlauf'"));
  });

  test('reset response updates the visible ticker before the reload', () {
    final resetStart = source.indexOf('Future<void> _confirmReset()');
    final resetFlow = source.substring(
      resetStart,
      source.indexOf('void _message(String text)', resetStart),
    );

    expect(resetFlow, contains('final resetTicker ='));
    expect(resetFlow, contains('_optimisticTicker = resetTicker'));
    expect(resetFlow, contains('_synchronizeClock(resetTicker)'));
    expect(resetFlow, contains('_scheduleNextClockTick(immediate: true)'));
    expect(
      resetFlow.indexOf('_focusData.value = _tickerFocusData(resetTicker)'),
      lessThan(resetFlow.indexOf('await widget.onChanged()')),
    );
  });
}
