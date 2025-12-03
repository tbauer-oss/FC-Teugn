import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/login_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/parent/parent_shell.dart';
import 'features/coach/coach_shell.dart';
import 'core/models/user.dart';

class FCTeugnApp extends ConsumerWidget {
  const FCTeugnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: '/login',
      // ACHTUNG: hier kein subloc mehr, sondern matchedLocation
      redirect: (context, state) {
        final loggedIn = authState.user != null;
        final location = state.matchedLocation; // z.B. "/login", "/parent", "/coach"

        // Nicht eingeloggt → alles außer /login wird auf /login umgebogen
        if (!loggedIn && location != '/login') {
          return '/login';
        }

        // Eingeloggt → von /login direkt in den passenden Bereich
        if (loggedIn && location == '/login') {
          return authState.user!.role == UserRole.coach
              ? '/coach'
              : '/parent';
        }

        // Sonst nichts ändern
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/parent',
          builder: (context, state) => const ParentShell(),
        ),
        GoRoute(
          path: '/coach',
          builder: (context, state) => const CoachShell(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'FC Teugn Jugend',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
    );
  }
}
