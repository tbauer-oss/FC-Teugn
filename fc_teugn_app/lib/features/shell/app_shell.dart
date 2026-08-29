import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_identity.dart';
import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/models/organization.dart';
import '../shared/pwa_install_prompt.dart';
import '../shared/app_about_sheet.dart';

void _noOp() {}
Future<void> _noOpAsync() async {}

enum ShellAudience { staff, family }

enum ShellSection {
  overview(
    'Übersicht',
    'Das Wichtigste und offene Aufgaben',
    Icons.home_rounded,
    'Übersicht',
    'Dein Familien-Assistent',
  ),
  team(
    'Meine Mannschaft',
    'Spieler, Kader, Stammformation und Teamdaten',
    Icons.groups_rounded,
    'Kinder & Mannschaft',
    'Kinder, Spielerprofile und Mannschaft',
  ),
  schedule(
    'Training & Spielbetrieb',
    'Kalender, Training, Spiele und Auswertungen',
    Icons.sports_soccer_rounded,
    'Termine & Spielbetrieb',
    'Kalender, Rückmeldungen, Spiele und Ergebnisse',
  ),
  communication(
    'Teamorganisation & Kommunikation',
    'Absprachen, Aufgaben und Ausrüstung',
    Icons.forum_rounded,
    'Kommunikation & Mithelfen',
    'Nachrichten, Umfragen und Teamaufgaben',
  ),
  administration(
    'Verein & Verwaltung',
    'Mitglieder, Strukturen und Einwilligungen',
    Icons.admin_panel_settings_rounded,
    'Konto & Datenschutz',
    'Persönliche Daten, Sicherheit und Einwilligungen',
  ),
  support(
    'Hilfe & Support',
    'Anleitungen, Antworten und Problemlösung',
    Icons.help_center_rounded,
    'Hilfe & Support',
    'Anleitungen, Antworten und Problemlösung',
  );

  const ShellSection(
    this.label,
    this.description,
    this.icon,
    this.familyLabel,
    this.familyDescription,
  );

  final String label;
  final String description;
  final IconData icon;
  final String familyLabel;
  final String familyDescription;

  String labelFor(ShellAudience audience) =>
      audience == ShellAudience.family ? familyLabel : label;

  String descriptionFor(ShellAudience audience) =>
      audience == ShellAudience.family ? familyDescription : description;
}

class ShellDestination {
  final String label;
  final String mobileLabel;
  final IconData icon;
  final String route;
  final ShellSection section;
  final String hint;
  final bool showOnMobile;
  final List<String> relatedRoutes;

  const ShellDestination({
    required this.label,
    String? mobileLabel,
    required this.icon,
    required this.route,
    required this.section,
    required this.hint,
    this.showOnMobile = true,
    this.relatedRoutes = const [],
  }) : mobileLabel = mobileLabel ?? label;

  bool matches(String location) {
    final routes = [route, ...relatedRoutes];
    return routes.any(
      (item) => location == item || location.startsWith('$item/'),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.destinations,
    required this.child,
    required this.title,
    this.audience = ShellAudience.staff,
  });

  final List<ShellDestination> destinations;
  final Widget child;
  final String title;
  final ShellAudience audience;

