import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'api_client.dart';
import 'data_repository.dart';
import 'models/event.dart';
import 'models/communication.dart';
import 'models/matchday.dart';
import 'models/organization.dart';
import 'models/pitch_occupancy.dart';
import 'models/player.dart';
import 'models/training.dart';
import 'models/user.dart';
import 'models/team_operations.dart';
import 'models/personal_response.dart';
import 'models/support.dart';
import 'models/dashboard_summary.dart';
import 'offline_ticker.dart';
import 'offline_outbox.dart';
import 'loading/loading_controller.dart';
import 'push/native_push_service.dart';
import 'push/push_client.dart';

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

/// Prüft, ob auf genau diesem Gerät ein nutzbarer Push-Kanal aktiv ist.
///
/// Die Angabe aus der ursprünglichen Registrierung ist dafür nicht
/// zuverlässig: Push kann später in den Einstellungen aktiviert werden,
/// ohne dass die alte Registrierungsanfrage erneut geschrieben wird.
/// Deshalb sind auf Android der aktuelle FCM-Token und im Web das bestehende
/// Browser-Abonnement die maßgebliche Quelle für den Startklar-Status.
final currentDevicePushReadyProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null || user.status != AccountStatus.approved) return false;

  if (nativePushService.supported) {
    return await nativePushService.currentTokenIfEnabled() != null;
  }

  if (webPushSupported) {
    final configuration =
        await ref.watch(repositoryProvider).pushConfiguration();
    if (!configuration.webPushConfigured) return false;
    final status = await getWebPushStatus(configuration.vapidPublicKey);
    return status.subscribed &&
        status.permission == WebPushPermission.granted &&
        !status.keyMismatch;
  }

  // Plattformen ohne lokal prüfbaren Push-Kanal behalten die vorhandene
  // Kontoeinstellung als rückwärtskompatiblen Fallback.
  return user.registrationRequest?.pushOptIn == true;
});

final playersProvider =
    FutureProvider.autoDispose<List<PlayerModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 120));
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

final parentConsentAttentionProvider =
    FutureProvider.autoDispose<List<ParentConsentAttention>>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null || user.status != AccountStatus.approved) return const [];
  if (!user.parentPlayers.any(
    (link) => link.isLegalGuardian && link.playerId.isNotEmpty,
  )) {
    return const [];
  }
  return ref.watch(repositoryProvider).parentConsentAttention();
});

final eventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
  return ref.watch(repositoryProvider).events();
});

/// Bounded, category-filtered data for the match overview. Matchday details
/// (squad, lineup, ratings and ticker events) are loaded only after opening a
/// match, so the overview remains small while still covering the season.
final matchEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
  final now = DateTime.now();
  return ref.watch(repositoryProvider).events(
    from: now.subtract(const Duration(days: 180)),
    to: now.add(const Duration(days: 550)),
    categories: const [
      EventCategory.leagueMatch,
      EventCategory.friendlyMatch,
      EventCategory.cupMatch,
      EventCategory.tournament,
      EventCategory.indoorTournament,
      EventCategory.footballFestival,
    ],
  );
});

typedef EventQueryRange = ({DateTime from, DateTime to});

/// Loads only the period visible in the calendar. Month navigation therefore
/// no longer transfers and parses the entire season on every page build.
final calendarEventsProvider = FutureProvider.autoDispose
    .family<List<EventModel>, EventQueryRange>((ref, range) async {
  // Keep recently viewed calendar windows warm. This makes month swipes use
  // the prefetched adjacent window instead of briefly replacing the calendar
  // with a loading panel, while the cache still expires quickly.
  final cacheLink = ref.keepAlive();
  final cacheTimer = Timer(const Duration(minutes: 2), cacheLink.close);
  ref.onDispose(cacheTimer.cancel);
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
  return ref.watch(repositoryProvider).events(
        from: range.from,
        to: range.to,
      );
});

/// Kompakter Terminbereich für den Familien-Assistenten. Die Startseite
/// benötigt weder vergangene Monate noch die komplette Saison und lädt daher
/// nur die dort tatsächlich dargestellten acht Tage.
final parentDashboardEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  return ref.watch(repositoryProvider).events(
        from: dayStart,
        to: dayStart.add(const Duration(days: 8)),
      );
});

final parentDashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((ref) async {
  _watchManualRefresh(ref);
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  try {
    final summary = await ref.watch(repositoryProvider).dashboardSummary(
          trainer: false,
          from: dayStart,
          to: dayStart.add(const Duration(days: 8)),
        );
    _scheduleLiveRefresh(ref, const Duration(seconds: 60));
    return summary;
  } catch (_) {
    _scheduleLiveRefresh(ref, const Duration(seconds: 90));
    rethrow;
  }
});

final trainerDashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((ref) async {
  _watchManualRefresh(ref);
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  try {
    final summary = await ref.watch(repositoryProvider).dashboardSummary(
          trainer: true,
          from: dayStart.subtract(const Duration(days: 1)),
          to: dayStart.add(const Duration(days: 42)),
        );
    _scheduleLiveRefresh(ref, const Duration(seconds: 60));
    return summary;
  } catch (_) {
    _scheduleLiveRefresh(ref, const Duration(seconds: 90));
    rethrow;
  }
});

enum PersonalResponsePeriod { oneWeek, twoWeeks, fourWeeks, allUpcoming }

final personalResponsePeriodProvider = StateProvider<PersonalResponsePeriod>(
    (ref) => PersonalResponsePeriod.oneWeek);

final personalResponsesProvider =
    FutureProvider.autoDispose<List<PersonalResponseModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
  final period = ref.watch(personalResponsePeriodProvider);
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  final days = switch (period) {
    PersonalResponsePeriod.oneWeek => 7,
    PersonalResponsePeriod.twoWeeks => 14,
    PersonalResponsePeriod.fourWeeks => 28,
    PersonalResponsePeriod.allUpcoming => 370,
  };
  return ref.watch(repositoryProvider).personalResponses(
        from: dayStart.subtract(const Duration(days: 1)),
        to: dayStart.add(Duration(days: days)),
      );
});

bool _hasActiveTicker(List<MatchdayModel> matches) => matches.any((match) {
      return switch (match.ticker?.status) {
        TickerStatus.live ||
        TickerStatus.paused ||
        TickerStatus.halfTime ||
        TickerStatus.interrupted =>
          true,
        _ => false,
      };
    });

/// Spieltagsdaten für kompakte Familienansichten. Ohne laufenden Liveticker
/// genügt ein moderates Intervall. Während eines Spiels bleibt die bisherige
/// kurze Aktualisierung erhalten. Der begrenzte Zeitraum vermeidet, dass bei
/// jedem Lauf die komplette Spielhistorie samt Detaildaten übertragen wird.
final parentMatchdaysProvider =
    FutureProvider.autoDispose<List<MatchdayModel>>((ref) async {
  _watchManualRefresh(ref);
  final now = DateTime.now();
  try {
    final matches = await ref.watch(repositoryProvider).matches(
          from: now.subtract(const Duration(days: 1)),
          to: now.add(const Duration(days: 62)),
        );
    _scheduleLiveRefresh(
      ref,
      Duration(seconds: _hasActiveTicker(matches) ? 8 : 60),
    );
    return matches;
  } catch (_) {
    // Auch ein vorübergehender Netzfehler wird automatisch erneut versucht,
    // aber nicht in einer aggressiven Fehlerschleife.
    _scheduleLiveRefresh(ref, const Duration(seconds: 30));
    rethrow;
  }
});

final supportTicketsProvider =
    FutureProvider.autoDispose<List<SupportTicketModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
  return ref.watch(repositoryProvider).supportTickets();
});

final trainingsProvider =
    FutureProvider.autoDispose<List<TrainingModel>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 120));
  return ref.watch(repositoryProvider).trainings();
});

final outdoorPitchOccupancyProvider =
    FutureProvider.autoDispose<PitchOccupancyPlan>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
  return ref.watch(repositoryProvider).pitchOccupancy();
});

final indoorPitchOccupancyProvider =
    FutureProvider.autoDispose<PitchOccupancyPlan>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 90));
  return ref.watch(repositoryProvider).pitchOccupancy(indoor: true);
});

final pendingUsersProvider =
    FutureProvider.autoDispose<List<AppUser>>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 60));
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
  _scheduleLiveRefresh(ref, const Duration(seconds: 120));
  return ref.watch(repositoryProvider).members();
});

final organizationProvider =
    FutureProvider.autoDispose<OrganizationContext>((ref) async {
  _watchManualRefresh(ref);
  _scheduleLiveRefresh(ref, const Duration(seconds: 120));
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
    await Future<void>.delayed(const Duration(seconds: 60));
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
      ref.invalidate(parentDashboardSummaryProvider);
      ref.invalidate(trainerDashboardSummaryProvider);
      ref.invalidate(trainingsProvider);
      ref.invalidate(outdoorPitchOccupancyProvider);
      ref.invalidate(indoorPitchOccupancyProvider);
      await ref.read(organizationProvider.future);
      // Der Kontext selbst ist jetzt bestätigt. Die sichtbare Zielseite lädt
      // ihre kompakten Daten anschließend parallel; ein Wechsel muss nicht
      // auf komplette Kader- und Kalenderlisten warten.
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

/// Only the navigation-critical organization context blocks the first frame.
/// Dashboard summaries start on their actual page and can render their own
/// compact loading state, rather than delaying the entire application.
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
