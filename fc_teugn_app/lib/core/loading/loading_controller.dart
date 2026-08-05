import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLoadingMode { fullscreen, overlay, background }

@immutable
class AppLoadingOperation {
  const AppLoadingOperation({
    required this.id,
    required this.message,
    required this.mode,
    required this.startedAt,
    this.progress,
    this.completedItems,
    this.totalItems,
  });

  final String id;
  final String message;
  final AppLoadingMode mode;
  final DateTime startedAt;
  final double? progress;
  final int? completedItems;
  final int? totalItems;

  AppLoadingOperation copyWith({
    String? message,
    double? progress,
    bool clearProgress = false,
    int? completedItems,
    int? totalItems,
  }) =>
      AppLoadingOperation(
        id: id,
        message: message ?? this.message,
        mode: mode,
        startedAt: startedAt,
        progress: clearProgress ? null : progress ?? this.progress,
        completedItems: completedItems ?? this.completedItems,
        totalItems: totalItems ?? this.totalItems,
      );
}

class AppLoadingHandle {
  AppLoadingHandle._(this._controller, this.id);

  final AppLoadingController _controller;
  final String id;
  bool _finished = false;

  void update({
    String? message,
    double? progress,
    int? completedItems,
    int? totalItems,
  }) {
    if (_finished) return;
    _controller.update(
      id,
      message: message,
      progress: progress,
      completedItems: completedItems,
      totalItems: totalItems,
    );
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _controller.finish(id);
  }
}

class AppLoadingController extends ChangeNotifier {
  AppLoadingController({
    this.showDelay = const Duration(milliseconds: 250),
    this.minimumVisibleDuration = const Duration(milliseconds: 420),
  });

  final Duration showDelay;
  final Duration minimumVisibleDuration;
  final Map<String, AppLoadingOperation> _operations = {};
  Timer? _blockingShowTimer;
  Timer? _backgroundShowTimer;
  Timer? _blockingHideTimer;
  Timer? _backgroundHideTimer;
  final Set<Timer> _transientTimers = {};
  DateTime? _blockingVisibleSince;
  DateTime? _backgroundVisibleSince;
  bool _blockingVisible = false;
  bool _backgroundVisible = false;
  int _sequence = 0;

  bool get hasOperations => _operations.isNotEmpty;
  bool get blockingVisible => _blockingVisible;
  bool get backgroundVisible => _backgroundVisible;
  int get operationCount => _operations.length;

  AppLoadingOperation? get blockingOperation =>
      _preferred(_operations.values.where((item) =>
          item.mode == AppLoadingMode.fullscreen ||
          item.mode == AppLoadingMode.overlay));

  AppLoadingOperation? get backgroundOperation => _preferred(
        _operations.values
            .where((item) => item.mode == AppLoadingMode.background),
      );

  AppLoadingHandle start({
    required String message,
    AppLoadingMode mode = AppLoadingMode.overlay,
    double? progress,
    int? completedItems,
    int? totalItems,
  }) {
    final id = 'loading-${++_sequence}';
    _operations[id] = AppLoadingOperation(
      id: id,
      message: message,
      mode: mode,
      startedAt: DateTime.now(),
      progress: _normalizedProgress(
        progress ??
            (completedItems != null && totalItems != null && totalItems > 0
                ? completedItems / totalItems
                : null),
      ),
      completedItems: completedItems,
      totalItems: totalItems,
    );
    _reconcile(mode == AppLoadingMode.background);
    notifyListeners();
    return AppLoadingHandle._(this, id);
  }

  Future<T> run<T>({
    required String message,
    AppLoadingMode mode = AppLoadingMode.overlay,
    double? progress,
    required Future<T> Function(AppLoadingHandle handle) action,
  }) async {
    final handle = start(message: message, mode: mode, progress: progress);
    try {
      return await action(handle);
    } finally {
      handle.finish();
    }
  }

