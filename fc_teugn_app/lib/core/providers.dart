import 'dart:async';

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
  return ref.watch(repositoryProvider).pendingUsers();
});

final membersProvider = FutureProvider<List<AppUser>>((ref) async {
  return ref.watch(repositoryProvider).members();
});

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
