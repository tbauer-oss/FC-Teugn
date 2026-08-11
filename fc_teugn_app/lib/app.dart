import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/widgets/adaptive_layout.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/auth/pending_page.dart';
import 'features/auth/account_settings_page.dart';
import 'features/shell/app_shell.dart';
import 'features/trainer/trainer_dashboard_page.dart';
import 'features/trainer/trainer_team_page.dart';
import 'features/trainer/trainer_approvals_page.dart';
import 'features/trainer/trainer_players_page.dart';
import 'features/trainer/trainer_events_page.dart';
import 'features/trainer/trainer_matches_page.dart';
import 'features/parent/parent_dashboard_page.dart';
import 'features/parent/parent_players_page.dart';
import 'features/parent/parent_events_page.dart';
import 'features/parent/parent_matches_page.dart';
import 'features/organization/organization_page.dart';
import 'features/players/player_profile_page.dart';
import 'features/matches/matchday_page.dart';
import 'features/matches/bfv_competition_page.dart';
import 'features/matches/bfv_browser_page.dart';
import 'features/statistics/statistics_page.dart';
import 'features/training/training_pages.dart';
import 'features/communications/communications_page.dart';
import 'features/operations/team_operations_page.dart';
import 'features/privacy/privacy_page.dart';
import 'features/privacy/parent_consent_prompt.dart';
import 'features/help/help_page.dart';
import 'features/support/support_page.dart';
import 'features/shared/family_responses.dart';
import 'features/launch/animated_launch_screen.dart';
import 'features/shared/app_update_dialog.dart';
import 'core/models/communication.dart';
import 'core/models/user.dart';
import 'core/app_identity.dart';
import 'core/app_theme.dart';
import 'core/app_update/app_update_service.dart';
import 'core/providers.dart';
import 'core/loading/loading_widgets.dart';
import 'core/push/initial_push_prompt.dart';
import 'core/push/native_push_service.dart';
import 'core/push/push_client.dart';

class FCTeugnApp extends ConsumerStatefulWidget {
  const FCTeugnApp({super.key});

  @override
  ConsumerState<FCTeugnApp> createState() => _FCTeugnAppState();
}

class _FCTeugnAppState extends ConsumerState<FCTeugnApp> {
  static const _minimumLaunchDuration = Duration(milliseconds: 2800);
  Timer? _launchTimer;
  StreamSubscription<String>? _pushActionSubscription;
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  GoRouter? _activeRouter;
  String? _pendingPushAction;
  bool _minimumLaunchComplete = false;
  bool _initialPushPromptScheduled = false;
  bool _startupPromptsScheduled = false;
  bool _parentConsentPromptScheduled = false;
  String? _parentConsentPromptShownUserId;

  @override
  void initState() {
    super.initState();
    _pendingPushAction = nativePushService.takePendingAction();
    _pushActionSubscription = nativePushService.actions.listen((action) {
      _pendingPushAction = action;
      _openPendingPushAction();
    });
    _launchTimer = Timer(_minimumLaunchDuration, () {
      if (mounted) setState(() => _minimumLaunchComplete = true);
    });
  }

  @override
  void dispose() {
    _launchTimer?.cancel();
    unawaited(_pushActionSubscription?.cancel());
    _activeRouter?.dispose();
    super.dispose();
  }

