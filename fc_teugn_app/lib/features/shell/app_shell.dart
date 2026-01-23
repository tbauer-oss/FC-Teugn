import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_controller.dart';

class ShellDestination {
  final String label;
  final IconData icon;
  final String route;

  const ShellDestination({
    required this.label,
    required this.icon,
    required this.route,
  });
}

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.destinations,
    required this.child,
    required this.title,
  });

  final List<ShellDestination> destinations;
  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = destinations.indexWhere((d) => location.startsWith(d.route));
    final selectedIndex = currentIndex >= 0 ? currentIndex : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final navigationRail = NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => context.go(destinations[index].route),
          labelType: NavigationRailLabelType.all,
          destinations: [
            for (final destination in destinations)
              NavigationRailDestination(
                icon: Icon(destination.icon),
                label: Text(destination.label),
              ),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (authState.user != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Text(
                      authState.user!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Abmelden',
                onPressed: () => ref.read(authProvider.notifier).logout(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Row(
            children: [
              if (isWide) navigationRail,
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => context.go(destinations[index].route),
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