  int? _matchingIndex(String location, List<ShellDestination> items) {
    for (var i = 0; i < items.length; i++) {
      if (location == items[i].route) {
        return i;
      }
    }
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].matches(location)) {
        return i;
      }
    }
    return null;
  }

  Future<void> _refreshApp(WidgetRef ref) async {
    ref.read(manualDataRefreshProvider.notifier).state++;
    // Active providers reload themselves through the generation signal. A
    // short minimum duration keeps the compact progress ring understandable
    // without blocking on unrelated APIs.
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }

  void _navigateContextBack(
    BuildContext context,
    ShellDestination destination,
  ) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(destination.route);
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    List<ShellDestination> destinations,
    String location,
    String contextLabel,
    String seasonLabel,
    String userName,
    String userRole,
  ) async {
    final destination = await showModalBottomSheet<ShellDestination>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.appColors.canvas,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: MobileNavigationPanel(
          destinations: destinations,
          audience: audience,
          location: location,
          contextLabel: contextLabel,
          seasonLabel: seasonLabel,
          userName: userName,
          userRole: userRole,
          offerInstall: shouldOfferPwaInstall,
          onInstall: () {
            Navigator.of(sheetContext).pop();
            showPwaInstallPrompt(context);
          },
          onAbout: () {
            Navigator.of(sheetContext).pop();
            showAppAboutSheet(context);
          },
          onHome: () => Navigator.of(sheetContext).pop(destinations.first),
          onSelect: (destination) =>
              Navigator.of(sheetContext).pop(destination),
        ),
      ),
    );

    // Erst navigieren, wenn das Bottom Sheet vollständig geschlossen wurde.
    // Gleichzeitiges Schließen und Wechseln der GoRouter-Route konnte auf
    // Mobilgeräten die neue Seite direkt wieder durch die alte ersetzen.
    if (destination == null || !context.mounted) return;
    context.go(destination.route);
  }

  Future<void> _showWorkingContextSwitcher(
    BuildContext context,
    WidgetRef ref,
    OrganizationContext organization,
  ) async {
    var ageGroupId = organization.workingContext.ageGroupId;
    var includeAll = organization.workingContext.includeAllTeams;
    String? teamId = organization.workingContext.teamIds.isEmpty
        ? organization.currentTeam.id
        : organization.workingContext.teamIds.first;

    final selection = await showDialog<
        ({
          String ageGroupId,
          String? teamId,
          bool includeAll,
        })>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ageGroups = organization.ageGroups
              .where((ageGroup) => organization.teams
                  .any((team) => team.ageGroup.id == ageGroup.id))
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          if (!ageGroups.any((item) => item.id == ageGroupId) &&
              ageGroups.isNotEmpty) {
            ageGroupId = ageGroups.first.id;
          }
          final teams = organization.teams
              .where((team) => team.ageGroup.id == ageGroupId && team.isActive)
              .toList()
            ..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
          if (!teams.any((item) => item.id == teamId) && teams.isNotEmpty) {
            teamId = teams.first.id;
          }

          return AlertDialog(
            title: const Text('Arbeitsbereich wechseln'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Alle Inhalte und Aktionen werden auf die gewählte Jugend und Mannschaft begrenzt.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: ageGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Jugend',
                      prefixIcon: Icon(Icons.category_rounded),
                    ),
                    items: [
                      for (final ageGroup in ageGroups)
                        DropdownMenuItem(
                          value: ageGroup.id,
                          child: Text(ageGroup.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        ageGroupId = value;
                        final candidates = organization.teams.where(
                          (team) => team.ageGroup.id == value && team.isActive,
                        );
                        teamId =
                            candidates.isEmpty ? null : candidates.first.id;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (teams.length > 1)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Alle Mannschaften dieser Jugend'),
                      subtitle: Text(
                        '${teams.length} Mannschaften gemeinsam verwalten',
                      ),
                      value: includeAll,
                      onChanged: (value) =>
                          setDialogState(() => includeAll = value),
                    ),
                  if (!includeAll)
                    DropdownButtonFormField<String>(
                      initialValue: teamId,
                      decoration: const InputDecoration(
                        labelText: 'Mannschaft',
                        prefixIcon: Icon(Icons.groups_rounded),
                      ),
                      items: [
                        for (final team in teams)
                          DropdownMenuItem(
                            value: team.id,
                            child: Text(team.displayName),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => teamId = value),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed: teams.isEmpty || (!includeAll && teamId == null)
                    ? null
                    : () => Navigator.pop(
                          context,
                          (
                            ageGroupId: ageGroupId,
                            teamId: includeAll ? null : teamId,
                            includeAll: includeAll,
                          ),
                        ),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Wechseln'),
              ),
            ],
          );
        },
      ),
    );
    if (selection == null || !context.mounted) return;
    final ok = await ref.read(workingContextControllerProvider.notifier).select(
          ageGroupId: selection.ageGroupId,
          teamId: selection.teamId,
          includeAllTeams: selection.includeAll,
        );
    if (!context.mounted || ok) return;
    final error = ref.read(workingContextControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(error ?? 'Arbeitsbereich konnte nicht gewechselt werden.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final organization = ref.watch(organizationProvider).valueOrNull;
    final queuedWrites = ref.watch(offlineOutboxCountProvider).valueOrNull ?? 0;
    final location = GoRouterState.of(context).uri.path;
    final matchedIndex = _matchingIndex(location, destinations);
    final selectedIndex = matchedIndex ?? 0;
    final selectedDestination = destinations[selectedIndex];
    final showContextBack = matchedIndex != null &&
        location != selectedDestination.route &&
        selectedDestination.matches(location);
    final mobileCandidates =
        destinations.where((destination) => destination.showOnMobile).toList();
    final mobileDestinations = mobileCandidates.take(4).toList();
    final primaryMobileIndex = _matchingIndex(location, mobileDestinations);
    final mobileSelectedIndex = primaryMobileIndex ?? mobileDestinations.length;
    final contextLabel = organization == null
        ? AppIdentity.name
        : organization.workingContext.includeAllTeams
            ? '${organization.ageGroups.where((item) => item.id == organization.workingContext.ageGroupId).firstOrNull?.name ?? organization.currentTeam.ageGroup.name} · Alle Mannschaften'
            : organization.currentTeam.displayName;
    final seasonLabel = organization?.season.name ?? '2026/27';
    final helpDestination = destinations
        .where((destination) => destination.route.endsWith('/help'))
        .firstOrNull;
    final accountRoute = authState.user?.isTrainer == true
        ? '/trainer/account'
        : '/parent/account';
    final homeRoute = destinations.first.route;

    // Feature surfaces receive the complete live window and its display
    // features. They can therefore use both halves of an unfolded device
    // instead of being constrained to only one hinge pane.
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
                  audience: audience,
                  selectedIndex: selectedIndex,
                  userName: authState.user?.name ?? '',
                  userRole: authState.user?.roleLabel ?? '',
                  contextLabel: contextLabel,
                  seasonLabel: seasonLabel,
                  onContextTap: organization == null
                      ? _noOp
                      : () => _showWorkingContextSwitcher(
                            context,
                            ref,
                            organization,
                          ),
                  onHome: () => context.go(homeRoute),
                  onSelect: (index) => context.go(destinations[index].route),
                  onAccount: () => context.go(accountRoute),
                  onLogout: () => ref.read(authProvider.notifier).logout(),
                  onHelp: helpDestination == null
                      ? _noOp
                      : () => context.go(helpDestination.route),
                  onAbout: () => showAppAboutSheet(context),
                  onRefresh: () => _refreshApp(ref),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (!isWide)
                      _MobileHeader(
                        title: title,
                        userName: authState.user?.name ?? '',
                        contextLabel: contextLabel,
                        onContextTap: organization == null
                            ? _noOp
                            : () => _showWorkingContextSwitcher(
                                  context,
                                  ref,
                                  organization,
                                ),
                        onHome: () => context.go(homeRoute),
                        onLogout: () =>
                            ref.read(authProvider.notifier).logout(),
                        onAccount: () => context.go(accountRoute),
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
                        onHelp: helpDestination == null
                            ? _noOp
                            : () => context.go(helpDestination.route),
                        onAbout: () => showAppAboutSheet(context),
                        onRefresh: () => _refreshApp(ref),
                      ),
                    if (authState.user?.isReadOnlyPreview == true)
                      _ReadOnlyPreviewBanner(
                        name: authState.user!.name,
                        onExit: () async {
                          try {
                            await ref
                                .read(authProvider.notifier)
                                .exitReadOnlyPreview();
                            if (context.mounted) {
                              context.go('/trainer/view-as');
                            }
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(error
                                    .toString()
                                    .replaceFirst('Exception: ', '')),
                              ),
                            );
                          }
                        },
                      ),
                    if (showContextBack)
                      _ContextBackBar(
                        destination: selectedDestination,
                        compact: !isWide,
                        onPressed: () => _navigateContextBack(
                          context,
                          selectedDestination,
                        ),
                      ),
                    if (queuedWrites > 0)
                      Material(
                        color: AppColors.yellowSoft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_upload_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$queuedWrites Änderung${queuedWrites == 1 ? ' wartet' : 'en warten'} auf die Übertragung – die App versucht es automatisch erneut.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
              : Container(
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    border: Border(
                      top: BorderSide(color: context.appColors.outline),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withValues(alpha: .05),
                        blurRadius: 18,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: NavigationBar(
                    height: 72,
                    backgroundColor: context.appColors.surface,
                    surfaceTintColor: Colors.transparent,
                    indicatorColor:
                        Theme.of(context).navigationBarTheme.indicatorColor,
                    selectedIndex: mobileSelectedIndex,
                    onDestinationSelected: (index) {
                      if (index < mobileDestinations.length) {
                        context.go(mobileDestinations[index].route);
                        return;
                      }
                      _showMoreMenu(
                        context,
                        destinations,
                        location,
                        contextLabel,
                        seasonLabel,
                        authState.user?.name ?? '',
                        authState.user?.roleLabel ?? '',
                      );
                    },
                    destinations: [
                      for (final destination in mobileDestinations)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(
                            destination.icon,
                            color: context.appColors.text,
                          ),
                          label: destination.mobileLabel,
                        ),
                      NavigationDestination(
                        icon: const Icon(Icons.apps_rounded),
                        selectedIcon: Icon(
                          Icons.apps_rounded,
                          color: context.appColors.text,
                        ),
                        label: 'Mehr',
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _ReadOnlyPreviewBanner extends StatelessWidget {
  const _ReadOnlyPreviewBanner({required this.name, required this.onExit});

  final String name;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.yellowSoft,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                const Icon(Icons.visibility_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ansicht als $name · nur lesen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onExit,
                  child: const Text('Adminansicht'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ContextBackBar extends StatelessWidget {
  const _ContextBackBar({
    required this.destination,
    required this.compact,
    required this.onPressed,
  });

  final ShellDestination destination;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.canvas.withValues(alpha: .96),
        border: Border(
          bottom: BorderSide(color: context.appColors.outline),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1244),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 22,
              vertical: 3,
            ),
            child: TextButton.icon(
              key: const ValueKey('context-back-button'),
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: context.appColors.textMuted,
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 7,
                ),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(
                'Zurück zu „${destination.label}“',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.title,
    required this.destinations,
    this.audience = ShellAudience.staff,
    required this.selectedIndex,
    required this.userName,
    required this.userRole,
    required this.contextLabel,
    required this.seasonLabel,
    this.onContextTap = _noOp,
    this.onHome = _noOp,
    required this.onSelect,
    this.onAccount = _noOp,
    required this.onLogout,
    this.onHelp = _noOp,
    this.onAbout = _noOp,
    this.onRefresh = _noOpAsync,
  });

  final String title;
  final List<ShellDestination> destinations;
  final ShellAudience audience;
  final int selectedIndex;
  final String userName;
  final String userRole;
  final String contextLabel;
  final String seasonLabel;
  final VoidCallback onContextTap;
  final VoidCallback onHome;
  final ValueChanged<int> onSelect;
  final VoidCallback onAccount;
  final VoidCallback onLogout;
  final VoidCallback onHelp;
  final VoidCallback onAbout;
  final Future<void> Function() onRefresh;

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _ClubBrand(light: true, onTap: onHome),
                  ),
                  _RefreshIconButton(
                    onRefresh: onRefresh,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onContextTap,
                borderRadius: BorderRadius.circular(18),
                child: Container(
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
                      const Icon(
                        Icons.unfold_more_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ],
                  ),
                ),
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
                        _DesktopSectionHeader(
                          section: section,
                          audience: audience,
                        ),
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
                Expanded(
                  child: Tooltip(
                    message: 'Mein Konto',
                    child: InkWell(
                      onTap: onAccount,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: .52),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hilfe & Anleitungen',
                  onPressed: onHelp,
                  color: Colors.white70,
                  icon: const Icon(Icons.help_outline_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Über ${AppIdentity.name}',
                  onPressed: onAbout,
                  color: Colors.white70,
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
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
  const _DesktopSectionHeader({
    required this.section,
    required this.audience,
  });

  final ShellSection section;
  final ShellAudience audience;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('desktop-menu-section-header-${section.name}'),
      margin: const EdgeInsets.fromLTRB(2, 8, 2, 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: AppColors.yellow.withValues(alpha: .12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              section.icon,
              size: 14,
              color: AppColors.yellow.withValues(alpha: .88),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              section.labelFor(audience).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.yellow.withValues(alpha: .82),
                fontSize: 9.5,
                letterSpacing: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSectionHeading extends StatelessWidget {
  const _MobileSectionHeading({
    required this.section,
    required this.audience,
  });

  final ShellSection section;
  final ShellAudience audience;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('mobile-menu-section-header-${section.name}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A18), Color(0xFF393500)],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.yellow.withValues(alpha: .2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(section.icon, size: 18, color: AppColors.black),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BEREICH',
                  style: TextStyle(
                    color: AppColors.yellow.withValues(alpha: .82),
                    fontSize: 8,
                    letterSpacing: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  section.labelFor(audience),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  section.descriptionFor(audience),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .66),
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                    maxLines: 2,
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

class MobileNavigationPanel extends StatelessWidget {
  const MobileNavigationPanel({
    super.key,
    required this.destinations,
    this.audience = ShellAudience.staff,
    required this.location,
    required this.contextLabel,
    required this.seasonLabel,
    required this.userName,
    required this.userRole,
    required this.onSelect,
    this.offerInstall = false,
    this.onInstall,
    this.onHome = _noOp,
    this.onAbout = _noOp,
  });

  final List<ShellDestination> destinations;
  final ShellAudience audience;
  final String location;
  final String contextLabel;
  final String seasonLabel;
  final String userName;
  final String userRole;
  final ValueChanged<ShellDestination> onSelect;
  final bool offerInstall;
  final VoidCallback? onInstall;
  final VoidCallback onHome;
  final VoidCallback onAbout;

  ShellDestination? _selectedDestination() {
    for (final destination in destinations) {
      if (location == destination.route) return destination;
    }
    for (final destination in destinations.reversed) {
      if (destination.matches(location)) return destination;
    }
    return null;
  }

  Future<void> _showSearch(BuildContext context) async {
    final destination = await showDialog<ShellDestination>(
      context: context,
      builder: (context) => _MobileMenuSearchDialog(
        destinations: destinations,
        audience: audience,
      ),
    );
    if (destination != null) onSelect(destination);
  }

  @override
  Widget build(BuildContext context) {
    final selectedDestination = _selectedDestination();
    return SafeArea(
      top: false,
      child: ListView(
        // ignore: deprecated_member_use
        cacheExtent: 1800,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 18),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF171A18), Color(0xFF383400)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Tooltip(
                  message: 'Zur Startseite',
                  child: InkWell(
                    key: const ValueKey('mobile-menu-home-logo'),
                    onTap: onHome,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const ClubLogo(size: 35),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FC TEUGN TALENTS · APP-MENÜ',
                        style: TextStyle(
                          color: AppColors.yellow.withValues(alpha: .9),
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        contextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Saison $seasonLabel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .62),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showSearch(context),
                  tooltip: 'Funktion suchen',
                  color: Colors.white,
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
          if (offerInstall && onInstall != null) ...[
            const SizedBox(height: 8),
            Material(
              color: AppColors.yellowSoft,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onInstall,
                borderRadius: BorderRadius.circular(18),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _MenuIcon(
                        icon: Icons.install_mobile_rounded,
                        selected: true,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${AppIdentity.name} installieren',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Direkt auf dem Startbildschirm öffnen',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final section in ShellSection.values)
            if (destinations.any((item) => item.section == section)) ...[
              _MobileMenuSection(
                section: section,
                audience: audience,
                destinations: destinations
                    .where((item) => item.section == section)
                    .toList(),
                isSelected: (destination) =>
                    destination.route == selectedDestination?.route,
                onSelect: onSelect,
              ),
              const SizedBox(height: 6),
            ],
          TextButton.icon(
            onPressed: onAbout,
            icon: const Icon(Icons.info_outline_rounded, size: 18),
            label: const Text('Über ${AppIdentity.name}'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.appColors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.appColors.outline),
            ),
            child: Row(
              children: [
                _Avatar(name: userName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        userRole,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.verified_user_outlined, color: AppColors.gold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMenuSearchDialog extends StatefulWidget {
  const _MobileMenuSearchDialog({
    required this.destinations,
    required this.audience,
  });
  final List<ShellDestination> destinations;
  final ShellAudience audience;

  @override
  State<_MobileMenuSearchDialog> createState() =>
      _MobileMenuSearchDialogState();
}

class _MobileMenuSearchDialogState extends State<_MobileMenuSearchDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final results = widget.destinations.where((destination) {
      return query.isEmpty ||
          destination.label.toLowerCase().contains(query) ||
          destination.hint.toLowerCase().contains(query) ||
          destination.section
              .labelFor(widget.audience)
              .toLowerCase()
              .contains(query);
    }).toList();
    return AlertDialog(
      title: const Text('Funktion suchen'),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'z. B. Rückmeldungen oder Tabelle',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final destination = results[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(destination.icon, color: AppColors.gold),
                    title: Text(destination.label),
                    subtitle: Text(
                      destination.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, destination),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

class _MobileMenuSection extends StatelessWidget {
  const _MobileMenuSection({
    required this.section,
    required this.audience,
    required this.destinations,
    required this.isSelected,
    required this.onSelect,
  });

  final ShellSection section;
  final ShellAudience audience;
  final List<ShellDestination> destinations;
  final bool Function(ShellDestination destination) isSelected;
  final ValueChanged<ShellDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('mobile-menu-section-${section.name}'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appColors.outline),
        boxShadow: [
          BoxShadow(
            color: context.appColors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _MobileSectionHeading(section: section, audience: audience),
          const SizedBox(height: 4),
          for (final destination in destinations)
            _MobileMenuDestination(
              destination: destination,
              selected: isSelected(destination),
              onTap: () => onSelect(destination),
            ),
        ],
      ),
    );
  }
}

class _MobileMenuDestination extends StatelessWidget {
  const _MobileMenuDestination({
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.yellowSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _MenuIcon(icon: destination.icon, selected: selected),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      Text(
                        destination.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color:
                      selected ? AppColors.gold : context.appColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  const _MenuIcon({required this.icon, this.selected = false});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: selected ? AppColors.yellow : context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.yellow : context.appColors.outline,
        ),
      ),
      child: Icon(icon, size: 18, color: AppColors.black),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.title,
    required this.userName,
    required this.contextLabel,
    required this.onLogout,
    required this.onAccount,
    required this.onContextTap,
    required this.onHome,
    required this.onPrivacy,
    required this.onHelp,
    required this.onAbout,
    required this.onRefresh,
  });

  final String title;
  final String userName;
  final String contextLabel;
  final VoidCallback onLogout;
  final VoidCallback onAccount;
  final VoidCallback onContextTap;
  final VoidCallback onHome;
  final VoidCallback onPrivacy;
  final VoidCallback onHelp;
  final VoidCallback onAbout;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final showDecorativeIdentity =
            constraints.maxWidth >= 360 && textScale < 1.5;
        final allowHeaderWrap = constraints.maxWidth < 360 || textScale >= 1.3;
        return Container(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border(
              bottom: BorderSide(color: context.appColors.outline),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (showDecorativeIdentity) ...[
                  Tooltip(
                    message: 'Zur Startseite',
                    child: InkWell(
                      key: const ValueKey('mobile-header-home-logo'),
                      onTap: onHome,
                      borderRadius: BorderRadius.circular(13),
                      child: Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: context.appColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: context.appColors.outline),
                        ),
                        child: const ClubLogo(size: 36),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: InkWell(
                    onTap: onContextTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.toUpperCase(),
                                maxLines: allowHeaderWrap ? 2 : 1,
                                overflow: allowHeaderWrap
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 9,
                                  letterSpacing: .8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                contextLabel,
                                maxLines: allowHeaderWrap ? 2 : 1,
                                overflow: allowHeaderWrap
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.text,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          )),
                          const Icon(Icons.unfold_more_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                _RefreshIconButton(
                  onRefresh: onRefresh,
                  color: context.appColors.textMuted,
                  compact: true,
                ),
                if (showDecorativeIdentity) ...[
                  _Avatar(name: userName, small: true),
                  const SizedBox(width: 2),
                ],
                PopupMenuButton<_MobileAccountAction>(
                  tooltip: 'Konto und Einstellungen',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) {
                    switch (action) {
                      case _MobileAccountAction.account:
                        onAccount();
                      case _MobileAccountAction.privacy:
                        onPrivacy();
                      case _MobileAccountAction.help:
                        onHelp();
                      case _MobileAccountAction.about:
                        onAbout();
                      case _MobileAccountAction.logout:
                        onLogout();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _MobileAccountAction.account,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.manage_accounts_outlined),
                        title: Text('Mein Konto'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _MobileAccountAction.help,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.help_center_rounded),
                        title: Text('Hilfe & Anleitungen'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _MobileAccountAction.privacy,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.shield_outlined),
                        title: Text('Datenschutz & meine Daten'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _MobileAccountAction.about,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.info_outline_rounded),
                        title: Text('Über FC Teugn Talents'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _MobileAccountAction.logout,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout_rounded),
                        title: Text('Abmelden'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RefreshIconButton extends StatefulWidget {
  const _RefreshIconButton({
    required this.onRefresh,
    required this.color,
    this.compact = false,
  });

  final Future<void> Function() onRefresh;
  final Color color;
  final bool compact;

  @override
  State<_RefreshIconButton> createState() => _RefreshIconButtonState();
}

class _RefreshIconButtonState extends State<_RefreshIconButton> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 18.0 : 19.0;
    return IconButton(
      tooltip: 'Daten aktualisieren',
      visualDensity: widget.compact ? VisualDensity.compact : null,
      onPressed: _refreshing ? null : _refresh,
      color: widget.color,
      disabledColor: widget.color.withValues(alpha: .72),
      icon: _refreshing
          ? SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.color,
              ),
            )
          : Icon(Icons.refresh_rounded, size: size + 1),
    );
  }
}

enum _MobileAccountAction { account, help, privacy, about, logout }

class _ClubBrand extends StatelessWidget {
  const _ClubBrand({required this.light, required this.onTap});

  final bool light;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : AppColors.navy;
    return Tooltip(
      message: 'Zur Startseite',
      child: InkWell(
        key: const ValueKey('desktop-home-logo'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ClubLogo(size: 48),
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
                    'TALENTS',
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
          ),
        ),
      ),
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
