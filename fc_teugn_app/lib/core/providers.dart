import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'api_client.dart';
import 'data_repository.dart';
import 'models/event.dart';
import 'models/communication.dart';
import 'models/organization.dart';
import 'models/pitch_occupancy.dart';
import 'models/player.dart';
import 'models/training.dart';
import 'models/user.dart';
import 'models/team_operations.dart';
import 'offline_ticker.dart';
import 'offline_outbox.dart';
import 'loading/loading_controller.dart';
import 'push/native_push_service.dart';

final offlineOutboxProvider = Provider<GeneralOfflineOutbox>(
  (ref) => GeneralOfflineOutbox(),
);

final repositoryProvider = Provider<DataRepository>((ref) {
  final authState = ref.watch(authProvider);
  final controller = ref.read(authProvider.notifier);
  final client = ApiClient(
    accessToken: authState.accessToken,
    refreshAccessToken: controller.refreshAccessToken,
    onSessionExpired: controller.clearSession,
    offlineOutbox: ref.watch(offlineOutboxProvider),
    userId: authState.user?.id,
    loadingController: ref.read(appLoadingProvider),
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

final offlineOutboxCountProvider =
    StreamProvider.autoDispose<int>((ref) async* {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) {
    yield 0;
    return;
  }
  while (true) {
    yield (await ref.read(offlineOutboxProvider).pending(userId)).length;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});

/// Hält die Meldungsanzeige ohne manuelles Neuladen aktuell. Das kurze
/// Intervall ist zugleich der Web-Fallback, wenn keine native Push-Verbindung
/// aktiv ist.
final liveNotificationsProvider =
    StreamProvider.autoDispose<List<AppNotificationModel>>((ref) async* {
  while (true) {
    yield await ref.read(repositoryProvider).notifications();
    await Future<void>.delayed(const Duration(seconds: 4));
  }
});

class WorkingContextState {
  const WorkingContextState({this.switching = false, this.error});
  final bool switching;
  final String? error;
}

class WorkingContextController extends StateNotifier<WorkingContextState> {
  WorkingContextController(this.ref) : super(const WorkingContextState());
  final Ref ref;

  Future<bool> select({
    required String ageGroupId,
    String? teamId,
    required bool includeAllTeams,
  }) async {
    if (state.switching) return false;
    state = const WorkingContextState(switching: true);
    try {
      await ref.read(repositoryProvider).updateOrganizationContext(
            ageGroupId: ageGroupId,
            teamId: teamId,
            includeAllTeams: includeAllTeams,
          );
      ref.invalidate(organizationProvider);
      ref.invalidate(playersProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(trainingsProvider);
      ref.invalidate(outdoorPitchOccupancyProvider);
      ref.invalidate(indoorPitchOccupancyProvider);
      await Future.wait([
        ref.read(organizationProvider.future),
        ref.read(playersProvider.future),
        ref.read(eventsProvider.future),
      ]);
      state = const WorkingContextState();
      return true;
    } catch (error) {
      state = WorkingContextState(error: error.toString());
      return false;
    }
  }
}

final workingContextControllerProvider =
    StateNotifierProvider<WorkingContextController, WorkingContextState>(
  (ref) => WorkingContextController(ref),
);

typedef AppBootstrapSession = ({String userId, UserRole role});

class AppBootstrapException implements Exception {
  const AppBootstrapException(this.resource, this.cause);

  final String resource;
  final Object cause;

  @override
  String toString() => '$resource konnte nicht geladen werden: $cause';
}

/// Lädt die Kerndaten einer angemeldeten Sitzung vollständig vor. Die
/// aufgerufenen FutureProvider halten ihre Ergebnisse anschließend im Cache,
/// sodass die erste sichtbare Seite nicht dieselben Requests erneut starten
/// muss. autoDispose sorgt dafür, dass beim Abmelden keine Sitzung erhalten
/// bleibt.
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

    final tasks = <Future<void>>[
      preload('Mannschaftsdaten', ref.read(organizationProvider.future)),
      preload('Spielerdaten', ref.read(playersProvider.future)),
      preload('Kalenderdaten', ref.read(eventsProvider.future)),
    ];

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
      tasks.addAll([
        preload('Trainingsdaten', ref.read(trainingsProvider.future)),
        preload(
          'Platzbelegung',
          ref.read(outdoorPitchOccupancyProvider.future),
        ),
        preload(
          'Hallenbelegung',
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
      tasks.addAll([
        preload('Offene Freigaben', ref.read(pendingUsersProvider.future)),
        preload('Mitgliederdaten', ref.read(membersProvider.future)),
      ]);
    }

    await Future.wait(tasks);
  },
);

final teamOperationsProvider =
    FutureProvider.family<TeamOperationsOverview, String>((ref, teamId) async {
  return ref.watch(repositoryProvider).teamOperations(teamId);
});

final tickerOfflineQueueProvider = Provider<TickerOfflineQueue>((ref) {
  return TickerOfflineQueue();
});
