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

/// Hält die Meldungsanzeige ohne manuelles Neuladen aktuell. Native Push-
/// Nachrichten bleiben unmittelbar; der Web-Fallback vermeidet mit einem
/// moderaten Intervall dauerhafte Datenbanklast durch jede offene Sitzung.
final liveNotificationsProvider =
    StreamProvider.autoDispose<List<AppNotificationModel>>((ref) async* {
  while (true) {
    yield await ref.read(repositoryProvider).notifications();
    await Future<void>.delayed(const Duration(seconds: 10));
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
      await ref.read(organizationProvider.future);
      await Future.wait([
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

/// Lädt nur die drei Datenbereiche vor, die jede erste Hauptansicht benötigt.
/// Mannschaftsdaten werden zuerst geladen; Spieler und Kalender folgen mit
/// höchstens zwei parallelen Requests. Rollenabhängige Spezialseiten laden ihre
/// Daten erst beim Öffnen. So erzeugt der App-Start keine acht gleichzeitigen
/// Datenbankabfragen mehr.
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

    // The family key intentionally contains the user and role so a changed
    // session can never reuse another account's bootstrap state.
    if (session.userId.isEmpty) return;
    await preload(
      'Mannschaftsdaten',
      ref.read(organizationProvider.future),
    );
    await Future.wait([
      preload('Spielerdaten', ref.read(playersProvider.future)),
      preload('Kalenderdaten', ref.read(eventsProvider.future)),
    ]);
  },
);

final teamOperationsProvider =
    FutureProvider.family<TeamOperationsOverview, String>((ref, teamId) async {
  return ref.watch(repositoryProvider).teamOperations(teamId);
});

final tickerOfflineQueueProvider = Provider<TickerOfflineQueue>((ref) {
  return TickerOfflineQueue();
});
