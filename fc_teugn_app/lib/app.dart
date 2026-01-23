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
import 'core/models/user.dart';

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
              ShellDestination(label: 'Dashboard', icon: Icons.dashboard, route: '/trainer'),
              ShellDestination(label: 'Freigaben', icon: Icons.check_circle, route: '/trainer/approvals'),
              ShellDestination(label: 'Players', icon: Icons.groups, route: '/trainer/players'),
              ShellDestination(label: 'Events', icon: Icons.event, route: '/trainer/events'),
              ShellDestination(label: 'Matches', icon: Icons.sports_soccer, route: '/trainer/matches'),
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
              path: '/trainer/events',
              builder: (context, state) => const TrainerEventsPage(),
            ),
            GoRoute(
              path: '/trainer/matches',
              builder: (context, state) => const TrainerMatchesPage(),
            ),
          ],
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(
            title: 'Eltern Bereich',
            destinations: const [
              ShellDestination(label: 'Dashboard', icon: Icons.dashboard, route: '/parent'),
              ShellDestination(label: 'Players', icon: Icons.groups, route: '/parent/players'),
              ShellDestination(label: 'Events', icon: Icons.event, route: '/parent/events'),
              ShellDestination(label: 'Matches', icon: Icons.sports_soccer, route: '/parent/matches'),
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
              path: '/parent/events',
              builder: (context, state) => const ParentEventsPage(),
            ),
            GoRoute(
              path: '/parent/matches',
              builder: (context, state) => const ParentMatchesPage(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: 'DFS Connect+ Training Hub',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
    );
  }
}
