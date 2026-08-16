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
import 'models/personal_response.dart';
import 'models/support.dart';
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
    onSessionExpired: controller.clearSessionAfterRefreshFailure,
    offlineOutbox: ref.watch(offlineOutboxProvider),
    userId: authState.user?.id,
    loadingController: ref.read(appLoadingProvider),
    onOfflineSynchronizationComplete: () {
      ref.read(manualDataRefreshProvider.notifier).state++;
    },
  );
  return DataRepository(client);
});

/// A lightweight signal for user-initiated refreshes. Data providers watch
/// this value, so only providers that are currently in use are fetched again.
/// This avoids rebuilding the session or restarting the whole application.
final manualDataRefreshProvider = StateProvider<int>((ref) => 0);

void _watchManualRefresh(Ref ref) {
  ref.watch(manualDataRefreshProvider);
}

void _scheduleLiveRefresh(Ref ref, Duration interval) {
  final timer = Timer(interval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

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
  if (!accountOptIn) await repository.grantPushConsent(silent: true);
  await repository.registerAndroidPushSubscription(token, silent: true);

  final refreshSubscription = nativePushService.tokenRefreshes.listen(
    (refreshedToken) {
      unawaited(
        repository
            .registerAndroidPushSubscription(refreshedToken, silent: true)
            .then<void>((_) {})
            .catchError((_) {}),
      );
    },
  );
  ref.onDispose(() => unawaited(refreshSubscription.cancel()));
});

final playersProvider =
    FutureProvider.autoDispose<List<PlayerModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
  return ref.watch(repositoryProvider).players();
});

final playerProvider = FutureProvider.autoDispose
    .family<PlayerModel, String>((ref, playerId) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
  return ref.watch(repositoryProvider).player(playerId);
});

final consentTemplatesProvider =
    FutureProvider<List<ConsentTemplate>>((ref) async {
  return ref.watch(repositoryProvider).consentTemplates();
});

class ParentConsentAttention {
  const ParentConsentAttention({
    required this.playerId,
    required this.playerName,
    required this.openCount,
  });

  final String playerId;
  final String playerName;
  final int openCount;
}

final parentConsentAttentionProvider =
    FutureProvider.autoDispose<List<ParentConsentAttention>>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null || user.status != AccountStatus.approved) return const [];
  final links = <String, UserParentPlayerLink>{
    for (final link in user.parentPlayers)
      if (link.isLegalGuardian && link.playerId.isNotEmpty) link.playerId: link,
  };
  if (links.isEmpty) return const [];

  final repository = ref.watch(repositoryProvider);
  final templates = await ref.watch(consentTemplatesProvider.future);
  final result = <ParentConsentAttention>[];
  for (final link in links.values) {
    final player = await repository.player(link.playerId);
    final open = openConsentTemplates(player.consents, templates);
    if (open.isNotEmpty) {
      result.add(ParentConsentAttention(
        playerId: player.id,
        playerName: player.fullName,
        openCount: open.length,
      ));
    }
  }
  return result;
});

final eventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 30));
  return ref.watch(repositoryProvider).events();
});

final personalResponsesProvider =
    FutureProvider.autoDispose<List<PersonalResponseModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 20));
  return ref.watch(repositoryProvider).personalResponses();
});

final supportTicketsProvider =
    FutureProvider.autoDispose<List<SupportTicketModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 45));
  return ref.watch(repositoryProvider).supportTickets();
});

final trainingsProvider =
    FutureProvider.autoDispose<List<TrainingModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
  return ref.watch(repositoryProvider).trainings();
});

final outdoorPitchOccupancyProvider =
    FutureProvider.autoDispose<PitchOccupancyPlan>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 45));
  return ref.watch(repositoryProvider).pitchOccupancy();
});

final indoorPitchOccupancyProvider =
    FutureProvider.autoDispose<PitchOccupancyPlan>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 45));
  return ref.watch(repositoryProvider).pitchOccupancy(indoor: true);
});

final pendingUsersProvider =
    FutureProvider.autoDispose<List<AppUser>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 30));
  return ref.watch(repositoryProvider).pendingUsers();
});

/// Registrierungen, die in dieser laufenden Sitzung bereits erfolgreich
/// abgeschlossen wurden. Die serverseitige Liste wird danach ebenfalls neu
/// geladen; dieser kleine lokale Overlay-State entfernt den Eintrag jedoch
/// schon im selben Frame aus Listen, Badges und Dashboard-Karten.
final dismissedPendingRegistrationIdsProvider =
    StateProvider<Set<String>>((ref) => <String>{});

AsyncValue<List<AppUser>> visiblePendingUsers(
  AsyncValue<List<AppUser>> pending,
  Set<String> dismissedIds,
) =>
    pending.whenData(
      (users) => users
          .where((user) => !dismissedIds.contains(user.id))
          .toList(growable: false),
    );

final membersProvider = FutureProvider.autoDispose<List<AppUser>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
  return ref.watch(repositoryProvider).members();
});

final organizationProvider =
    FutureProvider.autoDispose<OrganizationContext>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
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
  _watchManualRefresh(ref);
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

final teamOperationsProvider = FutureProvider.autoDispose
    .family<TeamOperationsOverview, String>((ref, teamId) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 45));
  return ref.watch(repositoryProvider).teamOperations(teamId);
});

final tickerOfflineQueueProvider = Provider<TickerOfflineQueue>((ref) {
  return TickerOfflineQueue();
});
