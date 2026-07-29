import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum PlayerViewMode { list, details, compactCards, largeCards }

abstract class PlayerViewPreferenceStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecurePlayerViewPreferenceStorage
    implements PlayerViewPreferenceStorage {
  SecurePlayerViewPreferenceStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class PlayerViewPreferences {
  PlayerViewPreferences({PlayerViewPreferenceStorage? storage})
      : _storage = storage ?? SecurePlayerViewPreferenceStorage();

  final PlayerViewPreferenceStorage _storage;

  String _key(String userId) => 'fc_teugn_player_view_v1_$userId';

  Future<PlayerViewMode> load(String userId) async {
    final saved = await _storage.read(_key(userId));
    return PlayerViewMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => PlayerViewMode.compactCards,
    );
  }

  Future<void> save(String userId, PlayerViewMode mode) =>
      _storage.write(_key(userId), mode.name);
}
