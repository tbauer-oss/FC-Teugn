import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../auth/auth_controller.dart';
import '../../core/providers.dart';
import '../shared/pwa_install_prompt.dart';

enum ShellSection {
  overview('Start'),
  team('Mannschaft & Sport'),
  communication('Kommunikation & Organisation'),
  administration('Verwaltung & Konto');

  const ShellSection(this.label);

  final String label;
}

class ShellDestination {
  final String label;
  final String mobileLabel;
  final IconData icon;
  final String route;
  final ShellSection section;
  final String hint;
  final bool showOnMobile;

  const ShellDestination({
    required this.label,
    String? mobileLabel,
    required this.icon,
    required this.route,
    required this.section,
    required this.hint,
    this.showOnMobile = true,
  }) : mobileLabel = mobileLabel ?? label;
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
                  'Navigation',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Schnell zum richtigen Bereich.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
                const SizedBox(height: 14),
                if (shouldOfferPwaInstall) ...[
                  ListTile(
                    tileColor: AppColors.yellow.withValues(alpha: .2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: const Icon(Icons.install_mobile_rounded),
                    title: const Text('FC Teugn als App installieren'),
                    subtitle: const Text('Kostenlos auf dem Home-Bildschirm'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showPwaInstallPrompt(context);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                for (final section in ShellSection.values)
                  if (destinations.any((item) => item.section == section)) ...[
                    _MobileSectionHeader(label: section.label),
                    for (final destination in destinations
                        .where((item) => item.section == section))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          selected: location == destination.route ||
                              location.startsWith('${destination.route}/'),
                          selectedTileColor:
                              AppColors.yellow.withValues(alpha: .2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Icon(destination.icon),
                          title: Text(destination.label),
                          subtitle: Text(destination.hint),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            context.go(destination.route);
                          },
                        ),
                      ),
                  ],
              ],
            ),
          ),
        );
      },
    );
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
                DesktopSidebar(
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
                        label: destination.mobileLabel,
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

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
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
      width: 280,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A18), Color(0xFF0B0D0C)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _ClubBrand(light: true),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.yellow.withValues(alpha: .16),
                    Colors.white.withValues(alpha: .06),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.yellow.withValues(alpha: .22),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.yellow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: AppColors.black,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: TextStyle(
                            color: AppColors.yellow.withValues(alpha: .82),
                            fontSize: 9,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          contextLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final section in ShellSection.values)
                      if (destinations
                          .any((item) => item.section == section)) ...[
                        _DesktopSectionHeader(label: section.label),
                        for (var index = 0;
                            index < destinations.length;
                            index++)
                          if (destinations[index].section == section)
                            _DesktopNavigationItem(
                              destination: destinations[index],
                              selected: selectedIndex == index,
                              onTap: () => onSelect(index),
                            ),
                        const SizedBox(height: 6),
                      ],
                  ],
                ),
              ),
            ),
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

class _DesktopSectionHeader extends StatelessWidget {
  const _DesktopSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: .38),
          fontSize: 10,
          letterSpacing: 1.25,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DesktopNavigationItem extends StatelessWidget {
  const _DesktopNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? AppColors.yellow : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: .06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.black.withValues(alpha: .08)
                        : Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 18,
                    color: selected
                        ? AppColors.black
                        : Colors.white.withValues(alpha: .7),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.black
                          : Colors.white.withValues(alpha: .76),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: AppColors.black,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSectionHeader extends StatelessWidget {
  const _MobileSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 7),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
              letterSpacing: 1.05,
              fontWeight: FontWeight.w800,
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
