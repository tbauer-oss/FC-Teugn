import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'features/trainer/admin_perspective_page.dart';
import 'features/parent/parent_dashboard_page.dart';
import 'features/parent/parent_players_page.dart';
import 'features/parent/parent_events_page.dart';
import 'features/parent/parent_matches_page.dart';
import 'features/organization/organization_page.dart';
import 'features/players/player_profile_page.dart';
import 'features/matches/matchday_page.dart';
import 'features/matches/bfv_competition_page.dart';
import 'features/matches/bfv_browser_page.dart';
import 'features/integrations/spielplus_page.dart';
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
import 'core/app_theme_controller.dart';
import 'core/app_update/app_update_service.dart';
import 'core/providers.dart';
import 'core/loading/loading_widgets.dart';
import 'core/push/initial_push_prompt.dart';
import 'core/push/native_push_service.dart';
import 'core/push/push_client.dart';
import 'core/push/push_action_route.dart';
import 'core/runtime_environment.dart';

class FCTeugnApp extends ConsumerStatefulWidget {
  const FCTeugnApp({
    super.key,
    this.playMobileIntroVideo = false,
  });

  final bool playMobileIntroVideo;

  @override
  ConsumerState<FCTeugnApp> createState() => _FCTeugnAppState();
}

class _FCTeugnAppState extends ConsumerState<FCTeugnApp>
    with WidgetsBindingObserver {
  static const _nativeMinimumLaunchDuration = Duration(milliseconds: 2800);
  static const _webMinimumLaunchDuration = Duration(milliseconds: 120);
  Timer? _launchTimer;
  StreamSubscription<String>? _pushActionSubscription;
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  GoRouter? _activeRouter;
  late final String? _startupPasswordResetRoute;
  String? _pendingPushAction;
  bool _minimumLaunchComplete = false;
  bool _initialLaunchComplete = false;
  bool _launchCompletionScheduled = false;
  bool _initialPushPromptScheduled = false;
  bool _startupPromptsScheduled = false;
  bool _parentConsentPromptScheduled = false;
  String? _parentConsentPromptShownUserId;
  DateTime? _lastResumeRefresh;

  @override
  void initState() {
    super.initState();
    // The temporary launch MaterialApp owns the browser navigator before the
    // real GoRouter is created. Capture password-reset links immediately so
    // its token cannot be lost while the launch screen restores the session.
    _startupPasswordResetRoute =
        kIsWeb ? passwordResetRouteFromBrowserUri(Uri.base) : null;
    WidgetsBinding.instance.addObserver(this);
    // The first resumed lifecycle event belongs to the initial launch. Treat
    // it as current so it does not immediately duplicate the bootstrap calls.
    _lastResumeRefresh = DateTime.now();
    _pendingPushAction = nativePushService.takePendingAction();
    _pushActionSubscription = nativePushService.actions.listen((action) {
      _pendingPushAction = action;
      _openPendingPushAction();
    });
    if (!widget.playMobileIntroVideo) {
      _launchTimer = Timer(
        kIsWeb ? _webMinimumLaunchDuration : _nativeMinimumLaunchDuration,
        _completeLaunchIntro,
      );
    }
  }

  void _completeLaunchIntro() {
    if (mounted && !_minimumLaunchComplete) {
      setState(() => _minimumLaunchComplete = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _launchTimer?.cancel();
    unawaited(_pushActionSubscription?.cancel());
    _activeRouter?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final now = DateTime.now();
    final lastRefresh = _lastResumeRefresh;
    if (lastRefresh != null &&
        now.difference(lastRefresh) < const Duration(seconds: 30)) {
      return;
    }
    _lastResumeRefresh = now;
    ref.read(manualDataRefreshProvider.notifier).state++;
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
          ref.invalidate(currentDevicePushReadyProvider);
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
        ref.invalidate(currentDevicePushReadyProvider);
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
    ref.invalidate(calendarEventsProvider);
    ref.invalidate(matchEventsProvider);
    ref.invalidate(trainingsProvider);
    ref.invalidate(outdoorPitchOccupancyProvider);
    ref.invalidate(indoorPitchOccupancyProvider);
    ref.invalidate(pendingUsersProvider);
    ref.invalidate(membersProvider);
    ref.invalidate(parentDashboardSummaryProvider);
    ref.invalidate(trainerDashboardSummaryProvider);
    ref.invalidate(sessionBootstrapProvider(session));
  }

  String _bootstrapErrorMessage(Object? error) {
    if (error is AppBootstrapException) {
      return 'Beim Laden von „${error.resource}“ ist die Verbindung abgebrochen.';
    }
    return 'Die Vereinsdaten konnten nicht vollständig geladen werden.';
  }

  void _finishInitialLaunchAfterBuild() {
    if (_initialLaunchComplete || _launchCompletionScheduled) return;
    _launchCompletionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchCompletionScheduled = false;
      if (!mounted || _initialLaunchComplete) return;
      _launchTimer?.cancel();
      setState(() => _initialLaunchComplete = true);
    });
  }

  Widget _withLaunchTransition(Widget child) => AnimatedSwitcher(
        duration: kIsWeb
            ? const Duration(milliseconds: 240)
            : const Duration(milliseconds: 900),
        reverseDuration: kIsWeb
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 800),
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
    final themePreference = ref.watch(appThemePreferenceProvider);
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
    final initialAuthRestoreLoading =
        authState.loading && authState.user == null;
    final initialSessionReady = !initialAuthRestoreLoading &&
        (approvedUser == null || (!bootstrapLoading && bootstrapError == null));
    if (!_initialLaunchComplete &&
        _minimumLaunchComplete &&
        initialSessionReady) {
      _finishInitialLaunchAfterBuild();
    }
    if (!_initialLaunchComplete) {
      return _withLaunchTransition(MaterialApp(
        key: const ValueKey('fc-teugn-launch'),
        title: AppIdentity.name,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        themeMode: themePreference.themeMode,
        locale: _germanLocale,
        supportedLocales: _supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        // Der Startbildschirm besitzt bereits seine eigene ruhige
        // Ladeanimation. Globale Speicher-/Ladeoverlays würden hier ein
        // zweites Vereinslogo darüberlegen.
        builder: buildLaunchScreenContent,
        home: AnimatedLaunchScreen(
          playMobileIntroVideo: widget.playMobileIntroVideo,
          onIntroCompleted: _completeLaunchIntro,
          waitingForData: initialAuthRestoreLoading || bootstrapLoading,
          statusMessage: authRestoreError != null || bootstrapError != null
              ? 'Verbindung nicht möglich'
              : initialAuthRestoreLoading
                  ? 'Sitzung wird geprüft...'
                  : bootstrapLoading
                      ? 'Vereinsdaten werden geladen...'
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
          onContinueToLogin: authRestoreError != null
              ? () => ref
                  .read(authProvider.notifier)
                  .continueToLoginAfterRestoreFailure()
              : null,
        ),
      ));
    }

    ref.watch(nativePushRegistrationProvider);

    // Keep one router for the complete signed-in app lifetime. Recreating it
    // after a provider refresh resets the navigation stack to its initial
    // location and causes the dashboard to visibly enter a second time.
    final router = _activeRouter ??= GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: initialAppRouteForSession(
        authState.user,
        capturedPasswordResetRoute: _startupPasswordResetRoute,
      ),
      // When a reset link was captured before the launch screen, it must take
      // precedence over the platform route that the temporary navigator may
      // have written in the meantime.
      overridePlatformDefaultLocation: _startupPasswordResetRoute != null,
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
          if (!user.isTrainer && location == '/spielplus-browser') {
            return '/parent';
          }
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
        GoRoute(
          path: '/spielplus-browser',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) {
            final user = ref.read(authProvider).user;
            if (user == null || !user.isTrainer) {
              return const Scaffold(
                body: Center(
                  child: Text('SpielPLUS steht dem Trainerteam zur Verfügung.'),
                ),
              );
            }
            return SpielPlusBrowserPage(userId: user.id);
          },
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Trainer & Verwaltung',
            destinations: [
              const ShellDestination(
                  label: 'Startseite',
                  mobileLabel: 'Start',
                  icon: Icons.grid_view_rounded,
                  route: '/trainer',
                  section: ShellSection.overview,
                  hint: 'Das Wichtigste und offene Aufgaben auf einen Blick'),
              const ShellDestination(
                  label: 'Mitglieder, Rollen & Zugänge',
                  icon: Icons.manage_accounts_rounded,
                  route: '/trainer/approvals',
                  section: ShellSection.administration,
                  hint:
                      'Registrierungen prüfen, Konten freigeben und Rechte verwalten',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Mein Konto',
                  icon: Icons.manage_accounts_outlined,
                  route: '/trainer/account',
                  section: ShellSection.administration,
                  hint: 'Persönliche Daten, Sicherheit und Passwort verwalten',
                  showOnMobile: false),
              if (ref.watch(authProvider).user?.role == UserRole.superAdmin)
                const ShellDestination(
                  label: 'Ansicht als Mitglied',
                  icon: Icons.visibility_rounded,
                  route: '/trainer/view-as',
                  section: ShellSection.administration,
                  hint:
                      'Die App schreibgeschützt aus Sicht eines Mitglieds prüfen',
                  showOnMobile: false,
                ),
              const ShellDestination(
                  label: 'Meine Mannschaft',
                  mobileLabel: 'Team',
                  icon: Icons.groups_rounded,
                  route: '/trainer/team',
                  section: ShellSection.team,
                  hint:
                      'Mannschaft, Aufstellung und Teamdaten zentral verwalten',
                  relatedRoutes: ['/trainer/players']),
              const ShellDestination(
                  label: 'Spieler & Kader',
                  icon: Icons.badge_rounded,
                  route: '/trainer/players',
                  section: ShellSection.team,
                  hint:
                      'Spielerprofile, Rückennummern und Positionen verwalten',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Kalender & Termine',
                  mobileLabel: 'Kalender',
                  icon: Icons.calendar_month_rounded,
                  route: '/trainer/events',
                  section: ShellSection.schedule,
                  hint:
                      'Trainings, Spiele, Serien und Rückmeldungen verwalten'),
              const ShellDestination(
                  label: 'Spiele & Turniere',
                  mobileLabel: 'Spiele',
                  icon: Icons.sports_soccer_rounded,
                  route: '/trainer/matches',
                  section: ShellSection.schedule,
                  hint:
                      'Spieltage planen, Kader festlegen und Liveticker führen'),
              const ShellDestination(
                  label: 'Tabelle & Ergebnisse',
                  icon: Icons.emoji_events_rounded,
                  route: '/trainer/bfv',
                  section: ShellSection.schedule,
                  hint: 'Offizielle BfV-Tabelle, Spielplan und Ergebnisse',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'BfV SpielPLUS',
                  icon: Icons.login_rounded,
                  route: '/spielplus-browser',
                  section: ShellSection.schedule,
                  hint: 'Spielberichte und Verbandsverwaltung öffnen',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Trainings- & Platzplanung',
                  icon: Icons.fitness_center_rounded,
                  route: '/trainer/training',
                  section: ShellSection.schedule,
                  hint:
                      'Trainingseinheiten planen und Sportplätze koordinieren',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Leistungszentrum',
                  icon: Icons.query_stats_rounded,
                  route: '/trainer/statistics',
                  section: ShellSection.schedule,
                  hint:
                      'Entwicklung, Bewertungen und Saisonstatistiken auswerten',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Nachrichten & Umfragen',
                  icon: Icons.forum_rounded,
                  route: '/trainer/messages',
                  section: ShellSection.communication,
                  hint: 'Informationen versenden und Abstimmungen durchführen'),
              const ShellDestination(
                  label: 'Teamaufgaben & Ausrüstung',
                  icon: Icons.assignment_turned_in_rounded,
                  route: '/trainer/operations',
                  section: ShellSection.communication,
                  hint:
                      'Aufgaben verteilen, Material und Ausrüstung organisieren'),
              const ShellDestination(
                  label: 'Verein & Mannschaften',
                  icon: Icons.account_tree_rounded,
                  route: '/trainer/organization',
                  section: ShellSection.administration,
                  hint:
                      'Vereinsdaten, Mannschaften und Verantwortliche verwalten',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Datenschutz & Einwilligungen',
                  icon: Icons.shield_outlined,
                  route: '/trainer/privacy',
                  section: ShellSection.administration,
                  hint: 'Zustimmungen, Dokumente und Datenschutz verwalten',
                  showOnMobile: false),
              const ShellDestination(
                  label: 'Hilfe & Anleitungen',
                  icon: Icons.help_center_rounded,
                  route: '/trainer/help',
                  section: ShellSection.support,
                  hint:
                      'Funktionen verständlich erklärt und schnelle Antworten finden',
                  showOnMobile: false),
              const ShellDestination(
                label: 'Rückmeldungen für meine Kinder',
                icon: Icons.family_restroom_rounded,
                route: '/trainer/family',
                section: ShellSection.overview,
                hint: 'Für eigene Kinder zu Trainings und Spielen antworten',
              ),
              const ShellDestination(
                label: 'Technischer Support',
                icon: Icons.support_agent_rounded,
                route: '/trainer/support',
                section: ShellSection.support,
                hint: 'Probleme melden und Bearbeitungsstand verfolgen',
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
              path: '/trainer/view-as',
              builder: (context, state) => const AdminPerspectivePage(),
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
              builder: (context, state) => TrainerEventsPage(
                initialEventId: state.uri.queryParameters['eventId'],
              ),
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
                initialTab: state.uri.queryParameters['tab'],
                tournamentPlanning:
                    state.uri.queryParameters['planning'] == 'tournament',
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
              builder: (context, state) => CommunicationsPage(
                staffView: true,
                initialSection: state.uri.queryParameters['section'],
              ),
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
            audience: ShellAudience.family,
            destinations: const [
              ShellDestination(
                  label: 'Startseite',
                  mobileLabel: 'Start',
                  icon: Icons.grid_view_rounded,
                  route: '/parent',
                  section: ShellSection.overview,
                  hint: 'Familien-Assistent mit allem, was jetzt wichtig ist'),
              ShellDestination(
                  label: 'Meine Kinder & Spielerprofile',
                  mobileLabel: 'Kinder',
                  icon: Icons.groups_rounded,
                  route: '/parent/players',
                  section: ShellSection.team,
                  hint:
                      'Profile, Mannschaften und sportliche Entwicklung ansehen'),
              ShellDestination(
                  label: 'Kalender & Rückmeldungen',
                  mobileLabel: 'Kalender',
                  icon: Icons.calendar_month_rounded,
                  route: '/parent/events',
                  section: ShellSection.schedule,
                  hint:
                      'Trainings und Spiele sehen und direkt darauf antworten'),
              ShellDestination(
                  label: 'Spiele, Kader & Liveticker',
                  mobileLabel: 'Spiele',
                  icon: Icons.sports_soccer_rounded,
                  route: '/parent/matches',
                  section: ShellSection.schedule,
                  hint:
                      'Nominierungen, Aufstellungen, Ergebnisse und Liveticker'),
              ShellDestination(
                  label: 'Tabelle & Ergebnisse',
                  icon: Icons.emoji_events_rounded,
                  route: '/parent/bfv',
                  section: ShellSection.schedule,
                  hint: 'Offizielle BfV-Tabelle, Spielplan und Ergebnisse',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Entwicklung & Statistiken',
                  icon: Icons.query_stats_rounded,
                  route: '/parent/statistics',
                  section: ShellSection.schedule,
                  hint: 'Freigegebene Leistungsdaten und Entwicklungen ansehen',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Nachrichten & Umfragen',
                  icon: Icons.forum_rounded,
                  route: '/parent/messages',
                  section: ShellSection.communication,
                  hint:
                      'Mit dem Trainerteam kommunizieren und an Umfragen teilnehmen'),
              ShellDestination(
                  label: 'Teamaufgaben & Ausrüstung',
                  icon: Icons.assignment_turned_in_rounded,
                  route: '/parent/operations',
                  section: ShellSection.communication,
                  hint: 'Aufgaben übernehmen und die Mannschaft unterstützen'),
              ShellDestination(
                  label: 'Datenschutz & Einwilligungen',
                  icon: Icons.shield_outlined,
                  route: '/parent/privacy',
                  section: ShellSection.administration,
                  hint:
                      'Einwilligungen, Dokumente und persönliche Daten verwalten',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Mein Konto',
                  icon: Icons.manage_accounts_outlined,
                  route: '/parent/account',
                  section: ShellSection.administration,
                  hint: 'Persönliche Daten, Sicherheit und Passwort verwalten',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Hilfe & Anleitungen',
                  icon: Icons.help_center_rounded,
                  route: '/parent/help',
                  section: ShellSection.support,
                  hint: 'Die wichtigsten Funktionen einfach erklärt',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Rückmeldungen für meine Kinder',
                  icon: Icons.family_restroom_rounded,
                  route: '/parent/family',
                  section: ShellSection.overview,
                  hint: 'Alle Zu- und Absagen der eigenen Kinder verwalten'),
              ShellDestination(
                  label: 'Technischer Support',
                  icon: Icons.support_agent_rounded,
                  route: '/parent/support',
                  section: ShellSection.support,
                  hint: 'Technische Probleme melden und Antworten verfolgen'),
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
              builder: (context, state) => ParentEventsPage(
                initialEventId: state.uri.queryParameters['eventId'],
              ),
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
                initialTab: state.uri.queryParameters['tab'],
                tournamentPlanning:
                    state.uri.queryParameters['planning'] == 'tournament',
              ),
            ),
            GoRoute(
              path: '/parent/statistics',
              builder: (context, state) => const StatisticsPage(),
            ),
            GoRoute(
              path: '/parent/messages',
              builder: (context, state) => CommunicationsPage(
                staffView: false,
                initialSection: state.uri.queryParameters['section'],
              ),
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
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: themePreference.themeMode,
      locale: _germanLocale,
      supportedLocales: _supportedLocales,
      localizationsDelegates: _localizationsDelegates,
      builder: _buildAppContent,
    ));
  }
}

