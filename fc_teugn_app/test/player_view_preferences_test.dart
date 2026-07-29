import 'package:fc_teugn_app/core/player_view_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements PlayerViewPreferenceStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('compact cards are the space-saving default', () async {
    final preferences = PlayerViewPreferences(storage: _MemoryStorage());

    expect(
      await preferences.load('trainer-1'),
      PlayerViewMode.compactCards,
    );
  });

  test('selected player view is stored separately per user', () async {
    final storage = _MemoryStorage();
    final preferences = PlayerViewPreferences(storage: storage);

    await preferences.save('trainer-1', PlayerViewMode.list);
    await preferences.save('trainer-2', PlayerViewMode.details);

    expect(await preferences.load('trainer-1'), PlayerViewMode.list);
    expect(await preferences.load('trainer-2'), PlayerViewMode.details);
  });
}
