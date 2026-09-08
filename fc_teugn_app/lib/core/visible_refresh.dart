import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pauses network refreshes in hidden browser tabs and background apps. Initial
/// loads remain immediate; an overdue refresh runs immediately on returning.
class VisibleRefreshTimer with WidgetsBindingObserver {
  VisibleRefreshTimer(this.interval, this.onRefresh,
      {this.repeat = false, DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _lastRefresh = _now();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  final Duration interval;
  final VoidCallback onRefresh;
  final bool repeat;
  final DateTime Function() _now;
  Timer? _timer;
  late DateTime _lastRefresh;
  bool _disposed = false;
  bool _listening = true;
  bool _completed = false;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void pause() {
    _listening = false;
    _timer?.cancel();
  }

  void resume() {
    _listening = true;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || _completed || !_listening || !_foreground) return;
    final remaining = interval - _now().difference(_lastRefresh);
    _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (_disposed || !_listening || !_foreground) return;
      _lastRefresh = _now();
      if (!repeat) _completed = true;
      onRefresh();
      if (repeat) _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _schedule();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

void scheduleVisibleRefresh(Ref ref, Duration interval) {
  final timer = VisibleRefreshTimer(interval, ref.invalidateSelf);
  ref.onDispose(timer.dispose);
  ref.onCancel(timer.pause);
  ref.onResume(timer.resume);
}
