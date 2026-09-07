import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local preference: watching the introduction is never required to
/// access the team. A slow or unavailable keystore must not delay startup.
class IntroPreferences {
  static const _storage = FlutterSecureStorage();
  static const _key = 'fc_teugn_intro_seen_v1';

  static Future<bool> shouldShow() async {
    try {
      return await _storage.read(key: _key).timeout(
                const Duration(milliseconds: 500),
              ) !=
          'yes';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      await _storage.write(key: _key, value: 'yes');
    } catch (_) {
      // Optional presentation preference; authentication remains unaffected.
    }
  }
}
