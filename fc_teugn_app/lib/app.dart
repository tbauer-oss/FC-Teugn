import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/pending_page.dart';
import 'features/shell/app_shell.dart';
import 'features/trainer/trainer_dashboard_page.dart';
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
import 'features/statistics/statistics_page.dart';
import 'features/training/training_pages.dart';
import 'features/communications/communications_page.dart';
import 'features/operations/team_operations_page.dart';
import 'features/privacy/privacy_page.dart';
import 'features/launch/animated_launch_screen.dart';
import 'core/models/user.dart';
import 'core/app_identity.dart';
import 'core/app_theme.dart';

class FCTeugnApp extends ConsumerStatefulWidget {
  const FCTeugnApp({super.key});

  @override
  ConsumerState<FCTeugnApp> createState() => _FCTeugnAppState();
}

class _FCTeugnAppState extends ConsumerState<FCTeugnApp> {
  static const _minimumLaunchDuration = Duration(milliseconds: 2800);
  Timer? _launchTimer;
  bool _minimumLaunchComplete = false;

  @override
  void initState() {
    super.initState();
    _launchTimer = Timer(_minimumLaunchDuration, () {
      if (mounted) setState(() => _minimumLaunchComplete = true);
    });
  }

  @override
  void dispose() {
    _launchTimer?.cancel();
    super.dispose();
  }

  Widget _withLaunchTransition(Widget child) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (!_minimumLaunchComplete ||
        (authState.loading && authState.user == null)) {
      return _withLaunchTransition(MaterialApp(
        key: const ValueKey('fc-teugn-launch'),
        title: AppIdentity.name,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: _germanLocale,
        supportedLocales: _supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        builder: _forceGerman24HourClock,
        home: const AnimatedLaunchScreen(),
      ));
    }

    final router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final user = authState.user;
        final location = state.matchedLocation;
        final loggedIn = user != null;

        if (!loggedIn && location != '/login' && location != '/register') {
          return '/login';
        }

        if (loggedIn && (location == '/login' || location == '/register')) {
          if (user.status != AccountStatus.approved) {
            return '/pending';
          }
          return user.isTrainer ? '/trainer' : '/parent';
        }

        if (loggedIn && user.status != AccountStatus.approved) {
          if (location != '/pending') {
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
          path: '/pending',
          builder: (context, state) => const PendingPage(),
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
                  label: 'Spieler & Kader',
                  mobileLabel: 'Team',
                  icon: Icons.groups_rounded,
                  route: '/trainer/players',
                  section: ShellSection.team,
                  hint: 'Spielerprofile und Zuordnungen'),
              ShellDestination(
                  label: 'Kalender',
                  icon: Icons.calendar_month_rounded,
                  route: '/trainer/events',
                  section: ShellSection.team,
                  hint: 'Termine, Serien und Rückmeldungen'),
              ShellDestination(
                  label: 'Spielbetrieb',
                  mobileLabel: 'Spiele',
                  icon: Icons.sports_soccer_rounded,
                  route: '/trainer/matches',
                  section: ShellSection.team,
                  hint: 'Spieltage, Kader und Liveticker'),
              ShellDestination(
                  label: 'Training & Platzplanung',
                  icon: Icons.fitness_center_rounded,
                  route: '/trainer/training',
                  section: ShellSection.team,
                  hint: 'Einheiten, Übungen und Belegung',
                  showOnMobile: false),
              ShellDestination(
                  label: 'Statistiken & Auswertungen',
                  icon: Icons.query_stats_rounded,
                  route: '/trainer/statistics',
                  section: ShellSection.team,
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
              path: '/trainer/players',
              builder: (context, state) => const TrainerPlayersPage(),
            ),
            GoRoute(
              path: '/trainer/players/:playerId',
              builder: (context, state) => PlayerProfilePage(
                playerId: state.pathParameters['playerId']!,
                staffView: true,
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
                  section: ShellSection.team,
                  hint: 'Training, Spiele und Vereinsleben'),
              ShellDestination(
                  label: 'Spiele & Liveticker',
                  mobileLabel: 'Spiele',
                  icon: Icons.sports_soccer_rounded,
                  route: '/parent/matches',
                  section: ShellSection.team,
                  hint: 'Kader, Ergebnisse und Liveticker'),
              ShellDestination(
                  label: 'Statistiken & Auswertungen',
                  icon: Icons.query_stats_rounded,
                  route: '/parent/statistics',
                  section: ShellSection.team,
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
          ],
        ),
      ],
    );

    return _withLaunchTransition(MaterialApp.router(
      key: const ValueKey('fc-teugn-app'),
      title: AppIdentity.name,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildAppTheme(),
      locale: _germanLocale,
      supportedLocales: _supportedLocales,
      localizationsDelegates: _localizationsDelegates,
      builder: _forceGerman24HourClock,
    ));
  }
}

const _germanLocale = Locale('de', 'DE');
const _supportedLocales = [_germanLocale];
const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _forceGerman24HourClock(BuildContext context, Widget? child) =>
    MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    );