  void _openPendingPushAction() {
    final action = _pendingPushAction;
    final router = _activeRouter;
    final user = ref.read(authProvider).user;
    if (action == null || router == null) return;
    final parsedAction = Uri.tryParse(action.trim());
    if (parsedAction?.path == '/reset-password' &&
        ((parsedAction?.queryParameters['token']?.isNotEmpty ?? false) ||
            (parsedAction?.queryParameters['requestId']?.isNotEmpty ??
                false))) {
      _pendingPushAction = null;
      final route = Uri(
        path: '/reset-password',
        queryParameters: {
          if (parsedAction!.queryParameters['token']?.isNotEmpty ?? false)
            'token': parsedAction.queryParameters['token']!,
          if (parsedAction.queryParameters['requestId']?.isNotEmpty ?? false)
            'requestId': parsedAction.queryParameters['requestId']!,
        },
      ).toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) router.go(route);
      });
      return;
    }
    if (user == null) return;
    _pendingPushAction = null;
    final route = normalizePushActionRoute(
      action,
      isTrainer: user.isTrainer,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) router.go(route);
    });
  }

  void _scheduleStartupPrompts() {
    if (_startupPromptsScheduled) return;
    _startupPromptsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final update = await appUpdateService.checkForUpdate();
        if (!mounted || update == null) return;
        final updateContext = _rootNavigatorKey.currentContext;
        if (updateContext == null || !updateContext.mounted) return;
        await showDialog<void>(
          context: updateContext,
          barrierDismissible: !update.mandatory,
          builder: (_) => AppUpdateDialog(manifest: update),
        );
      } catch (_) {
        // Die Update-Prüfung läuft bewusst im Hintergrund. Ein kurzzeitig
        // nicht erreichbarer Update-Speicher darf den App-Start nie stören.
      } finally {
        if (mounted) _scheduleParentConsentPrompt();
      }
    });
  }

  void _scheduleParentConsentPrompt() {
    final user = ref.read(authProvider).user;
    final legalGuardianLinks = user?.parentPlayers
            .where((link) => link.isLegalGuardian && link.playerId.isNotEmpty)
            .toList() ??
        const [];
    if (user == null ||
        user.status != AccountStatus.approved ||
        legalGuardianLinks.isEmpty) {
      _scheduleInitialPushPrompt();
      return;
    }
    if (_parentConsentPromptScheduled ||
        _parentConsentPromptShownUserId == user.id) {
      _scheduleInitialPushPrompt();
      return;
    }
    _parentConsentPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final items = await ref.read(parentConsentAttentionProvider.future);
        if (!mounted || items.isEmpty) return;
        final promptContext = _rootNavigatorKey.currentContext;
        if (promptContext == null || !promptContext.mounted) return;
        _parentConsentPromptShownUserId = user.id;
        final action = await showDialog<ParentConsentPromptAction>(
          context: promptContext,
          barrierDismissible: false,
          builder: (_) => ParentConsentPromptDialog(items: items),
        );
        if (!mounted || action != ParentConsentPromptAction.review) return;
        final target = items.first.playerId;
        final base = user.isTrainer ? '/trainer/players' : '/parent/players';
        _activeRouter?.go('$base/$target?consents=1');
      } catch (_) {
        // Der Hinweis darf den App-Start bei einer kurzzeitig nicht
        // erreichbaren Einwilligungsübersicht nicht blockieren.
      } finally {
        _parentConsentPromptScheduled = false;
        if (mounted) _scheduleInitialPushPrompt();
      }
    });
  }

  void _scheduleInitialPushPrompt() {
    if (_initialPushPromptScheduled ||
        (!nativePushService.supported && !webPushSupported)) {
      return;
    }
    _initialPushPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final native = nativePushService.supported;
      PushConfiguration? webConfiguration;
      if (native) {
        if (!mounted || !await nativePushService.shouldShowInitialPrompt()) {
          return;
        }
      } else {
        final repository = ref.read(repositoryProvider);
        webConfiguration = await repository.pushConfiguration();
        if (!mounted ||
            !webConfiguration.webPushConfigured ||
            !await shouldShowInitialWebPushPrompt()) {
          return;
        }
      }
      final promptContext = _rootNavigatorKey.currentContext;
      if (promptContext == null || !promptContext.mounted || !mounted) {
        _initialPushPromptScheduled = false;
        return;
      }
      Map<String, dynamic>? webSubscription;
      final activate = await showDialog<bool>(
        context: promptContext,
        barrierDismissible: false,
        builder: (_) => InitialPushPromptDialog(
          onActivate: native
              ? null
              : () async {
                  webSubscription = await subscribeToWebPush(
                    webConfiguration!.vapidPublicKey!,
                  );
                },
        ),
      );
      if (native) {
        await nativePushService.markInitialPromptHandled();
      } else {
        markInitialWebPushPromptHandled();
      }
      if (!mounted || activate != true) return;
      if (native) {
        final token = await nativePushService.enable();
        if (!mounted) return;
        if (token != null) {
          ref.invalidate(nativePushRegistrationProvider);
          _showPushMessage('Pushnachrichten sind jetzt aktiviert.');
        } else {
          _showPushMessage(
            'Die Android-Benachrichtigungsfreigabe wurde nicht erteilt.',
          );
        }
        return;
      }
      try {
        final repository = ref.read(repositoryProvider);
        await repository.grantPushConsent();
        await repository.registerWebPushSubscription(webSubscription!);
        if (!mounted) return;
        _showPushMessage('Web-Pushnachrichten sind jetzt aktiviert.');
      } catch (_) {
        if (!mounted) return;
        _showPushMessage(
          'Web-Push konnte nicht aktiviert werden. Du kannst es später unter Nachrichten · Einstellungen erneut versuchen.',
        );
      }
    });
  }

  void _showPushMessage(String message) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  void _retryBootstrap(AppBootstrapSession session) {
    ref.invalidate(organizationProvider);
    ref.invalidate(playersProvider);
    ref.invalidate(eventsProvider);
    ref.invalidate(trainingsProvider);
    ref.invalidate(outdoorPitchOccupancyProvider);
    ref.invalidate(indoorPitchOccupancyProvider);
    ref.invalidate(pendingUsersProvider);
    ref.invalidate(membersProvider);
    ref.invalidate(sessionBootstrapProvider(session));
  }

  String _bootstrapErrorMessage(Object? error) {
    if (error is AppBootstrapException) {
      return 'Beim Laden von „${error.resource}“ ist die Verbindung abgebrochen.';
    }
    return 'Die Vereinsdaten konnten nicht vollständig geladen werden.';
  }

  Widget _withLaunchTransition(Widget child) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 900),
        reverseDuration: const Duration(milliseconds: 800),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (child, animation) {
          final softened = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: softened,
            child: ScaleTransition(
              scale: Tween<double>(begin: .992, end: 1).animate(softened),
              child: child,
            ),
          );
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.user?.id != next.user?.id) {
        _startupPromptsScheduled = false;
        _initialPushPromptScheduled = false;
        _parentConsentPromptScheduled = false;
        _parentConsentPromptShownUserId = null;
      }
      final sessionChanged = previous?.user?.id != next.user?.id ||
          previous?.user?.status != next.user?.status ||
          previous?.user?.role != next.user?.role;
      final router = _activeRouter;
      if (!sessionChanged || router == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(router, _activeRouter)) router.refresh();
      });
    });
    final approvedUser = authState.user?.status == AccountStatus.approved
        ? authState.user
        : null;
    final bootstrapSession = approvedUser == null
        ? null
        : (userId: approvedUser.id, role: approvedUser.role);
    final bootstrap = bootstrapSession == null
        ? null
        : ref.watch(sessionBootstrapProvider(bootstrapSession));
    final bootstrapLoading = bootstrap?.isLoading == true;
    final bootstrapError = bootstrap?.error;
    final authRestoreError =
        authState.user == null && authState.loading ? authState.error : null;
    if (!_minimumLaunchComplete ||
        (authState.loading && authState.user == null) ||
        bootstrapLoading ||
        bootstrapError != null) {
      return _withLaunchTransition(MaterialApp(
        key: const ValueKey('fc-teugn-launch'),
        title: AppIdentity.name,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: _germanLocale,
        supportedLocales: _supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        // Der Startbildschirm besitzt bereits seine eigene ruhige
        // Ladeanimation. Globale Speicher-/Ladeoverlays würden hier ein
        // zweites Vereinslogo darüberlegen.
        builder: buildLaunchScreenContent,
        home: AnimatedLaunchScreen(
          waitingForData: bootstrapLoading,
          statusMessage: bootstrapLoading
              ? 'Vereinsdaten werden geladen...'
              : authRestoreError != null || bootstrapError != null
                  ? 'Start konnte noch nicht abgeschlossen werden'
                  : 'App wird vorbereitet …',
          errorMessage: authRestoreError ??
              (bootstrapError == null
                  ? null
                  : _bootstrapErrorMessage(bootstrapError)),
          onRetry: authRestoreError != null
              ? () => ref.read(authProvider.notifier).retryStoredSession()
              : bootstrapSession == null || bootstrapError == null
                  ? null
                  : () => _retryBootstrap(bootstrapSession),
        ),
      ));
    }

    ref.watch(nativePushRegistrationProvider);

    // Keep one router for the complete signed-in app lifetime. Recreating it
    // after a provider refresh resets the navigation stack to its initial
    // location and causes the dashboard to visibly enter a second time.
    final router = _activeRouter ??= GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: _initialRouteFor(authState.user),
      redirect: (context, state) {
        final user = ref.read(authProvider).user;
        final location = state.matchedLocation;
        final loggedIn = user != null;
        final publicLocation = location == '/login' ||
            location == '/register' ||
            location == '/reset-password';

        if (!loggedIn && !publicLocation) {
          return '/login';
        }

        if (loggedIn && (location == '/login' || location == '/register')) {
          if (user.status != AccountStatus.approved) {
            return '/pending';
          }
          return user.isTrainer ? '/trainer' : '/parent';
        }

        if (loggedIn && user.status != AccountStatus.approved) {
          if (location != '/pending' && location != '/reset-password') {
            return '/pending';
          }
          return null;
        }

        if (loggedIn && user.status == AccountStatus.approved) {
          if (user.isTrainer && location.startsWith('/parent')) {
            return '/trainer';
          }
          if (!user.isTrainer && location.startsWith('/trainer')) {
            return '/parent';
          }
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterPage(),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (context, state) => ResetPasswordPage(
            token: state.uri.queryParameters['token'] ?? '',
            requestId: state.uri.queryParameters['requestId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/pending',
          builder: (context, state) => const PendingPage(),
        ),
        GoRoute(
          path: '/bfv-browser',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) {
            final teamName = state.uri.queryParameters['teamName'] ?? 'BfV';
            final target = buildEmbeddedBfvUri(
              widgetTeamId: state.uri.queryParameters['teamId'],
              teamName: teamName,
              teamUrl: state.uri.queryParameters['teamUrl'],
            );
            if (target == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Tabelle & Ergebnisse')),
                body: const Center(
                  child: Text('Für diese Mannschaft fehlt die BfV-Kennung.'),
                ),
              );
            }
            return BfvBrowserPage(initialUri: target, teamName: teamName);
          },
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Trainer & Verwaltung',
            destinations: const [
              ShellDestination(
                  label: 'Startseite',
                  mobileLabel: 'Start',
                  icon: Icons.grid_view_rounded,
                  route: '/trainer',
                  section: ShellSection.overview,
                  hint: 'Das Wichtigste auf einen Blick'),
              ShellDestination(
                  label: 'Mitglieder & Berechtigungen',
                  icon: Icons.manage_accounts_rounded,
                  route: '/trainer/approvals',
                  section: ShellSection.administration,
                  hint: 'Zugänge, Rollen und Freigaben',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Mein Konto',
                  icon: Icons.manage_accounts_outlined,
                  route: '/trainer/account',
                  section: ShellSection.administration,
                  hint: 'Persönliche Daten und Passwort ändern',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Team-Zentrale',
                  mobileLabel: 'Team',
                  icon: Icons.groups_rounded,
                  route: '/trainer/team',
                  section: ShellSection.team,
                  hint: 'Mannschaft zentral verwalten',
                  relatedRoutes: ['/trainer/players']),
              ShellDestination(
                  label: 'Spieler & Kader',
                  icon: Icons.badge_rounded,
                  route: '/trainer/players',
                  section: ShellSection.team,
                  hint: 'Profile, Nummern und Positionen',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Kalender',
                  icon: Icons.calendar_month_rounded,
                  route: '/trainer/events',
                  section: ShellSection.schedule,
                  hint: 'Termine, Serien und Rückmeldungen'),
              ShellDestination(
                  label: 'Spielbetrieb',
                  mobileLabel: 'Spiele',
                  icon: Icons.sports_soccer_rounded,
                  route: '/trainer/matches',
                  section: ShellSection.schedule,
                  hint: 'Spieltage, Kader und Liveticker'),
              ShellDestination(
                  label: 'Tabelle & Ergebnisse',
                  icon: Icons.emoji_events_rounded,
                  route: '/trainer/bfv',
                  section: ShellSection.schedule,
                  hint: 'Offizielle BfV-Ligaübersicht',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Training & Platzplanung',
                  icon: Icons.fitness_center_rounded,
                  route: '/trainer/training',
                  section: ShellSection.schedule,
                  hint: 'Einheiten, Übungen und Belegung',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Statistiken & Auswertungen',
                  icon: Icons.query_stats_rounded,
                  route: '/trainer/statistics',
                  section: ShellSection.schedule,
                  hint: 'Leistung und Saisonstatistik',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Nachrichten & Abstimmung',
                  icon: Icons.forum_rounded,
                  route: '/trainer/messages',
                  section: ShellSection.communication,
                  hint: 'Absprachen im Verein'),
              ShellDestination(
                  label: 'Aufgaben & Ausrüstung',
                  icon: Icons.assignment_turned_in_rounded,
                  route: '/trainer/operations',
                  section: ShellSection.communication,
                  hint: 'Aufgaben, Listen und Ausrüstung'),
              ShellDestination(
                  label: 'Mannschaften & Verein',
                  icon: Icons.account_tree_rounded,
                  route: '/trainer/organization',
                  section: ShellSection.administration,
                  hint: 'Mannschaften und Strukturen',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Datenschutz & Einwilligungen',
                  icon: Icons.shield_outlined,
                  route: '/trainer/privacy',
                  section: ShellSection.administration,
                  hint: 'Daten, Dokumente und Zustimmungen',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Hilfe-Center',
                  icon: Icons.help_center_rounded,
                  route: '/trainer/help',
                  section: ShellSection.support,
                  hint: 'Anleitungen und schnelle Antworten',
                  showOnMobile: false),
              ShellDestination(
                label: 'Meine Kinder & Rückmeldungen',
                icon: Icons.family_restroom_rounded,
                route: '/trainer/family',
                section: ShellSection.overview,
                hint: 'Zu- und Absagen für eigene Kinder',
              ),
              ShellDestination(
                label: 'Technischer Support',
                icon: Icons.support_agent_rounded,
                route: '/trainer/support',
                section: ShellSection.support,
                hint: 'Probleme melden und Antworten verfolgen',
              ),
            ],
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/trainer',
              builder: (context, state) => const TrainerDashboardPage(),
            ),
            GoRoute(
              path: '/trainer/approvals',
              builder: (context, state) => const TrainerApprovalsPage(),
            ),
            GoRoute(
              path: '/trainer/account',
              builder: (context, state) => const AccountSettingsPage(),
            ),
            GoRoute(
              path: '/trainer/team',
              builder: (context, state) => const TrainerTeamPage(),
            ),
            GoRoute(
              path: '/trainer/players',
              builder: (context, state) => const TrainerPlayersPage(),
            ),
            GoRoute(
              path: '/trainer/players/:playerId',
              builder: (context, state) => PlayerProfilePage(
                playerId: state.pathParameters['playerId']!,
                staffView: true,
                focusConsents: state.uri.queryParameters['consents'] == '1',
              ),
            ),
            GoRoute(
              path: '/trainer/events',
              builder: (context, state) => const TrainerEventsPage(),
            ),
            GoRoute(
              path: '/trainer/matches',
              builder: (context, state) => const TrainerMatchesPage(),
            ),
            GoRoute(
              path: '/trainer/bfv',
              builder: (context, state) =>
                  const BfvCompetitionPage(staffView: true),
            ),
            GoRoute(
              path: '/trainer/matches/:matchId',
              builder: (context, state) => MatchdayPage(
                matchId: state.pathParameters['matchId']!,
                staffView: true,
              ),
            ),
            GoRoute(
              path: '/trainer/training',
              builder: (context, state) => const TrainingsPage(),
            ),
            GoRoute(
              path: '/trainer/training/:trainingId',
              builder: (context, state) => TrainingPlannerPage(
                trainingId: state.pathParameters['trainingId']!,
              ),
            ),
            GoRoute(
              path: '/trainer/statistics',
              builder: (context, state) => const StatisticsPage(),
            ),
            GoRoute(
              path: '/trainer/messages',
              builder: (context, state) =>
                  const CommunicationsPage(staffView: true),
            ),
            GoRoute(
              path: '/trainer/operations',
              builder: (context, state) => const TeamOperationsPage(),
            ),
            GoRoute(
              path: '/trainer/organization',
              builder: (context, state) => const OrganizationPage(),
            ),
            GoRoute(
              path: '/trainer/privacy',
              builder: (context, state) => const PrivacyPage(),
            ),
            GoRoute(
              path: '/trainer/help',
              builder: (context, state) => HelpPage(
                staffView: true,
                initialQuery: state.uri.queryParameters['topic'],
              ),
            ),
            GoRoute(
              path: '/trainer/family',
              builder: (context, state) => FamilyResponsesPage(
                isTrainer: true,
                highlightedEventId: state.uri.queryParameters['eventId'],
                highlightedPlayerId: state.uri.queryParameters['playerId'],
              ),
            ),
            GoRoute(
              path: '/trainer/support',
              builder: (context, state) => SupportPage(
                initialTicketId: state.uri.queryParameters['ticketId'],
              ),
            ),
          ],
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Familie & Team',
            destinations: const [
              ShellDestination(
                  label: 'Startseite',
                  mobileLabel: 'Start',
                  icon: Icons.grid_view_rounded,
                  route: '/parent',
                  section: ShellSection.overview,
                  hint: 'Das Wichtigste auf einen Blick'),
              ShellDestination(
                  label: 'Kinder & Spielerprofile',
                  mobileLabel: 'Kinder',
                  icon: Icons.groups_rounded,
                  route: '/parent/players',
                  section: ShellSection.team,
                  hint: 'Profile und sportliche Entwicklung'),
              ShellDestination(
                  label: 'Termine & Kalender',
                  icon: Icons.calendar_month_rounded,
                  route: '/parent/events',
                  section: ShellSection.schedule,
                  hint: 'Training, Spiele und Vereinsleben'),
              ShellDestination(
                  label: 'Spiele & Liveticker',
                  mobileLabel: 'Spiele',
                  icon: Icons.sports_soccer_rounded,
                  route: '/parent/matches',
                  section: ShellSection.schedule,
                  hint: 'Kader, Ergebnisse und Liveticker'),
              ShellDestination(
                  label: 'Tabelle & Ergebnisse',
                  icon: Icons.emoji_events_rounded,
                  route: '/parent/bfv',
                  section: ShellSection.schedule,
                  hint: 'Offizielle BfV-Ligaübersicht',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Statistiken & Auswertungen',
                  icon: Icons.query_stats_rounded,
                  route: '/parent/statistics',
                  section: ShellSection.schedule,
                  hint: 'Leistung und Saisonstatistik',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Nachrichten & Abstimmung',
                  icon: Icons.forum_rounded,
                  route: '/parent/messages',
                  section: ShellSection.communication,
                  hint: 'Absprachen mit dem Team'),
              ShellDestination(
                  label: 'Aufgaben & Ausrüstung',
                  icon: Icons.assignment_turned_in_rounded,
                  route: '/parent/operations',
                  section: ShellSection.communication,
                  hint: 'Aufgaben, Listen und Ausrüstung'),
              ShellDestination(
                  label: 'Datenschutz & Einwilligungen',
                  icon: Icons.shield_outlined,
                  route: '/parent/privacy',
                  section: ShellSection.administration,
                  hint: 'Daten, Dokumente und Zustimmungen',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Mein Konto',
                  icon: Icons.manage_accounts_outlined,
                  route: '/parent/account',
                  section: ShellSection.administration,
                  hint: 'Persönliche Daten und Passwort ändern',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Hilfe-Center',
                  icon: Icons.help_center_rounded,
                  route: '/parent/help',
                  section: ShellSection.support,
                  hint: 'Anleitungen und schnelle Antworten',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Meine Kinder & Rückmeldungen',
                  icon: Icons.family_restroom_rounded,
                  route: '/parent/family',
                  section: ShellSection.overview,
                  hint: 'Alle Zu- und Absagen auf einen Blick'),
              ShellDestination(
                  label: 'Technischer Support',
                  icon: Icons.support_agent_rounded,
                  route: '/parent/support',
                  section: ShellSection.support,
                  hint: 'Probleme melden und Antworten verfolgen'),
            ],
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/parent',
              builder: (context, state) => const ParentDashboardPage(),
            ),
            GoRoute(
              path: '/parent/players',
              builder: (context, state) => const ParentPlayersPage(),
            ),
            GoRoute(
              path: '/parent/players/:playerId',
              builder: (context, state) => PlayerProfilePage(
                playerId: state.pathParameters['playerId']!,
                staffView: false,
                focusConsents: state.uri.queryParameters['consents'] == '1',
              ),
            ),
            GoRoute(
              path: '/parent/events',
              builder: (context, state) => const ParentEventsPage(),
            ),
            GoRoute(
              path: '/parent/matches',
              builder: (context, state) => const ParentMatchesPage(),
            ),
            GoRoute(
              path: '/parent/bfv',
              builder: (context, state) =>
                  const BfvCompetitionPage(staffView: false),
            ),
            GoRoute(
              path: '/parent/matches/:matchId',
              builder: (context, state) => MatchdayPage(
                matchId: state.pathParameters['matchId']!,
                staffView: false,
              ),
            ),
            GoRoute(
              path: '/parent/statistics',
              builder: (context, state) => const StatisticsPage(),
            ),
            GoRoute(
              path: '/parent/messages',
              builder: (context, state) =>
                  const CommunicationsPage(staffView: false),
            ),
            GoRoute(
              path: '/parent/operations',
              builder: (context, state) => const TeamOperationsPage(),
            ),
            GoRoute(
              path: '/parent/privacy',
              builder: (context, state) => const PrivacyPage(),
            ),
            GoRoute(
              path: '/parent/account',
              builder: (context, state) => const AccountSettingsPage(),
            ),
            GoRoute(
              path: '/parent/help',
              builder: (context, state) => HelpPage(
                staffView: false,
                initialQuery: state.uri.queryParameters['topic'],
              ),
            ),
            GoRoute(
              path: '/parent/family',
              builder: (context, state) => FamilyResponsesPage(
                isTrainer: false,
                highlightedEventId: state.uri.queryParameters['eventId'],
                highlightedPlayerId: state.uri.queryParameters['playerId'],
              ),
            ),
            GoRoute(
              path: '/parent/support',
              builder: (context, state) => SupportPage(
                initialTicketId: state.uri.queryParameters['ticketId'],
              ),
            ),
          ],
        ),
      ],
    );
    _openPendingPushAction();
    _scheduleStartupPrompts();

    return _withLaunchTransition(MaterialApp.router(
      key: const ValueKey('fc-teugn-app'),
      title: AppIdentity.name,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: buildAppTheme(),
      locale: _germanLocale,
      supportedLocales: _supportedLocales,
      localizationsDelegates: _localizationsDelegates,
      builder: _buildAppContent,
    ));
  }
}

