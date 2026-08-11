import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api_client.dart';
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

  AuthState({
    this.user,
    this.accessToken,
    this.loading = false,
    this.error,
  });

  AuthState copyWith({
    AppUser? user,
    String? accessToken,
    bool? loading,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({AppLoadingController? loadingController})
      : _loadingController = loadingController,
        super(AuthState(loading: true)) {
    unawaited(_restore());
  }

  static const _refreshTokenKey = 'fc_teugn_refresh_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AppLoadingController? _loadingController;
  Future<String?>? _refreshing;
  String? _refreshTokenCache;
  bool _refreshFailureInvalidatesSession = false;
  bool _refreshTokenReadFailed = false;

  Future<void> login(String email, String password) async {
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
      state = AuthState(user: user, accessToken: token, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _messageFromError(e, fallback: 'Login fehlgeschlagen'),
      );
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
    state = AuthState();
  }

  void clearSession() {
    final userId = state.user?.id;
    unawaited(_deleteStoredToken());
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
          user: AppUser.fromJson(data['user'] as Map<String, dynamic>),
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
