import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/models/user.dart';

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
  AuthController() : super(AuthState());

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
      state = AuthState(user: user, accessToken: token, loading: false);
    } catch (e) {
      String? message;
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['message'] is String) {
          message = data['message'] as String;
        }
      }

      state = state.copyWith(
        loading: false,
        error: message ?? 'Login fehlgeschlagen',
      );
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    required UserRole role,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final res = await _client.dio.post('/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
        'phone': phone,
        'role': role == UserRole.coach ? 'COACH' : 'PARENT',
      });

      final data = res.data as Map<String, dynamic>;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = data['accessToken'] as String;
      state = AuthState(user: user, accessToken: token, loading: false);
    } catch (e) {
      String? message;
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['message'] is String) {
          message = data['message'] as String;
        }
      }

      state = state.copyWith(
        loading: false,
        error: message ?? 'Registrierung fehlgeschlagen',
      );
    }
  }

  void logout() {
    state = AuthState();
  }

  ApiClient get _client => ApiClient(accessToken: state.accessToken);

  ApiClient get client => _client;
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});