String _initialRouteFor(AppUser? user) {
  if (user == null) return '/login';
  if (user.status != AccountStatus.approved) return '/pending';
  return user.isTrainer ? '/trainer' : '/parent';
}

String normalizePushActionRoute(
  String action, {
  required bool isTrainer,
}) {
  final parsed = Uri.tryParse(action.trim());
  final path = parsed?.path ?? '';
  if (path == '/reset-password' &&
      ((parsed?.queryParameters['token']?.isNotEmpty ?? false) ||
          (parsed?.queryParameters['requestId']?.isNotEmpty ?? false))) {
    return Uri(
      path: '/reset-password',
      queryParameters: {
        if (parsed!.queryParameters['token']?.isNotEmpty ?? false)
          'token': parsed.queryParameters['token']!,
        if (parsed.queryParameters['requestId']?.isNotEmpty ?? false)
          'requestId': parsed.queryParameters['requestId']!,
      },
    ).toString();
  }
  if (path == '/messages' || path.startsWith('/messages/')) {
    return isTrainer ? '/trainer/messages' : '/parent/messages';
  }
  if (path == '/trainer/messages' || path == '/parent/messages') {
    return isTrainer ? '/trainer/messages' : '/parent/messages';
  }
  if (path == '/events' || path.startsWith('/events/')) {
    return isTrainer ? '/trainer/events' : '/parent/events';
  }
  if (path == '/family' || path.startsWith('/family/')) {
    final base = isTrainer ? '/trainer/family' : '/parent/family';
    return parsed?.hasQuery == true ? '$base?${parsed!.query}' : base;
  }
  if (path == '/support' || path.startsWith('/support/')) {
    final base = isTrainer ? '/trainer/support' : '/parent/support';
    final ticketId = path.startsWith('/support/')
        ? path.substring('/support/'.length).split('/').first
        : '';
    return ticketId.isEmpty ? base : '$base?ticketId=$ticketId';
  }
  if (path == '/matches') {
    return isTrainer ? '/trainer/matches' : '/parent/matches';
  }
  if (path.startsWith('/matches/')) {
    final matchId = path.substring('/matches/'.length).split('/').first;
    if (matchId.isNotEmpty) {
      return isTrainer
          ? '/trainer/matches/$matchId'
          : '/parent/matches/$matchId';
    }
  }
  if (path.startsWith('/trainer/') && !isTrainer) return '/parent';
  if (path.startsWith('/parent/') && isTrainer) return '/trainer';
  if (path.startsWith('/')) return path;
  return isTrainer ? '/trainer' : '/parent';
}

const _germanLocale = Locale('de', 'DE');
const _supportedLocales = [_germanLocale];
const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _buildAppContent(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: AdaptiveHingePane(
        child: AppLoadingHost(child: child ?? const SizedBox.shrink()),
      ),
    );

@visibleForTesting
Widget buildLaunchScreenContent(BuildContext context, Widget? child) =>
    MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: AdaptiveHingePane(child: child ?? const SizedBox.shrink()),
    );
