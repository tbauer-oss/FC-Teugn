import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api_client.dart';
import '../../core/biometric_auth/biometric_auth.dart';
import '../../core/loading/loading_controller.dart';
import '../../core/models/user.dart';
import '../../core/offline_outbox.dart';
import '../../core/offline_ticker.dart';
import '../../core/push/native_push_service.dart';

class AuthState {
  final AppUser? user;
  final String? accessToken;
  final bool loading;
  final String? error;
  final bool biometricLoginAvailable;
  final String? biometricAccountLabel;

  AuthState({
    this.user,
    this.accessToken,
    this.loading = false,
    this.error,
    this.biometricLoginAvailable = false,
    this.biometricAccountLabel,
  });

  AuthState copyWith({
    AppUser? user,
    String? accessToken,
    bool? loading,
    String? error,
    bool? biometricLoginAvailable,
    String? biometricAccountLabel,
  }) {
    return AuthState(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      loading: loading ?? this.loading,
      error: error,
      biometricLoginAvailable:
          biometricLoginAvailable ?? this.biometricLoginAvailable,
      biometricAccountLabel:
          biometricAccountLabel ?? this.biometricAccountLabel,
    );
  }
}

class BiometricLoginSettings {
  const BiometricLoginSettings({
    required this.capability,
    required this.enabled,
  });

