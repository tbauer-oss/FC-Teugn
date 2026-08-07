import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api_client.dart';
import '../../core/loading/loading_controller.dart';
import '../../core/models/user.dart';
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

    String? refreshToken;
    try {
      refreshToken = await _storage.read(key: _refreshTokenKey);
    } catch (_) {}
    if (refreshToken != null) {
      try {
        await ApiClient(loadingController: _loadingController).dio.post(
          '/auth/logout',
          data: {'refreshToken': refreshToken},
        );
      } catch (_) {}
    }
    await _deleteStoredToken();
    state = AuthState();
  }

  void clearSession() {
    unawaited(_deleteStoredToken());
    unawaited(nativePushService.disable(forgetPreference: false));
    state = AuthState();
  }

  Future<String?> refreshAccessToken() {
    return _refreshing ??= _refreshAccessToken().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<String?> _refreshAccessToken() async {
    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken == null) return null;
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
      return accessToken;
    } catch (_) {
      await _deleteStoredToken();
      return null;
    }
  }

  Future<void> _restore() async {
    final token = await refreshAccessToken();
    if (token == null && mounted) state = AuthState();
  }

  Future<void> _storeRefreshToken(String token) async {
    try {
      await _storage.write(key: _refreshTokenKey, value: token);
    } catch (_) {}
  }

  Future<void> _deleteStoredToken() async {
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
