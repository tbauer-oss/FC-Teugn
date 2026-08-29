import 'dart:io';

import 'package:flutter/services.dart';

class LiveMatchSurface {
  const LiveMatchSurface();

  static const _channel = MethodChannel(
    'de.fcteugn.jugend/live_match',
  );

  bool get supported => Platform.isAndroid;

  Future<bool> update({
    required String matchId,
    required String homeTeam,
    required String awayTeam,
    required int homeScore,
    required int awayScore,
    required int minute,
    required String status,
    required bool finished,
    required String actionUrl,
  }) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('updateLiveMatch', {
            'matchId': matchId,
            'homeTeam': homeTeam,
            'awayTeam': awayTeam,
            'homeScore': homeScore,
            'awayScore': awayScore,
            'minute': minute,
            'status': status,
            'finished': finished,
            'actionUrl': actionUrl,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> cancel(String matchId) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancelLiveMatch', {
        'matchId': matchId,
      });
    } on PlatformException {
      // Eine Systemanzeige ist optional und darf die App nie blockieren.
    } on MissingPluginException {
      // Plattform unterstützt die native Oberfläche nicht.
    }
  }
}

const liveMatchSurface = LiveMatchSurface();
