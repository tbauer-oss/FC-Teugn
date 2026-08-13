import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'models/matchday.dart';

const fcTeugnGoalSoundAsset = 'audio/fc_teugn_goal.mp3';
const opponentGoalSoundAsset = 'audio/fc_teugn_opponent_goal.mp3';

enum LiveGoalSound { fcTeugnGoal, opponentGoal }

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

  List<LiveGoalSound> observe(LiveTickerModel? ticker) {
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
              isGoalEvent(event.type),
        )
        .toList()
      ..sort((left, right) => left.sequence.compareTo(right.sequence));

    _lastObservedSequence = ticker.lastSequence;
    _playedEventIds.addAll(ticker.events.map((event) => event.id));
    return goals
        .map(
          (event) => isFcTeugnGoal(event.type, fcIsHome: _fcIsHome)
              ? LiveGoalSound.fcTeugnGoal
              : LiveGoalSound.opponentGoal,
        )
        .toList(growable: false);
  }
}

bool isGoalEvent(TickerEventType type) =>
    type == TickerEventType.homeGoal || type == TickerEventType.awayGoal;

bool isFcTeugnGoal(TickerEventType type, {required bool fcIsHome}) =>
    (fcIsHome && type == TickerEventType.homeGoal) ||
    (!fcIsHome && type == TickerEventType.awayGoal);

class LiveGoalSoundPlayer {
  LiveGoalSoundPlayer({
    AudioPlayer? fcTeugnPlayer,
    AudioPlayer? opponentPlayer,
  })  : _fcTeugnPlayer =
            fcTeugnPlayer ?? AudioPlayer(playerId: 'fc-teugn-live-goal'),
        _opponentPlayer = opponentPlayer ??
            AudioPlayer(playerId: 'fc-teugn-live-opponent-goal');

  final AudioPlayer _fcTeugnPlayer;
  final AudioPlayer _opponentPlayer;
  Future<void> _playbackQueue = Future<void>.value();
  Future<void>? _prepareFuture;
  bool _fcTeugnReady = false;
  bool _opponentReady = false;
  bool _disposed = false;

  Future<void> prepare() {
    if (_disposed) return Future<void>.value();
    return _prepareFuture ??= _prepareSounds();
  }

  Future<void> _prepareSounds() async {
    final readiness = await Future.wait([
      _preparePlayer(_fcTeugnPlayer, fcTeugnGoalSoundAsset),
      _preparePlayer(_opponentPlayer, opponentGoalSoundAsset),
    ]);
    _fcTeugnReady = readiness.first;
    _opponentReady = readiness.last;
  }

  Future<bool> _preparePlayer(AudioPlayer player, String asset) async {
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(asset));
      return true;
    } catch (_) {
      // A failed counterpart sound must never disable the other goal sound.
      return false;
    }
  }

  Future<void> play(LiveGoalSound sound) async {
    if (_disposed) return;
    _playbackQueue = _playbackQueue.then(
      (_) => _playNow(sound),
      onError: (_) => _playNow(sound),
    );
    await _playbackQueue;
  }

  Future<void> _playNow(LiveGoalSound sound) async {
    if (_disposed) return;
    try {
      await prepare();
      final ready =
          sound == LiveGoalSound.fcTeugnGoal ? _fcTeugnReady : _opponentReady;
      if (!ready || _disposed) return;
      final player =
          sound == LiveGoalSound.fcTeugnGoal ? _fcTeugnPlayer : _opponentPlayer;
      await player.stop();
      await player.resume();
    } catch (_) {
      // Browsers can reject playback until the user interacted with the page.
      // The match state remains authoritative and fully functional regardless.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _playbackQueue;
    } catch (_) {}
    await Future.wait([
      _fcTeugnPlayer.dispose(),
      _opponentPlayer.dispose(),
    ]);
  }
}
