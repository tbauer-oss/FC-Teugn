import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum MatchSortOrder { nextFirst, newestFirst, oldestFirst }

enum MatchViewMode { veryCompact, compact, standard, detailed }

abstract class MatchViewPreferenceStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureMatchViewPreferenceStorage implements MatchViewPreferenceStorage {
  SecureMatchViewPreferenceStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class MatchViewPreferences {
  MatchViewPreferences({MatchViewPreferenceStorage? storage})
      : _storage = storage ?? SecureMatchViewPreferenceStorage();

  final MatchViewPreferenceStorage _storage;

  String _sortKey(String userId) => 'fc_teugn_match_sort_v1_$userId';
  String _viewKey(String userId) => 'fc_teugn_match_view_v1_$userId';

  Future<MatchSortOrder> loadSortOrder(String userId) async {
    final saved = await _storage.read(_sortKey(userId));
    return MatchSortOrder.values.firstWhere(
      (order) => order.name == saved,
      orElse: () => MatchSortOrder.nextFirst,
    );
  }

  Future<MatchViewMode> loadViewMode(String userId) async {
    final saved = await _storage.read(_viewKey(userId));
    return MatchViewMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => MatchViewMode.standard,
    );
  }

  Future<void> saveSortOrder(String userId, MatchSortOrder order) =>
      _storage.write(_sortKey(userId), order.name);

  Future<void> saveViewMode(String userId, MatchViewMode mode) =>
      _storage.write(_viewKey(userId), mode.name);
}
