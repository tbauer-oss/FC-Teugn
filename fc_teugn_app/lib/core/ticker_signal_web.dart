import 'dart:js_interop';

@JS('fcTeugnPrepareTickerSignal')
external void _prepareTickerSignal();

@JS('fcTeugnPlayTickerEndSignal')
external void _playTickerEndSignal();

@JS('fcTeugnActivateTickerFocusMode')
external void _activateTickerFocusMode();

@JS('fcTeugnDeactivateTickerFocusMode')
external void _deactivateTickerFocusMode();

Future<void> prepareTickerSignal() async => _prepareTickerSignal();

Future<void> playTickerEndSignal() async => _playTickerEndSignal();

Future<void> activateTickerFocusMode() async => _activateTickerFocusMode();

Future<void> deactivateTickerFocusMode() async => _deactivateTickerFocusMode();
