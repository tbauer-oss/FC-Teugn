import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  late String repositorySource;

  setUpAll(() {
    source = File(
      'lib/features/matches/matchday_page.dart',
    ).readAsStringSync();
    repositorySource = File(
      'lib/core/data_repository.dart',
    ).readAsStringSync();
  });

  test('fullscreen ticker exposes clock and match controls', () {
    final focusView = source.substring(
      source.indexOf('class _TickerFocusView'),
      source.indexOf('class _SmoothClockProgress'),
    );

    expect(focusView, contains('clockControlLabel'));
    expect(focusView, contains("? 'Tor FC Teugn'"));
    expect(focusView, contains("'Tor für FC Teugn'"));
    expect(focusView, contains("'Gegentor'"));
    expect(focusView, contains("'Spiel beenden'"));
    expect(
      focusView,
      contains('Toraktionen sind nach dem Spielstart verfügbar.'),
    );
    expect(focusView, contains('onOurGoal'));
    expect(focusView, contains('onTheirGoal'));
    expect(focusView, contains('canRecordGoal ? onOurGoal : null'));
    expect(focusView, contains('canRecordGoal ? onTheirGoal : null'));
    expect(focusView, contains('FontFeature.tabularFigures()'));
    expect(focusView, contains('RepaintBoundary'));
  });

  test('ticker refreshes incrementally and keeps writes off the full reload',
      () {
    expect(source, contains('after: previousSequence'));
    expect(source, contains('waitForChanges: true'));
    expect(source, contains('_runTickerRefreshLoop()'));
    expect(source, isNot(contains('Duration(seconds: 4)')));
    expect(source, contains('onChanged: _refreshTicker'));
    expect(source, isNot(contains('onChanged: _load,')));
    expect(repositorySource, contains("if (waitForChanges) 'waitMs': 8000"));
    expect(repositorySource, contains("'Cache-Control': 'no-cache'"));
  });

  test('new confirmed goals trigger the matching shared live sound path', () {
    expect(source, contains('_handleGoalSoundUpdate(serverTicker)'));
    expect(source, contains('_handleGoalSoundUpdate(merged)'));
    expect(source, contains('_goalSoundPlayer.play(sound)'));
  });

  test('live ticker push deep links can open the live tab directly', () {
    expect(source, contains("widget.initialTab == 'live'"));
    expect(source, contains('initialIndex: initialTabIndex'));
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