@visibleForTesting
String initialAppRouteForSession(
  AppUser? user, {
  String? capturedPasswordResetRoute,
}) {
  if (capturedPasswordResetRoute != null) {
    return capturedPasswordResetRoute;
  }
  if (kIsWeb) {
    final passwordResetRoute = passwordResetRouteFromBrowserUri(Uri.base);
    if (passwordResetRoute != null) return passwordResetRoute;
  }
  if (user == null) return '/login';
  if (user.status != AccountStatus.approved) return '/pending';
  return user.isTrainer ? '/trainer' : '/parent';
}

/// Converts both the new clean email URL and previously issued hash URLs into
/// the canonical in-app reset route. The clean path is rewritten in index.html
/// before Flutter starts; this fallback also keeps startup robust when a
/// browser restores the original URL from history.
@visibleForTesting
String? passwordResetRouteFromBrowserUri(Uri uri) {
  Uri? action;
  final normalizedPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (normalizedPath == '/reset-password') {
    action = uri;
  } else if (uri.fragment.isNotEmpty) {
    final fragment =
        uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}';
    final parsedFragment = Uri.tryParse(fragment);
    if (parsedFragment?.path == '/reset-password') action = parsedFragment;
  }
  if (action == null) return null;

  final token = action.queryParameters['token']?.trim() ?? '';
  final requestId = action.queryParameters['requestId']?.trim() ?? '';
  if (token.isEmpty && requestId.isEmpty) return null;
  return Uri(
    path: '/reset-password',
    queryParameters: {
      if (token.isNotEmpty) 'token': token,
      if (requestId.isNotEmpty) 'requestId': requestId,
    },
  ).toString();
}

String normalizePushActionRoute(
  String action, {
  required bool isTrainer,
}) =>
    roleCorrectPushActionRoute(action, isTrainer: isTrainer);

const _germanLocale = Locale('de', 'DE');
const _supportedLocales = [_germanLocale];
const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _buildAppContent(BuildContext context, Widget? child) {
  final appContent = AppLoadingHost(child: child ?? const SizedBox.shrink());
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    // Feature-Seiten erhalten die vollständige Fenstergeometrie inklusive
    // DisplayFeature. So können Master/Detail-Flächen beide Foldable-Panes
    // nutzen, ohne Inhalte unter dem Scharnier zu zeichnen.
    child: RuntimeEnvironment.isDemo
        ? Column(
            children: [
              const DemoEnvironmentStrip(),
              Expanded(child: appContent),
            ],
          )
        : appContent,
  );
}

@visibleForTesting
Widget buildLaunchScreenContent(BuildContext context, Widget? child) =>
    MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: AdaptiveHingePane(child: child ?? const SizedBox.shrink()),
    );
