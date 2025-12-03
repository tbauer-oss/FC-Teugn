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
      redirect: (context, state) {
        final loggedIn = authState.user != null;

        if (!loggedIn && state.subloc != '/login') {
          return '/login';
        }

        if (loggedIn && state.subloc == '/login') {
          return authState.user!.role == UserRole.coach
              ? '/coach'
              : '/parent';
        }

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
