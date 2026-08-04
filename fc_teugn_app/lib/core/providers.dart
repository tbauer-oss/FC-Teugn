import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'api_client.dart';
import 'data_repository.dart';
import 'models/event.dart';
import 'models/organization.dart';
import 'models/pitch_occupancy.dart';
import 'models/player.dart';
import 'models/training.dart';
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

final trainingsProvider = FutureProvider<List<TrainingModel>>((ref) async {
  return ref.watch(repositoryProvider).trainings();
});

final outdoorPitchOccupancyProvider =
    FutureProvider<PitchOccupancyPlan>((ref) async {
  return ref.watch(repositoryProvider).pitchOccupancy();
});

final indoorPitchOccupancyProvider =
    FutureProvider<PitchOccupancyPlan>((ref) async {
  return ref.watch(repositoryProvider).pitchOccupancy(indoor: true);
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

typedef AppBootstrapSession = ({String userId, UserRole role});

class AppBootstrapException implements Exception {
  const AppBootstrapException(this.resource, this.cause);

  final String resource;
  final Object cause;

  @override
  String toString() => '$resource konnte nicht geladen werden: $cause';
}

/// Lädt die sichtbaren Kerndaten einer angemeldeten Sitzung vollständig vor
/// und wärmt nachgelagerte Verwaltungsbereiche parallel im Hintergrund. Die
/// FutureProvider halten ihre Ergebnisse anschließend im Cache, sodass Seiten
/// dieselben Requests nicht erneut starten müssen. autoDispose sorgt dafür,
/// dass beim Abmelden keine Sitzung erhalten bleibt.
final sessionBootstrapProvider =
    FutureProvider.autoDispose.family<void, AppBootstrapSession>(
  (ref, session) async {
    Future<void> preload<T>(String resource, Future<T> future) async {
      try {
        await future;
      } catch (error) {
        throw AppBootstrapException(resource, error);
      }
    }

    final criticalTasks = <Future<void>>[
      preload('Mannschaftsdaten', ref.read(organizationProvider.future)),
      preload('Spielerdaten', ref.read(playersProvider.future)),
      preload('Kalenderdaten', ref.read(eventsProvider.future)),
    ];

    // Start the remaining requests at the same time, but do not keep the
    // launch screen open for administration data that is not needed on the
    // first visible page. Their providers still retain the result, so the
    // corresponding pages are normally warm by the time they are opened.
    final backgroundTasks = <Future<void>>[];

    Future<void> warmInBackground<T>(Future<T> future) async {
      try {
        await future;
      } catch (_) {
        // A secondary page renders its own retry state. A temporary failure
        // here must not prevent the complete app from starting.
      }
    }

    final isStaff = switch (session.role) {
      UserRole.superAdmin ||
      UserRole.clubAdmin ||
      UserRole.youthDirector ||
      UserRole.coach ||
      UserRole.assistantCoach ||
      UserRole.teamManager ||
      UserRole.trainerAdmin ||
      UserRole.trainer =>
        true,
      _ => false,
    };
    if (isStaff) {
      backgroundTasks.addAll([
        warmInBackground(ref.read(trainingsProvider.future)),
        warmInBackground(
          ref.read(outdoorPitchOccupancyProvider.future),
        ),
        warmInBackground(
          ref.read(indoorPitchOccupancyProvider.future),
        ),
      ]);
    }

    final canManageMembers = switch (session.role) {
      UserRole.superAdmin ||
      UserRole.clubAdmin ||
      UserRole.youthDirector ||
      UserRole.coach ||
      UserRole.teamManager ||
      UserRole.trainerAdmin ||
      UserRole.trainer =>
        true,
      _ => false,
    };
    if (canManageMembers) {
      backgroundTasks.addAll([
        warmInBackground(ref.read(pendingUsersProvider.future)),
        warmInBackground(ref.read(membersProvider.future)),
      ]);
    }

    unawaited(Future.wait(backgroundTasks));
    await Future.wait(criticalTasks);
  },
);

final teamOperationsProvider =
    FutureProvider.family<TeamOperationsOverview, String>((ref, teamId) async {
  return ref.watch(repositoryProvider).teamOperations(teamId);
});

final tickerOfflineQueueProvider = Provider<TickerOfflineQueue>((ref) {
  return TickerOfflineQueue();
});
