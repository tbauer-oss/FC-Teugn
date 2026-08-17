import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SpielPlusCredentials {
  const SpielPlusCredentials({
    this.username = '',
    this.password = '',
    this.automaticLogin = false,
  });

  final String username;
  final String password;
  final bool automaticLogin;

  bool get hasUsername => username.trim().isNotEmpty;
  bool get hasPassword => password.isNotEmpty;
  bool get isComplete => hasUsername && hasPassword;

  SpielPlusCredentials copyWith({
    String? username,
    String? password,
    bool? automaticLogin,
  }) {
    return SpielPlusCredentials(
      username: username ?? this.username,
      password: password ?? this.password,
      automaticLogin: automaticLogin ?? this.automaticLogin,
    );
  }
}

abstract class SpielPlusCredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSpielPlusCredentialStorage implements SpielPlusCredentialStorage {
  SecureSpielPlusCredentialStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SpielPlusCredentialsStore {
  SpielPlusCredentialsStore({
    required String userId,
    SpielPlusCredentialStorage? storage,
  })  : _userKey = base64Url.encode(utf8.encode(userId)),
        _storage = storage ?? SecureSpielPlusCredentialStorage();

  final String _userKey;
  final SpielPlusCredentialStorage _storage;

  String get _usernameKey => 'fc_teugn_spielplus_username_v1_$_userKey';
  String get _passwordKey => 'fc_teugn_spielplus_password_v1_$_userKey';
  String get _automaticLoginKey =>
      'fc_teugn_spielplus_automatic_login_v1_$_userKey';

  Future<SpielPlusCredentials> load() async {
    final values = await Future.wait([
      _storage.read(_usernameKey),
      _storage.read(_passwordKey),
      _storage.read(_automaticLoginKey),
    ]);
    final credentials = SpielPlusCredentials(
      username: values[0] ?? '',
      password: values[1] ?? '',
      automaticLogin: values[2] == 'true',
    );
    return credentials.isComplete
        ? credentials
        : credentials.copyWith(automaticLogin: false);
  }

  Future<void> save(SpielPlusCredentials credentials) async {
    final username = credentials.username.trim();
    final automaticLogin = credentials.automaticLogin &&
        username.isNotEmpty &&
        credentials.password.isNotEmpty;
    await Future.wait([
      _writeOrDelete(_usernameKey, username),
      _writeOrDelete(_passwordKey, credentials.password),
      _storage.write(_automaticLoginKey, automaticLogin.toString()),
    ]);
  }

  Future<void> clear() => Future.wait([
        _storage.delete(_usernameKey),
        _storage.delete(_passwordKey),
        _storage.delete(_automaticLoginKey),
      ]);

  Future<void> _writeOrDelete(String key, String value) =>
      value.isEmpty ? _storage.delete(key) : _storage.write(key, value);
}
