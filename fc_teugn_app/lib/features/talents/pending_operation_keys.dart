import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingOperationKeys {
  PendingOperationKeys(this.userId, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final String userId;
  final FlutterSecureStorage _storage;
  final Map<String, Future<String>> _pending = {};
  String _name(String fingerprint) =>
      'talents-operation-$userId-${sha256.convert(utf8.encode(fingerprint))}';
  Future<String> get(String fingerprint) async {
    try {
      return await _pending.putIfAbsent(fingerprint, () async {
        final stored = await _storage.read(key: _name(fingerprint));
        if (stored != null) {
          final split = stored.split(':');
          final created = int.tryParse(split.first);
          if (split.length == 2 &&
              created != null &&
              DateTime.now().millisecondsSinceEpoch - created <
                  const Duration(days: 6).inMilliseconds) {
            return split.last;
          }
        }
        final random = Random.secure();
        final key = List.generate(24,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
        await _storage.write(
            key: _name(fingerprint),
            value: '${DateTime.now().millisecondsSinceEpoch}:$key');
        return key;
      });
    } catch (_) {
      _pending.remove(fingerprint);
      rethrow;
    }
  }

  Future<void> complete(String fingerprint) async {
    await _storage.delete(key: _name(fingerprint));
    _pending.remove(fingerprint);
  }
}