  void update(
    String id, {
    String? message,
    double? progress,
    int? completedItems,
    int? totalItems,
  }) {
    final operation = _operations[id];
    if (operation == null) return;
    final derivedProgress = progress ??
        (completedItems != null && totalItems != null && totalItems > 0
            ? completedItems / totalItems
            : null);
    _operations[id] = operation.copyWith(
      message: message,
      progress: derivedProgress == null
          ? operation.progress
          : _normalizedProgress(derivedProgress),
      completedItems: completedItems,
      totalItems: totalItems,
    );
    notifyListeners();
  }

  void finish(String id) {
    final removed = _operations.remove(id);
    if (removed == null) return;
    _reconcile(removed.mode == AppLoadingMode.background);
    notifyListeners();
  }

  void showTransientStatus(
    String message, {
    Duration duration = const Duration(milliseconds: 1400),
  }) {
    final handle = start(message: message, mode: AppLoadingMode.background);
    late final Timer timer;
    timer = Timer(duration, () {
      _transientTimers.remove(timer);
      handle.finish();
    });
    _transientTimers.add(timer);
  }

  AppLoadingOperation? _preferred(Iterable<AppLoadingOperation> values) {
    AppLoadingOperation? selected;
    for (final value in values) {
      if (selected == null ||
          value.mode.index < selected.mode.index ||
          (value.mode == selected.mode &&
              !value.startedAt.isBefore(selected.startedAt))) {
        selected = value;
      }
    }
    return selected;
  }

  void _reconcile(bool background) {
    final hasActive =
        background ? backgroundOperation != null : blockingOperation != null;
    final visible = background ? _backgroundVisible : _blockingVisible;
    final showTimer = background ? _backgroundShowTimer : _blockingShowTimer;
    if (hasActive) {
      if (!visible && showTimer == null) _scheduleShow(background);
      if (background) {
        _backgroundHideTimer?.cancel();
        _backgroundHideTimer = null;
      } else {
        _blockingHideTimer?.cancel();
        _blockingHideTimer = null;
      }
      return;
    }
    if (background) {
      _backgroundShowTimer?.cancel();
      _backgroundShowTimer = null;
    } else {
      _blockingShowTimer?.cancel();
      _blockingShowTimer = null;
    }
    if (visible) _scheduleHide(background);
  }

  void _scheduleShow(bool background) {
    void show() {
      if (background) {
        _backgroundShowTimer = null;
        if (backgroundOperation == null) return;
        _backgroundVisible = true;
        _backgroundVisibleSince = DateTime.now();
      } else {
        _blockingShowTimer = null;
        if (blockingOperation == null) return;
        _blockingVisible = true;
        _blockingVisibleSince = DateTime.now();
      }
      notifyListeners();
    }

    if (showDelay == Duration.zero) {
      show();
    } else if (background) {
      _backgroundShowTimer = Timer(showDelay, show);
    } else {
      _blockingShowTimer = Timer(showDelay, show);
    }
  }

  void _scheduleHide(bool background) {
    final visibleSince =
        background ? _backgroundVisibleSince : _blockingVisibleSince;
    final elapsed = visibleSince == null
        ? minimumVisibleDuration
        : DateTime.now().difference(visibleSince);
    final remaining = minimumVisibleDuration - elapsed;

    void hide() {
      if (background) {
        _backgroundHideTimer = null;
        if (backgroundOperation != null) return;
        _backgroundVisible = false;
        _backgroundVisibleSince = null;
      } else {
        _blockingHideTimer = null;
        if (blockingOperation != null) return;
        _blockingVisible = false;
        _blockingVisibleSince = null;
      }
      notifyListeners();
    }

    if (remaining <= Duration.zero) {
      hide();
    } else if (background) {
      _backgroundHideTimer = Timer(remaining, hide);
    } else {
      _blockingHideTimer = Timer(remaining, hide);
    }
  }

  double? _normalizedProgress(double? value) => value?.clamp(0, 1).toDouble();

  @override
  void dispose() {
    _blockingShowTimer?.cancel();
    _backgroundShowTimer?.cancel();
    _blockingHideTimer?.cancel();
    _backgroundHideTimer?.cancel();
    for (final timer in _transientTimers) {
      timer.cancel();
    }
    _transientTimers.clear();
    super.dispose();
  }
}

final appLoadingProvider = ChangeNotifierProvider<AppLoadingController>(
  (ref) => AppLoadingController(),
);
