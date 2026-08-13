import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'models/matchday.dart';

const fcTeugnGoalSoundAsset = 'audio/fc_teugn_goal.mp3';

/// Remembers the authoritative ticker position that was already shown in one
/// open live view. It never fires for the initial snapshot or for replayed
/// history after a reconnect; only newly arriving FC-Teugn goal events qualify.
class LiveGoalSoundTracker {
  LiveGoalSoundTracker({required bool fcIsHome}) : _fcIsHome = fcIsHome;

  bool _fcIsHome;
  bool _initialized = false;
  int _lastObservedSequence = 0;
  final Set<String> _playedEventIds = <String>{};

  void updateSide({required bool fcIsHome}) => _fcIsHome = fcIsHome;

  List<TickerEventModel> observe(LiveTickerModel? ticker) {
    if (ticker == null) return const [];
    if (!_initialized) {
      _initialized = true;
      _lastObservedSequence = ticker.lastSequence;
      _playedEventIds.addAll(ticker.events.map((event) => event.id));
      return const [];
    }

    if (ticker.lastSequence < _lastObservedSequence) {
      // A deliberate reset/restart establishes a new baseline. Old goals must
      // not ring again when the rebuilt history arrives.
      _lastObservedSequence = ticker.lastSequence;
      _playedEventIds
        ..clear()
        ..addAll(ticker.events.map((event) => event.id));
      return const [];
    }

    final goals = ticker.events
        .where(
          (event) =>
              event.sequence > _lastObservedSequence &&
              !_playedEventIds.contains(event.id) &&
              isFcTeugnGoal(event.type, fcIsHome: _fcIsHome),
        )
        .toList()
      ..sort((left, right) => left.sequence.compareTo(right.sequence));

    _lastObservedSequence = ticker.lastSequence;
    _playedEventIds.addAll(ticker.events.map((event) => event.id));
    return goals;
  }
}

bool isFcTeugnGoal(TickerEventType type, {required bool fcIsHome}) =>
    (fcIsHome && type == TickerEventType.homeGoal) ||
    (!fcIsHome && type == TickerEventType.awayGoal);

class LiveGoalSoundPlayer {
  LiveGoalSoundPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer(playerId: 'fc-teugn-live-goal');

  final AudioPlayer _player;
  bool _ready = false;
  bool _disposed = false;

  Future<void> prepare() async {
    if (_disposed || _ready) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource(fcTeugnGoalSoundAsset));
      _ready = true;
    } catch (_) {
      // Audio is celebratory only and may never interrupt the live ticker.
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    try {
      await prepare();
      if (!_ready || _disposed) return;
      await _player.stop();
      await _player.resume();
    } catch (_) {
      // Browsers can reject playback until the user interacted with the page.
      // The match state remains authoritative and fully functional regardless.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _player.dispose();
  }
}
