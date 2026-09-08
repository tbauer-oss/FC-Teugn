/// Coalesces checks and limits passive requests without delaying data refreshes.
class UpdateCheckCoordinator<T> {
  UpdateCheckCoordinator({required this.check, DateTime Function()? now})
      : now = now ?? DateTime.now;
  final Future<T?> Function() check;
  final DateTime Function() now;
  Future<T?>? _pending;
  DateTime? _lastCheck;
  T? _lastResult;

  Future<T?> run({bool manual = false}) {
    if (_pending != null) return _pending!;
    if (!manual &&
        _lastCheck != null &&
        now().difference(_lastCheck!) < const Duration(minutes: 1)) {
      return Future.value(_lastResult);
    }
    return _pending = Future.sync(check).then((result) {
      _lastCheck = now();
      _lastResult = result;
      return result;
    }).whenComplete(() => _pending = null);
  }
}
