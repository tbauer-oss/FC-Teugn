import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'api_client.dart';
import 'data_repository.dart';
import 'models/event.dart';
import 'models/organization.dart';
import 'models/player.dart';
import 'models/user.dart';
import 'models/team_operations.dart';
import 'offline_ticker.dart';
import 'push/native_push_service.dart';

final repositoryProvider = Provider<DataRepository>((ref) {
  final authState = ref.watch(authProvider);
  final controller = ref.read(authProvider.notifier);
  final client = ApiClient(
    accessToken: authState.accessToken,
    refreshAccessToken: controller.refreshAccessToken,
    onSessionExpired: controller.clearSession,
  );
  return DataRepository(client);
});

/// Keeps the FCM token for an approved, opted-in Android account registered.
final nativePushRegistrationProvider = FutureProvider<void>((ref) async {
  final authState = ref.watch(authProvider);
  final user = authState.user;
  if (user == null ||
      user.status != AccountStatus.approved ||
      authState.accessToken == null ||
      !nativePushService.supported) {
    return;
  }

  final accountOptIn = user.registrationRequest?.pushOptIn == true;
  final shouldRegister = await nativePushService.shouldAutomaticallyRegister(
    accountOptIn: accountOptIn,
  );
  if (!shouldRegister) return;

  final token = await nativePushService.enable();
  if (token == null) return;
  final repository = ref.read(repositoryProvider);
  if (!accountOptIn) await repository.grantPushConsent();
  await repository.registerAndroidPushSubscription(token);

  final refreshSubscription = nativePushService.tokenRefreshes.listen(
    (refreshedToken) {
      unawaited(
        repository
            .registerAndroidPushSubscription(refreshedToken)
            .then<void>((_) {})
            .catchError((_) {}),
      );
    },
  );
  ref.onDispose(() => unawaited(refreshSubscription.cancel()));
});

final playersProvider = FutureProvider<List<PlayerModel>>((ref) async {
  return ref.watch(repositoryProvider).players();
});

final playerProvider =
    FutureProvider.family<PlayerModel, String>((ref, playerId) async {
  return ref.watch(repositoryProvider).player(playerId);
});

final consentTemplatesProvider =
    FutureProvider<List<ConsentTemplate>>((ref) async {
  return ref.watch(repositoryProvider).consentTemplates();
});

final eventsProvider = FutureProvider<List<EventModel>>((ref) async {
  return ref.watch(repositoryProvider).events();
});

final pendingUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  return loadWithTransientRetry(repository.pendingUsers);
});

final membersProvider = FutureProvider<List<AppUser>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  return loadWithTransientRetry(repository.members);
});

/// Wiederholt kurzzeitige API-Ausfälle beim ersten Seitenaufruf automatisch.
/// So bleibt ein Vercel-Kaltstart oder ein kurzer Netzwechsel im Ladezustand,
/// statt sofort eine Fehlerkarte zu zeigen, die erst per Pull-to-refresh
/// verschwindet.
Future<T> loadWithTransientRetry<T>(
  Future<T> Function() load, {
  int maxAttempts = 4,
  Duration initialDelay = const Duration(milliseconds: 250),
}) async {
  assert(maxAttempts > 0);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await load();
    } catch (error) {
      final isLastAttempt = attempt == maxAttempts - 1;
      if (isLastAttempt || !_isTransientRequestFailure(error)) rethrow;
      await Future<void>.delayed(initialDelay * (1 << attempt));
    }
  }
  throw StateError('Unreachable retry state');
}

bool _isTransientRequestFailure(Object error) {
  if (error is! DioException) return false;
  final status = error.response?.statusCode;
  return status == null || status == 408 || status == 429 || status >= 500;
}

final organizationProvider = FutureProvider<OrganizationContext>((ref) async {
  return ref.watch(repositoryProvider).organizationContext();
});

final teamOperationsProvider =
    FutureProvider.family<TeamOperationsOverview, String>((ref, teamId) async {
  return ref.watch(repositoryProvider).teamOperations(teamId);
});

final tickerOfflineQueueProvider = Provider<TickerOfflineQueue>((ref) {
  return TickerOfflineQueue();
});
