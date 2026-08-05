import 'package:flutter/services.dart';

Future<void> prepareTickerSignal() async {}

Future<void> playTickerEndSignal() => SystemSound.play(SystemSoundType.alert);

Future<void> activateTickerFocusMode() async {}

Future<void> deactivateTickerFocusMode() async {}
