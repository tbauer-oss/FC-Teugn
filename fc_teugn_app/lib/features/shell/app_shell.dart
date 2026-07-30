import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../auth/auth_controller.dart';
import '../../core/providers.dart';

class ShellDestination {
  final String label;
  final IconData icon;
  final String route;
  final bool showOnMobile;

  const ShellDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.showOnMobile = true,
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

  int? _matchingIndex(String location, List<ShellDestination> items) {
    for (var i = 0; i < items.length; i++) {
      if (location == items[i].route) {
        return i;
      }
    }
    for (var i = items.length - 1; i >= 0; i--) {
      if (location.startsWith('${items[i].route}/')) {
        return i;
      }
    }
    return null;
  }

  int _selectedIndex(String location, List<ShellDestination> items) {
    return _matchingIndex(location, items) ?? 0;
  }

  Future<void> _refreshApp(WidgetRef ref) async {
    ref.invalidate(repositoryProvider);
    ref.invalidate(organizationProvider);
    try {
      await ref.read(organizationProvider.future);
    } catch (_) {
      // Die aktuell sichtbare Seite zeigt ihren eigenen Ladefehler an.
    }
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    List<ShellDestination> destinations,
    String location,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              children: [
                Text(
                  'Weitere Bereiche',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Alle Funktionen, übersichtlich an einem Ort.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
                const SizedBox(height: 14),
                for (final destination in destinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      selected: location == destination.route ||
                          location.startsWith('${destination.route}/'),
                      selectedTileColor: AppColors.yellow.withValues(alpha: .2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(destination.icon),
                      title: Text(destination.label),
                      subtitle: Text(_destinationHint(destination.label)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.go(destination.route);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _destinationHint(String label) {
    return switch (label) {
      'Mitglieder' => 'Freigaben, Rollen und Berechtigungen',
      'Training' => 'Einheiten und Übungen vorbereiten',
      'Statistik' => 'Leistungen und Saisonwerte',
      'Nachrichten' => 'Im Team austauschen',
      'Orga' => 'Aufgaben und Material',
      'Verein' => 'Mannschaften und Verein verwalten',
      'Datenschutz' => 'Meine Daten und Einwilligungen',
      _ => 'Bereich öffnen',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final organization = ref.watch(organizationProvider).value;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _selectedIndex(location, destinations);
    final mobileCandidates =
        destinations.where((destination) => destination.showOnMobile).toList();
    final mobileDestinations = mobileCandidates.take(4).toList();
    final primaryRoutes =
        mobileDestinations.map((destination) => destination.route).toSet();
    final moreDestinations = destinations
        .where((destination) => !primaryRoutes.contains(destination.route))
        .toList();
    final primaryMobileIndex = _matchingIndex(location, mobileDestinations);
    final mobileSelectedIndex = primaryMobileIndex ?? mobileDestinations.length;
    final contextLabel = organization == null
        ? 'FC Teugn Jugend'
        : organization.currentTeam.displayName;
    final seasonLabel = organization?.season.name ?? '2026/27';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;

        return Scaffold(
          body: Row(
            children: [
              if (isWide)
                _DesktopNavigation(
                  title: title,
                  destinations: destinations,
                  selectedIndex: selectedIndex,
                  userName: authState.user?.name ?? '',
                  userRole: authState.user?.roleLabel ?? '',
                  contextLabel: contextLabel,
                  seasonLabel: seasonLabel,
                  onSelect: (index) => context.go(destinations[index].route),
                  onLogout: () => ref.read(authProvider.notifier).logout(),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (!isWide)
                      _MobileHeader(
                        title: title,
                        userName: authState.user?.name ?? '',
                        contextLabel: contextLabel,
                        onLogout: () =>
                            ref.read(authProvider.notifier).logout(),
                        onPrivacy: () {
                          ShellDestination? privacy;
                          for (final item in destinations) {
                            if (item.route.endsWith('/privacy')) {
                              privacy = item;
                              break;
                            }
                          }
                          if (privacy != null) context.go(privacy.route);
                        },
                      ),
                    Expanded(
                      child: RefreshIndicator.adaptive(
                        onRefresh: () => _refreshApp(ref),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  height: 72,
                  selectedIndex: mobileSelectedIndex,
                  onDestinationSelected: (index) {
                    if (index < mobileDestinations.length) {
                      context.go(mobileDestinations[index].route);
                      return;
                    }
                    _showMoreMenu(context, moreDestinations, location);
                  },
                  destinations: [
                    for (final destination in mobileDestinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon:
                            Icon(destination.icon, color: AppColors.blue),
                        label: destination.label,
                      ),
                    const NavigationDestination(
                      icon: Icon(Icons.more_horiz_rounded),
                      selectedIcon: Icon(
                        Icons.more_horiz_rounded,
                        color: AppColors.blue,
                      ),
                      label: 'Mehr',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.userName,
    required this.userRole,
    required this.contextLabel,
    required this.seasonLabel,
    required this.onSelect,
    required this.onLogout,
  });

  final String title;
  final List<ShellDestination> destinations;
  final int selectedIndex;
  final String userName;
  final String userRole;
  final String contextLabel;
  final String seasonLabel;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 262,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _ClubBrand(light: true),
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Saison $seasonLabel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .48),
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < destinations.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Material(
                  color: selectedIndex == index
                      ? AppColors.yellow
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => onSelect(index),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            destinations[index].icon,
                            size: 21,
                            color: selectedIndex == index
                                ? AppColors.black
                                : Colors.white.withValues(alpha: .62),
                          ),
                          const SizedBox(width: 13),
                          Text(
                            destinations[index].label,
                            style: TextStyle(
                              color: selectedIndex == index
                                  ? AppColors.black
                                  : Colors.white.withValues(alpha: .68),
                              fontWeight: selectedIndex == index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            const Divider(color: Color(0xFF3A3D3B)),
            const SizedBox(height: 8),
            Row(
              children: [
                _Avatar(name: userName),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        userRole,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .52),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Abmelden',
                  onPressed: onLogout,
                  color: Colors.white70,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.title,
    required this.userName,
    required this.contextLabel,
    required this.onLogout,
    required this.onPrivacy,
  });

  final String title;
  final String userName;
  final String contextLabel;
  final VoidCallback onLogout;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;
        return Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(narrow ? 12 : 18, 8, 6, 8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (narrow)
                  const ClubLogo(size: 38)
                else
                  const _ClubBrand(light: false, compact: true),
                SizedBox(width: narrow ? 10 : 14),
                Expanded(
                  child: Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _Avatar(name: userName, small: true),
                IconButton(
                  visualDensity: narrow ? VisualDensity.compact : null,
                  tooltip: 'Datenschutz & meine Daten',
                  onPressed: onPrivacy,
                  icon: const Icon(Icons.shield_outlined),
                ),
                IconButton(
                  visualDensity: narrow ? VisualDensity.compact : null,
                  tooltip: 'Abmelden',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClubBrand extends StatelessWidget {
  const _ClubBrand({required this.light, this.compact = false});

  final bool light;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : AppColors.navy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClubLogo(size: compact ? 40 : 48),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FC TEUGN',
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
            ),
            Text(
              'JUGENDFUSSBALL',
              style: TextStyle(
                color: foreground.withValues(alpha: .56),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.small = false});

  final String name;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: small ? 17 : 19,
      backgroundColor: AppColors.teal,
      child: Text(
        initials.isEmpty ? 'FC' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
