import 'package:fc_teugn_app/core/match_view_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements MatchViewPreferenceStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('next match and compact cards are the defaults', () async {
    final preferences = MatchViewPreferences(storage: _MemoryStorage());

    expect(
      await preferences.loadSortOrder('trainer-1'),
      MatchSortOrder.nextFirst,
    );
    expect(
      await preferences.loadViewMode('trainer-1'),
      MatchViewMode.veryCompact,
    );
  });

  test('legacy compact preference migrates to the compact view', () async {
    final storage = _MemoryStorage();
    storage.values['fc_teugn_match_view_v1_trainer-legacy'] = 'compact';
    final preferences = MatchViewPreferences(storage: storage);

    expect(
      await preferences.loadViewMode('trainer-legacy'),
      MatchViewMode.veryCompact,
    );
  });

  test('sort order and view mode are stored separately per user', () async {
    final storage = _MemoryStorage();
    final preferences = MatchViewPreferences(storage: storage);

    await preferences.saveSortOrder(
      'trainer-1',
      MatchSortOrder.newestFirst,
    );
    await preferences.saveViewMode(
      'trainer-1',
      MatchViewMode.veryCompact,
    );
    await preferences.saveViewMode('trainer-2', MatchViewMode.detailed);

    expect(
      await preferences.loadSortOrder('trainer-1'),
      MatchSortOrder.newestFirst,
    );
    expect(
      await preferences.loadViewMode('trainer-1'),
      MatchViewMode.veryCompact,
    );
    expect(
      await preferences.loadSortOrder('trainer-2'),
      MatchSortOrder.nextFirst,
    );
    expect(
      await preferences.loadViewMode('trainer-2'),
      MatchViewMode.detailed,
    );
  });
}
