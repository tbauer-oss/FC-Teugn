import 'package:flutter/material.dart';
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
import 'core/models/user.dart';
import 'core/app_theme.dart';

class FCTeugnApp extends ConsumerWidget {
  const FCTeugnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

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
            title: 'Trainer Bereich',
            destinations: const [
              ShellDestination(label: 'Übersicht', icon: Icons.grid_view_rounded, route: '/trainer'),
              ShellDestination(label: 'Freigaben', icon: Icons.check_circle, route: '/trainer/approvals', showOnMobile: false),
              ShellDestination(label: 'Team', icon: Icons.groups_rounded, route: '/trainer/players'),
              ShellDestination(label: 'Termine', icon: Icons.calendar_month_rounded, route: '/trainer/events'),
              ShellDestination(label: 'Spiele', icon: Icons.sports_soccer_rounded, route: '/trainer/matches'),
              ShellDestination(label: 'Training', icon: Icons.fitness_center_rounded, route: '/trainer/training', showOnMobile: false),
              ShellDestination(label: 'Statistik', icon: Icons.query_stats_rounded, route: '/trainer/statistics', showOnMobile: false),
              ShellDestination(label: 'Nachrichten', icon: Icons.forum_rounded, route: '/trainer/messages'),
              ShellDestination(label: 'Verein', icon: Icons.account_tree_rounded, route: '/trainer/organization', showOnMobile: false),
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
              path: '/trainer/organization',
              builder: (context, state) => const OrganizationPage(),
            ),
          ],
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Eltern Bereich',
            destinations: const [
              ShellDestination(label: 'Übersicht', icon: Icons.grid_view_rounded, route: '/parent'),
              ShellDestination(label: 'Kinder', icon: Icons.groups_rounded, route: '/parent/players'),
              ShellDestination(label: 'Termine', icon: Icons.calendar_month_rounded, route: '/parent/events'),
              ShellDestination(label: 'Spiele', icon: Icons.sports_soccer_rounded, route: '/parent/matches'),
              ShellDestination(label: 'Statistik', icon: Icons.query_stats_rounded, route: '/parent/statistics', showOnMobile: false),
              ShellDestination(label: 'Nachrichten', icon: Icons.forum_rounded, route: '/parent/messages'),
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
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: 'FC Teugn Jugend',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildAppTheme(),
    );
  }
}