  final BiometricCapability capability;
  final bool enabled;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    AppLoadingController? loadingController,
    FlutterSecureStorage? storage,
    BiometricAuthenticator? biometricAuthenticator,
  })  : _loadingController = loadingController,
        _storage = storage ?? const FlutterSecureStorage(),
        _biometricAuthenticator =
            biometricAuthenticator ?? createBiometricAuthenticator(),
        super(AuthState(loading: true)) {
    unawaited(_restore());
  }

  static const _refreshTokenKey = 'fc_teugn_refresh_token';
  static const _biometricCredentialKey = 'fc_teugn_biometric_credential';
  static const _biometricAccountKey = 'fc_teugn_biometric_account';
  final FlutterSecureStorage _storage;
  final BiometricAuthenticator _biometricAuthenticator;
  final AppLoadingController? _loadingController;
  Future<String?>? _refreshing;
  String? _refreshTokenCache;
  bool _refreshFailureInvalidatesSession = false;
  bool _refreshTokenReadFailed = false;

  Future<bool> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final res = await _client.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final data = res.data as Map<String, dynamic>;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = data['accessToken'] as String;
      await _storeRefreshToken(data['refreshToken'] as String);
      final biometricAccount = await _readBiometricAccount();
      if (biometricAccount != null &&
          biometricAccount.toLowerCase() != user.email.toLowerCase()) {
        await _clearBiometricPreference();
      }
      state = AuthState(user: user, accessToken: token, loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _messageFromError(e, fallback: 'Login fehlgeschlagen'),
      );
      return false;
    }
  }

  Future<String> requestPasswordReset(String email) async {
    try {
      final response = await ApiClient(
        loadingController: _loadingController,
      ).dio.post('/auth/password-reset/request', data: {'email': email});
      final data = response.data;
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Prüfe jetzt deine bereits registrierten Geräte.';
    } catch (error) {
      throw Exception(_messageFromError(
        error,
        fallback: 'Die Anfrage konnte gerade nicht gesendet werden.',
      ));
    }
  }

  Future<String> confirmPasswordReset({
    required String token,
    required String password,
  }) async {
    try {
      final response = await ApiClient(
        loadingController: _loadingController,
      ).dio.post('/auth/password-reset/confirm', data: {
        'token': token,
        'password': password,
      });
      final data = response.data;
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Dein Passwort wurde geändert.';
    } catch (error) {
      throw Exception(_messageFromError(
        error,
        fallback: 'Das Passwort konnte nicht geändert werden.',
      ));
    }
  }

  Future<String> exchangePasswordReset(String requestId) async {
    final deviceEndpoint = await nativePushService.currentTokenIfEnabled();
    if (deviceEndpoint == null || deviceEndpoint.trim().isEmpty) {
      throw Exception(
        'Auf diesem Gerät ist kein aktiver Push-Zugang registriert. Bitte öffne die Nachricht auf dem zuvor angemeldeten Gerät oder wende dich an die Systemadministration.',
      );
    }
    try {
      final response = await ApiClient(
        loadingController: _loadingController,
      ).dio.post(
            '/auth/password-reset/exchange',
            data: {
              'requestId': requestId,
              'deviceEndpoint': deviceEndpoint,
            },
            options: Options(extra: const {
              'loadingMessage': 'Sicherheitsanfrage wird geprüft …',
              'loadingMode': 'background',
            }),
          );
      final data = response.data;
      if (data is Map<String, dynamic> && data['token'] is String) {
        return data['token'] as String;
      }
      throw Exception('Die Sicherheitsanfrage konnte nicht bestätigt werden.');
    } catch (error) {
      if (error is Exception && error is! DioException) rethrow;
      throw Exception(_messageFromError(
        error,
        fallback: 'Die Sicherheitsanfrage konnte nicht bestätigt werden.',
      ));
    }
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
    required UserRole role,
    required List<String> teamIds,
    String? childName,
    String? relationship,
    required bool privacyAccepted,
    required bool termsAccepted,
    required bool pushOptIn,
    required String privacyTextVersionId,
    required String termsTextVersionId,
    String? pushTextVersionId,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final res = await _client.dio.post('/auth/register', data: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
        'phone': phone,
        'role': switch (role) {
          UserRole.coach || UserRole.trainer => 'COACH',
          UserRole.assistantCoach => 'ASSISTANT_COACH',
          UserRole.teamManager => 'TEAM_MANAGER',
          UserRole.player => 'PLAYER',
          _ => 'PARENT',
        },
        'teamIds': teamIds,
        'childName': childName,
        'relationship': relationship,
        'privacyAccepted': privacyAccepted,
        'termsAccepted': termsAccepted,
        'pushOptIn': pushOptIn,
        'privacyTextVersionId': privacyTextVersionId,
        'termsTextVersionId': termsTextVersionId,
        'pushTextVersionId': pushTextVersionId,
      });

      final data = res.data as Map<String, dynamic>;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = data['accessToken'] as String;
      await _storeRefreshToken(data['refreshToken'] as String);
      await _clearBiometricPreference();
      state = AuthState(user: user, accessToken: token, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _messageFromError(e, fallback: 'Registrierung fehlgeschlagen'),
      );
    }
  }

  Future<void> logout() async {
    final userId = state.user?.id;
    final accessToken = state.accessToken;
    final nativeToken = await nativePushService.currentTokenIfEnabled();
    if (accessToken != null && nativeToken != null) {
      try {
        await ApiClient(
          accessToken: accessToken,
          loadingController: _loadingController,
        ).dio.delete(
          '/notifications/settings/subscriptions',
          data: {'endpoint': nativeToken},
        );
      } catch (_) {}
    }
    await nativePushService.disable(forgetPreference: false);

    final refreshToken = await _readRefreshToken();
    if (refreshToken != null) {
      try {
        await ApiClient(loadingController: _loadingController).dio.post(
          '/auth/logout',
          data: {'refreshToken': refreshToken},
        );
      } catch (_) {}
    }
    await _deleteStoredToken();
    if (userId != null) {
      await GeneralOfflineOutbox().clearUser(userId);
      await TickerOfflineQueue().clearUser(userId);
    }
    if (!await _prepareBiometricLogin()) {
      state = AuthState();
    }
  }

  Future<AppUser> enterReadOnlyPreview(String userId) async {
    final actor = state.user;
    final token = state.accessToken;
    if (actor == null || token == null || actor.role != UserRole.superAdmin) {
      throw Exception(
        'Die Ansicht aus Sicht eines Mitglieds steht nur der Systemadministration zur Verfügung.',
      );
    }
    try {
      final response = await ApiClient(
        accessToken: token,
        viewAsUserId: userId,
        loadingController: _loadingController,
      ).dio.get('/auth/me');
      final previewUser =
          AppUser.fromJson(response.data as Map<String, dynamic>);
      state = state.copyWith(user: previewUser, error: null);
      return previewUser;
    } catch (error) {
      throw Exception(_messageFromError(
        error,
        fallback: 'Die Mitgliedsansicht konnte nicht geöffnet werden.',
      ));
    }
  }

  Future<AppUser> exitReadOnlyPreview() async {
    final token = state.accessToken;
    if (token == null) {
      throw Exception('Die Adminsitzung ist nicht mehr verfügbar.');
    }
    try {
      final response = await ApiClient(
        accessToken: token,
        loadingController: _loadingController,
      ).dio.get('/auth/me');
      final actor = AppUser.fromJson(response.data as Map<String, dynamic>);
      state = state.copyWith(user: actor, error: null);
      return actor;
    } catch (error) {
      throw Exception(_messageFromError(
        error,
        fallback: 'Die Adminansicht konnte nicht wiederhergestellt werden.',
      ));
    }
  }

  Future<String> updateOwnProfile({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  }) async {
    try {
      final response = await _client.dio.patch('/auth/me', data: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
      });
      final data = response.data as Map<String, dynamic>;
      final current = state.user;
      if (current != null) {
        state = state.copyWith(
          user: current.copyWithProfile(
            firstName: data['firstName'] as String? ?? firstName,
            lastName: data['lastName'] as String? ?? lastName,
            email: data['email'] as String? ?? email,
            phone: data['phone'] as String?,
          ),
          error: null,
        );
      }
      if (await _isBiometricLoginEnabled()) {
        await _storage.write(key: _biometricAccountKey, value: email);
      }
      return 'Deine persönlichen Daten wurden gespeichert.';
    } catch (error) {
      throw Exception(_messageFromError(
        error,
        fallback: 'Deine Daten konnten nicht gespeichert werden.',
      ));
    }
  }

  Future<String> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _client.dio.put('/auth/me/password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
      final data = response.data;
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Dein Passwort wurde geändert. Bitte melde dich erneut an.';
    } catch (error) {
      throw Exception(_messageFromError(
        error,
        fallback: 'Das Passwort konnte nicht geändert werden.',
      ));
    }
  }

  void clearSession() {
    final userId = state.user?.id;
    unawaited(_deleteStoredToken());
    unawaited(_clearBiometricPreference());
    unawaited(nativePushService.disable(forgetPreference: false));
    if (userId != null) {
      unawaited(GeneralOfflineOutbox().clearUser(userId));
      unawaited(TickerOfflineQueue().clearUser(userId));
    }
    state = AuthState();
  }

  void clearSessionAfterRefreshFailure() {
    if (_refreshFailureInvalidatesSession) clearSession();
  }

  Future<String?> refreshAccessToken() {
    return _refreshing ??= _refreshAccessToken().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<String?> _refreshAccessToken() async {
    var refreshToken = await _readRefreshToken();
    if (refreshToken == null) {
      // Ein nicht lesbarer Browser-/Gerätespeicher ist kein Beweis für eine
      // abgelaufene Sitzung. In diesem Fall bleibt die Startansicht aktiv und
      // bietet eine erneute Wiederherstellung an.
      _refreshFailureInvalidatesSession = !_refreshTokenReadFailed;
      return null;
    }
    final previewUser =
        state.user?.isReadOnlyPreview == true ? state.user : null;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        final res =
            await ApiClient(loadingController: _loadingController).dio.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );
        final data = res.data as Map<String, dynamic>;
        final accessToken = data['accessToken'] as String;
        await _storeRefreshToken(data['refreshToken'] as String);
        state = AuthState(
          // Die Mitgliedsvorschau hängt an der echten Adminsitzung. Eine
          // transparente Token-Verlängerung darf sie nicht sichtbar beenden.
          user: previewUser ??
              AppUser.fromJson(data['user'] as Map<String, dynamic>),
          accessToken: accessToken,
        );
        _refreshFailureInvalidatesSession = false;
        return accessToken;
      } catch (error) {
        if (isRefreshRotationConflict(error) && attempt < 2) {
          // Ein anderer Tab oder ein nahezu gleichzeitiger App-Start hat den
          // Token bereits erneuert. Kurz warten und anschließend zwingend den
          // neuesten Wert aus dem gemeinsamen sicheren Speicher lesen.
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
          final latest = await _readRefreshToken(preferStored: true);
          if (latest != null && latest.isNotEmpty) refreshToken = latest;
          continue;
        }
        // Eine kurzzeitig unterbrochene Verbindung oder ein Serverfehler darf
        // die dauerhaft gespeicherte Anmeldung nicht löschen. Nur eine
        // eindeutige Ablehnung des Refresh-Tokens beendet die Sitzung.
        if (discardStoredSessionAfterRefreshFailure(error)) {
          _refreshFailureInvalidatesSession = true;
          await _deleteStoredToken();
        } else {
          _refreshFailureInvalidatesSession = false;
        }
        return null;
      }
    }
    _refreshFailureInvalidatesSession = false;
    return null;
  }

  Future<void> _restore() async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final token = await refreshAccessToken();
      if (token != null || !mounted) return;
      if (_refreshFailureInvalidatesSession) {
        if (await _prepareBiometricLogin()) return;
        state = AuthState();
        return;
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (attempt + 1)),
        );
      }
    }
    if (mounted) {
      state = AuthState(
        loading: true,
        error:
            'Die gespeicherte Anmeldung konnte gerade nicht wiederhergestellt werden. Deine Sitzung bleibt erhalten.',
      );
    }
  }

  Future<void> retryStoredSession() async {
    if (state.user != null) return;
    state = AuthState(loading: true);
    await _restore();
  }

  void continueToLoginAfterRestoreFailure() {
    if (state.user != null) return;
    _refreshFailureInvalidatesSession = false;
    state = AuthState();
  }

  Future<BiometricLoginSettings> biometricLoginSettings() async {
    final capability = await _biometricAuthenticator.capability();
    return BiometricLoginSettings(
      capability: capability,
      enabled: await _isBiometricLoginEnabled(),
    );
  }

  Future<String> enableBiometricLogin() async {
    final user = state.user;
    if (user == null) {
      throw Exception('Bitte melde dich zuerst mit deinem Passwort an.');
    }
    final capability = await _biometricAuthenticator.capability();
    if (capability == BiometricCapability.notEnrolled) {
      throw Exception(
        'Auf diesem Gerät ist noch kein Fingerabdruck bzw. keine Gesichtserkennung eingerichtet.',
      );
    }
    if (capability != BiometricCapability.available) {
      throw Exception(
        'Biometrischer Login wird auf diesem Gerät nicht unterstützt.',
      );
    }
    final result = await _biometricAuthenticator.authenticate(
      reason: 'Biometrischen Login für FC Teugn Talents aktivieren',
    );
    if (result != BiometricAuthenticationResult.authenticated) {
      throw Exception(_biometricFailureMessage(result));
    }
    final response = await _client.dio.post('/auth/biometric/enroll');
    final data = response.data as Map<String, dynamic>;
    final credential = data['credential'] as String?;
    if (credential == null || credential.isEmpty) {
      throw Exception(
        'Die biometrische Geräteberechtigung konnte nicht erstellt werden.',
      );
    }
    await _storage.write(key: _biometricCredentialKey, value: credential);
    await _storage.write(key: _biometricAccountKey, value: user.email);
    return 'Biometrischer Login ist auf diesem Gerät aktiviert.';
  }

  Future<String> disableBiometricLogin() async {
    await _disableBiometricLoginOnServer();
    await _clearBiometricPreference();
    return 'Biometrischer Login ist auf diesem Gerät deaktiviert.';
  }

  Future<bool> unlockWithBiometrics() async {
    if (state.loading || !state.biometricLoginAvailable) return false;
    final accountLabel = state.biometricAccountLabel;
    state = AuthState(
      loading: true,
      biometricLoginAvailable: true,
      biometricAccountLabel: accountLabel,
    );
    final result = await _biometricAuthenticator.authenticate(
      reason: 'Bei FC Teugn Talents anmelden',
    );
    if (result != BiometricAuthenticationResult.authenticated) {
      state = AuthState(
        biometricLoginAvailable: true,
        biometricAccountLabel: accountLabel,
        error: _biometricFailureMessage(result),
      );
      return false;
    }

    final credential = await _readBiometricCredential();
    if (credential == null) {
      await _clearBiometricPreference();
      state = AuthState(
        error:
            'Die biometrische Geräteberechtigung fehlt. Bitte melde dich einmal mit deinem Passwort an.',
      );
      return false;
    }
    try {
      final response =
          await ApiClient(loadingController: _loadingController).dio.post(
        '/auth/biometric/login',
        data: {'credential': credential},
      );
      final data = response.data as Map<String, dynamic>;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      await _storeRefreshToken(data['refreshToken'] as String);
      state = AuthState(
        user: user,
        accessToken: data['accessToken'] as String,
      );
      return true;
    } catch (error) {
      final invalidCredential = error is DioException &&
          (error.response?.statusCode == 401 ||
              error.response?.statusCode == 403);
      if (invalidCredential) {
        await _clearBiometricPreference();
        state = AuthState(
          error:
              'Der biometrische Login ist abgelaufen. Bitte melde dich einmal mit deinem Passwort an und aktiviere ihn erneut.',
        );
      } else {
        state = AuthState(
          biometricLoginAvailable: true,
          biometricAccountLabel: accountLabel,
          error:
              'Der biometrische Login konnte gerade nicht abgeschlossen werden. Bitte prüfe die Verbindung oder nutze dein Passwort.',
        );
      }
      return false;
    }
  }

  Future<bool> _prepareBiometricLogin() async {
    if (!await _isBiometricLoginEnabled()) return false;
    final account = await _readBiometricAccount();
    state = AuthState(
      biometricLoginAvailable: true,
      biometricAccountLabel: account,
    );
    return true;
  }

  Future<bool> _isBiometricLoginEnabled() async {
    return await _readBiometricCredential() != null;
  }

  Future<String?> _readBiometricCredential() async {
    try {
      final credential = await _storage.read(key: _biometricCredentialKey);
      return credential?.trim().isEmpty == true ? null : credential;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readBiometricAccount() async {
    try {
      final account = await _storage.read(key: _biometricAccountKey);
      return account?.trim().isEmpty == true ? null : account;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearBiometricPreference() async {
    try {
      await _storage.delete(key: _biometricCredentialKey);
      await _storage.delete(key: _biometricAccountKey);
    } catch (_) {}
  }

  Future<void> _disableBiometricLoginOnServer() async {
    final credential = await _readBiometricCredential();
    final accessToken = state.accessToken;
    if (credential == null || accessToken == null) return;
    try {
      await ApiClient(
        accessToken: accessToken,
        loadingController: _loadingController,
      ).dio.delete(
        '/auth/biometric',
        data: {'credential': credential},
      );
    } catch (_) {
      // Die lokale Berechtigung wird trotzdem entfernt. Serverseitig läuft
      // ein nicht mehr zugänglicher Schlüssel automatisch aus.
    }
  }

  String _biometricFailureMessage(BiometricAuthenticationResult result) {
    return switch (result) {
      BiometricAuthenticationResult.cancelled =>
        'Biometrische Anmeldung wurde abgebrochen.',
      BiometricAuthenticationResult.unavailable =>
        'Biometrie ist aktuell nicht verfügbar. Nutze bitte dein Passwort.',
      BiometricAuthenticationResult.failed =>
        'Biometrie konnte dich nicht bestätigen. Versuche es erneut oder nutze dein Passwort.',
      BiometricAuthenticationResult.authenticated => '',
    };
  }

  Future<void> _storeRefreshToken(String token) async {
    _refreshTokenCache = token;
    _refreshFailureInvalidatesSession = false;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        await _storage.write(key: _refreshTokenKey, value: token);
        final persisted = await _storage.read(key: _refreshTokenKey);
        if (persisted == token) return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  }

  Future<String?> _readRefreshToken({bool preferStored = false}) async {
    final cached = _refreshTokenCache;
    // Browser-Tabs teilen sich den sicheren Web-Speicher, besitzen aber je
    // Tab einen eigenen Arbeitsspeicher. Deshalb darf ein alter Tab-Cache den
    // inzwischen rotierten, neueren Token nicht überstimmen.
    if (!kIsWeb && !preferStored && cached != null && cached.isNotEmpty) {
      _refreshTokenReadFailed = false;
      return cached;
    }
    try {
      final stored = await _storage.read(key: _refreshTokenKey);
      _refreshTokenReadFailed = false;
      if (stored != null && stored.isNotEmpty) {
        _refreshTokenCache = stored;
        return stored;
      }
    } catch (_) {
      _refreshTokenReadFailed = true;
      return cached;
    }
    return cached;
  }

  Future<void> _deleteStoredToken() async {
    _refreshTokenCache = null;
    try {
      await _storage.delete(key: _refreshTokenKey);
    } catch (_) {}
  }

  String _messageFromError(Object e, {required String fallback}) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return fallback;
  }

  ApiClient get _client => ApiClient(
        accessToken: state.accessToken,
        viewAsUserId: state.user?.preview?.targetId,
        loadingController: _loadingController,
      );

  ApiClient get client => _client;
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(loadingController: ref.read(appLoadingProvider));
});

@visibleForTesting
bool discardStoredSessionAfterRefreshFailure(Object error) {
  if (error is! DioException) return false;
  return switch (error.response?.statusCode) {
    401 || 403 => true,
    _ => false,
  };
}

@visibleForTesting
bool isRefreshRotationConflict(Object error) {
  if (error is! DioException || error.response?.statusCode != 409) {
    return false;
  }
  final data = error.response?.data;
  return data is Map<String, dynamic> &&
      data['code'] == 'REFRESH_TOKEN_ROTATED';
}
