import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/football_options.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/player_view_preferences.dart';
import '../../core/providers.dart';
import '../../core/widgets/player_team_chip.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

const _unassignedTeamFilter = '__unassigned__';

class TrainerPlayersPage extends ConsumerStatefulWidget {
  const TrainerPlayersPage({super.key});

  @override
  ConsumerState<TrainerPlayersPage> createState() => _TrainerPlayersPageState();
}

class _TrainerPlayersPageState extends ConsumerState<TrainerPlayersPage> {
  final _search = TextEditingController();
  final _viewPreferences = PlayerViewPreferences();
  PlayerViewMode _viewMode = PlayerViewMode.compactCards;
  String? _selectedTeamId;

  String get _preferenceUserId =>
      ref.read(authProvider).user?.id ?? 'anonymous';

  @override
  void initState() {
    super.initState();
    unawaited(_loadViewMode());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadViewMode() async {
    try {
      final mode = await _viewPreferences.load(_preferenceUserId);
      if (mounted) setState(() => _viewMode = mode);
    } catch (_) {
      // The compact default remains usable if browser storage is unavailable.
    }
  }

  Future<void> _selectViewMode(PlayerViewMode mode) async {
    setState(() => _viewMode = mode);
    try {
      await _viewPreferences.save(_preferenceUserId, mode);
    } catch (_) {
      // A storage restriction must not prevent changing the current view.
    }
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider);
    final organization = ref.watch(organizationProvider).asData?.value;
    final teams = organization?.teams ?? const <TeamSummary>[];

    return PageScaffold(
      title: 'Spieler',
      subtitle:
          'Alle Jugenden und Mannschaften vereinsweit verwalten und Spieler sicher zuordnen.',
      denseMobileHeader: true,
      action: FilledButton.icon(
        onPressed:
            teams.isEmpty ? null : () => _createPlayer(context, ref, teams),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Spieler anlegen'),
      ),
      child: players.when(
        loading: () => const Center(
          child: LogoLoadingPanel(message: 'Spieler werden geladen …'),
        ),
        error: (_, __) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Mannschaft nicht erreichbar',
          message: 'Die Spielerdaten konnten nicht geladen werden.',
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(playersProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut laden'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.groups_rounded,
              title: 'Noch keine Spieler angelegt',
              message:
                  'Lege das erste Spielerprofil mit Stammdaten und Mannschaftszuordnung an.',
              action: FilledButton.icon(
                onPressed: teams.isEmpty
                    ? null
                    : () => _createPlayer(context, ref, teams),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Erstes Profil anlegen'),
              ),
            );
          }
          final query = _search.text.trim().toLowerCase();
          final filtered = items
              .where((player) {
                if (query.isEmpty) return true;
                return [
                  player.fullName,
                  player.displayName,
                  player.ageGroupCode,
                  player.teamName,
                  player.position,
                  player.secondaryPosition,
                  player.shirtNumber?.toString(),
                ].whereType<String>().join(' ').toLowerCase().contains(query);
              })
              .where(
                (player) =>
                    _selectedTeamId == null ||
                    (_selectedTeamId == _unassignedTeamFilter
                        ? player.teamId == null
                        : player.teamId == _selectedTeamId),
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlayerViewToolbar(
                controller: _search,
                mode: _viewMode,
                visiblePlayers: filtered.length,
                totalPlayers: items.length,
                onSearchChanged: (_) => setState(() {}),
                onModeChanged: _selectViewMode,
                teams: teams,
                selectedTeamId: _selectedTeamId,
                onTeamChanged: (value) =>
                    setState(() => _selectedTeamId = value),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const EmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'Keine Spieler gefunden',
                  message: 'Passe den Suchbegriff an.',
                )
              else
                _CategorizedPlayerCollection(
                  players: filtered,
                  mode: _viewMode,
                  groupByTeam: _selectedTeamId == null,
                  onOpen: (player) =>
                      context.push('/trainer/players/${player.id}'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createPlayer(
    BuildContext context,
    WidgetRef ref,
    List<TeamSummary> teams,
  ) async {
    final draft = await showDialog<_PlayerDraft>(
      context: context,
      builder: (context) => _CreatePlayerDialog(
        teams: teams,
        initialTeamId: _selectedTeamId,
      ),
    );
    if (draft == null) return;
    try {
      final player = await ref.read(repositoryProvider).createPlayer(
            teamId: draft.teamId,
            firstName: draft.firstName,
            lastName: draft.lastName,
            preferredName: draft.preferredName,
            birthDate: draft.birthDate,
            nationality: draft.nationality,
            gender: draft.gender,
            position: draft.position,
            secondaryPosition: draft.secondaryPosition,
            dominantFoot: draft.dominantFoot,
            shirtNumber: draft.shirtNumber,
            passNumber: draft.passNumber,
            joinedAt: draft.joinedAt,
          );
      ref.invalidate(playersProvider);
      if (context.mounted) {
        context.push('/trainer/players/${player.id}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Spielerprofil konnte nicht angelegt werden.'),
          ),
        );
      }
    }
  }
}

class _PlayerViewToolbar extends StatelessWidget {
  const _PlayerViewToolbar({
    required this.controller,
    required this.mode,
    required this.visiblePlayers,
    required this.totalPlayers,
    required this.onSearchChanged,
    required this.onModeChanged,
    required this.teams,
    required this.selectedTeamId,
    required this.onTeamChanged,
  });

  final TextEditingController controller;
  final PlayerViewMode mode;
  final int visiblePlayers;
  final int totalPlayers;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PlayerViewMode> onModeChanged;
  final List<TeamSummary> teams;
  final String? selectedTeamId;
  final ValueChanged<String?> onTeamChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = SizedBox(
            width: constraints.maxWidth < 760 ? constraints.maxWidth : 310,
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Spieler suchen',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche löschen',
                        onPressed: () {
                          controller.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          );
          final switcher = constraints.maxWidth < 760
              ? _MobilePlayerViewMenu(
                  mode: mode,
                  onChanged: onModeChanged,
                )
              : SegmentedButton<PlayerViewMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: PlayerViewMode.list,
                      icon: Icon(Icons.view_list_rounded),
                      label: Text('Liste'),
                    ),
                    ButtonSegment(
                      value: PlayerViewMode.details,
                      icon: Icon(Icons.table_rows_rounded),
                      label: Text('Details'),
                    ),
                    ButtonSegment(
                      value: PlayerViewMode.compactCards,
                      icon: Icon(Icons.grid_view_rounded),
                      label: Text('Karten klein'),
                    ),
                    ButtonSegment(
                      value: PlayerViewMode.largeCards,
                      icon: Icon(Icons.grid_on_rounded),
                      label: Text('Karten groß'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) =>
                      onModeChanged(selection.first),
                );
          final counter = Text(
            visiblePlayers == totalPlayers
                ? '$totalPlayers Spieler'
                : '$visiblePlayers von $totalPlayers Spielern',
            style: TextStyle(
              color: context.appColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          );
          final teamFilter = SizedBox(
            width: constraints.maxWidth < 760 ? constraints.maxWidth : 245,
            child: DropdownButtonFormField<String?>(
              initialValue: selectedTeamId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Jugend / Mannschaft',
                prefixIcon: Icon(Icons.account_tree_rounded),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Alle Jugenden'),
                ),
                const DropdownMenuItem<String?>(
                  value: _unassignedTeamFilter,
                  child: Text('Nicht zugeordnet'),
                ),
                for (final team in teams)
                  DropdownMenuItem<String?>(
                    value: team.id,
                    child: Text(team.displayName),
                  ),
              ],
              onChanged: onTeamChanged,
            ),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    switcher,
                  ],
                ),
                const SizedBox(height: 8),
                teamFilter,
                const SizedBox(height: 6),
                counter,
              ],
            );
          }
          return Row(
            children: [
              search,
              const SizedBox(width: 12),
              teamFilter,
              const SizedBox(width: 16),
              counter,
              const Spacer(),
              Flexible(child: switcher),
            ],
          );
        },
      ),
    );
  }
}

class _MobilePlayerViewMenu extends StatelessWidget {
  const _MobilePlayerViewMenu({required this.mode, required this.onChanged});

  final PlayerViewMode mode;
  final ValueChanged<PlayerViewMode> onChanged;

  static const options = [
    (PlayerViewMode.list, Icons.view_list_rounded, 'Liste', 'sehr kompakt'),
    (PlayerViewMode.details, Icons.table_rows_rounded, 'Details', 'alle Daten'),
    (
      PlayerViewMode.compactCards,
      Icons.grid_view_rounded,
      'Klein',
      '2-spaltig'
    ),
    (PlayerViewMode.largeCards, Icons.badge_rounded, 'Groß', 'Spielerporträt'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere((option) => option.$1 == mode);
    return PopupMenuButton<PlayerViewMode>(
      key: const ValueKey('player-view-menu'),
      tooltip: 'Darstellung wählen',
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option.$1,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(option.$2),
              title: Text(option.$3),
              subtitle: Text(option.$4),
              trailing:
                  mode == option.$1 ? const Icon(Icons.check_rounded) : null,
            ),
          ),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.yellowSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: context.appColors.outline),
        ),
        child: Icon(current.$2, size: 21),
      ),
    );
  }
}

class _CategorizedPlayerCollection extends StatelessWidget {
  const _CategorizedPlayerCollection({
    required this.players,
    required this.mode,
    required this.groupByTeam,
    required this.onOpen,
  });

  final List<PlayerModel> players;
  final PlayerViewMode mode;
  final bool groupByTeam;
  final ValueChanged<PlayerModel> onOpen;

  @override
  Widget build(BuildContext context) {
    if (!groupByTeam) {
      return _PlayerCollection(players: players, mode: mode, onOpen: onOpen);
    }
    final groups = <String, List<PlayerModel>>{};
    for (final player in players) {
      final key = player.teamId == null
          ? 'Nicht zugeordnet'
          : '${player.teamCode}-Jugend';
      groups
          .putIfAbsent(
            key,
            () => [],
          )
          .add(player);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.groups_rounded, size: 20, color: context.appInfo),
              Text(
                entries[index].key,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                '${entries[index].value.length} Spieler',
                style: TextStyle(color: context.appColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _PlayerCollection(
            players: entries[index].value,
            mode: mode,
            onOpen: onOpen,
          ),
        ],
      ],
    );
  }
}

class _PlayerCollection extends StatelessWidget {
  const _PlayerCollection({
    required this.players,
    required this.mode,
    required this.onOpen,
  });

  final List<PlayerModel> players;
  final PlayerViewMode mode;
  final ValueChanged<PlayerModel> onOpen;

  @override
  Widget build(BuildContext context) {
    if (mode == PlayerViewMode.list || mode == PlayerViewMode.details) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: players.length,
        separatorBuilder: (_, __) => const SizedBox(height: 7),
        itemBuilder: (context, index) => mode == PlayerViewMode.list
            ? _PlayerListRow(
                player: players[index],
                onTap: () => onOpen(players[index]),
              )
            : _PlayerDetailsCard(
                player: players[index],
                onTap: () => onOpen(players[index]),
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = mode == PlayerViewMode.compactCards;
        final targetWidth = compact ? 235.0 : 430.0;
        final maximumColumns = compact ? 6 : 3;
        final columns = (constraints.maxWidth / targetWidth)
            .floor()
            .clamp(1, maximumColumns)
            .toInt();
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: players.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: compact ? 10 : 14,
            mainAxisSpacing: compact ? 10 : 14,
            childAspectRatio: compact
                ? (columns == 1 ? 3.0 : 2.15)
                : (columns == 1 ? .8 : 1.35),
          ),
          itemBuilder: (context, index) => compact
              ? _CompactPlayerCard(
                  player: players[index],
                  onTap: () => onOpen(players[index]),
                )
              : _LargePlayerCard(
                  player: players[index],
                  onTap: () => onOpen(players[index]),
                ),
        );
      },
    );
  }
}

class _PlayerListRow extends StatelessWidget {
  const _PlayerListRow({
    required this.player,
    required this.onTap,
  });

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(context, player.status);
    return Material(
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: context.appColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final identity = Row(
                children: [
                  _PlayerAvatar(player: player, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _playerSummary(player),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.appColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (compact && player.shirtNumber != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '#${player.shirtNumber}',
                        style: TextStyle(
                          color: context.appInfo,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  if (compact)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.appColors.textMuted,
                    ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 50),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          PlayerTeamChip(player: player, compact: true),
                          _StatusBadge(status: status, compact: true),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  if (!compact && player.shirtNumber != null)
                    SizedBox(
                      width: 45,
                      child: Text(
                        '#${player.shirtNumber}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.appInfo,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  PlayerTeamChip(player: player, compact: true),
                  const SizedBox(width: 6),
                  _StatusBadge(status: status, compact: true),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.appColors.textMuted,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlayerDetailsCard extends StatelessWidget {
  const _PlayerDetailsCard({required this.player, required this.onTap});

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(context, player.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PlayerAvatar(player: player, size: 50),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.fullName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            PlayerTeamChip(player: player, compact: true),
                            _StatusBadge(status: status, compact: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (player.shirtNumber != null)
                    Text(
                      '#${player.shirtNumber}',
                      style: TextStyle(
                        color: context.appInfo,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const Divider(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MobileDetailChip(
                    label: _positionSummary(player),
                    icon: Icons.sports_soccer_rounded,
                  ),
                  _MobileDetailChip(
                    label: _dominantFootLabel(player.dominantFoot),
                    icon: Icons.directions_run_rounded,
                  ),
                  _MobileDetailChip(
                    label: player.age == null
                        ? 'Alter offen'
                        : '${player.age} Jahre',
                    icon: Icons.cake_outlined,
                  ),
                  _MobileDetailChip(
                    label: '${player.goals} Tore · ${player.assists} Assists',
                    icon: Icons.insights_rounded,
                  ),
                  _MobileDetailChip(
                    label: '${player.appearances} Einsätze',
                    icon: Icons.event_available_rounded,
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

class _MobileDetailChip extends StatelessWidget {
  const _MobileDetailChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.appInfo),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CompactPlayerCard extends StatelessWidget {
  const _CompactPlayerCard({required this.player, required this.onTap});

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(context, player.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _PlayerAvatar(player: player, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _playerSummary(player),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        PlayerTeamChip(player: player, compact: true),
                        _StatusBadge(status: status, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
              if (player.shirtNumber != null)
                Text(
                  '#${player.shirtNumber}',
                  style: TextStyle(
                    color: context.appInfo,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargePlayerCard extends StatelessWidget {
  const _LargePlayerCard({required this.player, required this.onTap});

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(context, player.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _PlayerAvatar(player: player, size: 92),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      player.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  if (player.shirtNumber != null)
                    Text(
                      '#${player.shirtNumber}',
                      style: TextStyle(
                        color: context.appInfo,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _positionSummary(player),
                  style: TextStyle(color: context.appColors.textMuted),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _LargeCardFact(
                      icon: Icons.cake_outlined,
                      label: player.age == null
                          ? 'Alter offen'
                          : '${player.age} Jahre',
                    ),
                    _LargeCardFact(
                      icon: Icons.directions_run_rounded,
                      label: player.dominantFoot == DominantFoot.unknown
                          ? 'Fuß offen'
                          : _dominantFootLabel(player.dominantFoot),
                    ),
                    _LargeCardFact(
                      icon: Icons.person_outline_rounded,
                      label: _largeCardGenderLabel(player.gender),
                    ),
                    _LargeCardFact(
                      icon: Icons.calendar_month_outlined,
                      label: player.joinedAt == null
                          ? 'Eintritt offen'
                          : 'Seit ${player.joinedAt!.year}',
                    ),
                    if (player.nationality?.trim().isNotEmpty == true)
                      _LargeCardFact(
                        icon: Icons.flag_outlined,
                        label: player.nationality!.trim(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        PlayerTeamChip(player: player, compact: true),
                        _StatusBadge(status: status, compact: true),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.appColors.textMuted,
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _CardStatistic(value: player.goals, label: 'Tore'),
                  ),
                  Expanded(
                    child:
                        _CardStatistic(value: player.assists, label: 'Assists'),
                  ),
                  Expanded(
                    child: _CardStatistic(
                      value: player.appearances,
                      label: 'Einsätze',
                    ),
                  ),
                  Expanded(
                    child:
                        _CardStatistic(value: player.starts, label: 'Startelf'),
                  ),
                  Expanded(
                    child:
                        _CardStatistic(value: player.minutes, label: 'Minuten'),
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

class _LargeCardFact extends StatelessWidget {
  const _LargeCardFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: context.appInfo),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _CardStatistic extends StatelessWidget {
  const _CardStatistic({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: TextStyle(color: context.appColors.textMuted, fontSize: 11),
          ),
        ],
      );
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.player, required this.size});

  final PlayerModel player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = player.photoUrl?.trim().isNotEmpty == true;
    final fallback = Container(
      alignment: Alignment.center,
      color: context.appInfo.withValues(alpha: .1),
      child: Text(
        player.initials,
        style: TextStyle(
          color: context.appInfo,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return Semantics(
      key: ValueKey('player-photo-${player.id}'),
      image: hasPhoto,
      label: hasPhoto ? 'Spielerfoto von ${player.fullName}' : null,
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: !hasPhoto
              ? fallback
              : Image.network(
                  player.photoUrl!.trim(),
                  fit: BoxFit.cover,
                  filterQuality:
                      size >= 80 ? FilterQuality.high : FilterQuality.medium,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.compact = false});

  final (String, Color) status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: status.$2.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.$1,
        style: TextStyle(
          color: status.$2,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _playerSummary(PlayerModel player) {
  final values = [
    if (player.ageGroupCode?.isNotEmpty == true)
      '${player.ageGroupCode}-Jugend',
    if (player.teamName?.isNotEmpty == true) player.teamName!,
    if (player.position?.isNotEmpty == true) player.position!,
    if (player.age != null) '${player.age} Jahre',
    '${player.goals} Tore',
    '${player.assists} Assists',
  ];
  return values.isEmpty ? 'Profil vervollständigen' : values.join(' · ');
}

String _positionSummary(PlayerModel player) => [
      if (player.position?.isNotEmpty == true) player.position!,
      if (player.secondaryPosition?.isNotEmpty == true)
        player.secondaryPosition!,
    ].join(' / ').isEmpty
        ? 'Noch offen'
        : [
            if (player.position?.isNotEmpty == true) player.position!,
            if (player.secondaryPosition?.isNotEmpty == true)
              player.secondaryPosition!,
          ].join(' / ');

String _dominantFootLabel(DominantFoot foot) => switch (foot) {
      DominantFoot.right => 'Rechts',
      DominantFoot.left => 'Links',
      DominantFoot.both => 'Beidfüßig',
      DominantFoot.unknown => 'Noch offen',
    };

String _largeCardGenderLabel(PlayerGender? gender) => switch (gender) {
      PlayerGender.male => 'm · männlich',
      PlayerGender.female => 'w · weiblich',
      PlayerGender.diverse => 'd · divers',
      null => 'Geschlecht offen',
    };

(String, Color) _statusStyle(BuildContext context, PlayerStatus status) =>
    switch (status) {
      PlayerStatus.active => ('Aktiv', context.appSuccess),
      PlayerStatus.injured => ('Verletzt', Colors.redAccent),
      PlayerStatus.paused => ('Pausiert', context.appWarning),
      PlayerStatus.left => ('Ausgetreten', context.appColors.textMuted),
    };

class _CreatePlayerDialog extends StatefulWidget {
  const _CreatePlayerDialog({
    required this.teams,
    this.initialTeamId,
  });

  final List<TeamSummary> teams;
  final String? initialTeamId;

  @override
  State<_CreatePlayerDialog> createState() => _CreatePlayerDialogState();
}

class _CreatePlayerDialogState extends State<_CreatePlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _preferredName = TextEditingController();
  final _nationality = TextEditingController();
  final _shirtNumber = TextEditingController();
  final _passNumber = TextEditingController();
  DateTime? _birthDate;
  DateTime? _joinedAt;
  PlayerGender? _gender;
  String? _position;
  String? _secondaryPosition;
  DominantFoot _dominantFoot = DominantFoot.unknown;
  late String _teamId;

  @override
  void initState() {
    super.initState();
    _teamId = widget.teams.any((team) => team.id == widget.initialTeamId)
        ? widget.initialTeamId!
        : widget.teams.first.id;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _preferredName.dispose();
    _nationality.dispose();
    _shirtNumber.dispose();
    _passNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void save() {
      if (!_formKey.currentState!.validate()) return;
      Navigator.pop(
        context,
        _PlayerDraft(
          teamId: _teamId,
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          preferredName: _optional(_preferredName),
          nationality: _optional(_nationality),
          gender: _gender,
          position: _position,
          secondaryPosition: _secondaryPosition,
          dominantFoot: _dominantFoot,
          shirtNumber: int.tryParse(_shirtNumber.text),
          passNumber: _optional(_passNumber),
          birthDate: _birthDate,
          joinedAt: _joinedAt,
        ),
      );
    }

    return ResponsiveFormDialog(
      title: 'Spielerprofil anlegen',
      subtitle: 'Zuordnung, persönliche Daten und Fußballprofil erfassen.',
      saveLabel: 'Profil anlegen',
      saveIcon: Icons.person_add_alt_1_rounded,
      onSave: save,
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              ResponsiveFormSection(
                title: 'Zuordnung',
                icon: Icons.groups_rounded,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _teamId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jugend / Mannschaft *',
                      prefixIcon: Icon(Icons.groups_rounded),
                    ),
                    items: [
                      for (final team in widget.teams)
                        DropdownMenuItem(
                          value: team.id,
                          child: Text(team.displayName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _teamId = value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Persönliche Daten',
                icon: Icons.badge_outlined,
                children: [
                  ResponsiveFormRow(
                    children: [
                      TextFormField(
                        controller: _firstName,
                        decoration:
                            const InputDecoration(labelText: 'Vorname *'),
                        validator: _required,
                      ),
                      TextFormField(
                        controller: _lastName,
                        decoration:
                            const InputDecoration(labelText: 'Nachname *'),
                        validator: _required,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ResponsiveFormRow(
                    children: [
                      TextFormField(
                        controller: _preferredName,
                        decoration: const InputDecoration(labelText: 'Rufname'),
                      ),
                      TextFormField(
                        controller: _nationality,
                        decoration:
                            const InputDecoration(labelText: 'Nationalität'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ResponsiveFormRow(
                    children: [
                      _DateField(
                        label: 'Geburtsdatum',
                        value: _birthDate,
                        onChanged: (value) =>
                            setState(() => _birthDate = value),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      ),
                      DropdownButtonFormField<PlayerGender?>(
                        key: const ValueKey('player-create-gender'),
                        initialValue: _gender,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Geschlecht (m/w/d)',
                          prefixIcon: Icon(Icons.wc_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Noch offen'),
                          ),
                          DropdownMenuItem(
                            value: PlayerGender.male,
                            child: Text('m · männlich'),
                          ),
                          DropdownMenuItem(
                            value: PlayerGender.female,
                            child: Text('w · weiblich'),
                          ),
                          DropdownMenuItem(
                            value: PlayerGender.diverse,
                            child: Text('d · divers'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _gender = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ResponsiveFormRow(
                    children: [
                      _DateField(
                        label: 'Im Verein seit',
                        value: _joinedAt,
                        onChanged: (value) => setState(() => _joinedAt = value),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('player-create-pass-number'),
                    controller: _passNumber,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Passnummer',
                      helperText: 'Nummer des Spielerpasses (optional)',
                      prefixIcon: Icon(Icons.verified_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Fußballprofil',
                icon: Icons.sports_soccer_rounded,
                children: [
                  ResponsiveFormRow(
                    children: [
                      DropdownButtonFormField<String?>(
                        initialValue: _position,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Hauptposition',
                        ),
                        items: footballOptionItems(
                          options: footballPositions,
                          emptyLabel: 'Noch offen',
                          showCode: true,
                        ),
                        onChanged: (value) => setState(() => _position = value),
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: _secondaryPosition,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Nebenposition',
                        ),
                        items: footballOptionItems(
                          options: footballPositions,
                          emptyLabel: 'Keine Nebenposition',
                          showCode: true,
                        ),
                        onChanged: (value) =>
                            setState(() => _secondaryPosition = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ResponsiveFormRow(
                    children: [
                      DropdownButtonFormField<DominantFoot>(
                        initialValue: _dominantFoot,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Starker Fuß'),
                        items: const [
                          DropdownMenuItem(
                            value: DominantFoot.unknown,
                            child: Text('Noch offen'),
                          ),
                          DropdownMenuItem(
                            value: DominantFoot.right,
                            child: Text('Rechts'),
                          ),
                          DropdownMenuItem(
                            value: DominantFoot.left,
                            child: Text('Links'),
                          ),
                          DropdownMenuItem(
                            value: DominantFoot.both,
                            child: Text('Beidfüßig'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _dominantFoot = value ?? DominantFoot.unknown,
                        ),
                      ),
                      TextFormField(
                        controller: _shirtNumber,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Trikotnummer'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;

  String? _optional(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          firstDate: firstDate,
          lastDate: lastDate,
          initialDate: value ?? lastDate,
        );
        if (selected != null) onChanged(selected);
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value == null
              ? 'Auswählen'
              : '${value!.day.toString().padLeft(2, '0')}.${value!.month.toString().padLeft(2, '0')}.${value!.year}',
        ),
      ),
    );
  }
}

class _PlayerDraft {
  const _PlayerDraft({
    required this.teamId,
    required this.firstName,
    required this.lastName,
    required this.dominantFoot,
    this.preferredName,
    this.nationality,
    this.birthDate,
    this.gender,
    this.position,
    this.secondaryPosition,
    this.shirtNumber,
    this.passNumber,
    this.joinedAt,
  });

  final String teamId;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? nationality;
  final DateTime? birthDate;
  final PlayerGender? gender;
  final String? position;
  final String? secondaryPosition;
  final DominantFoot dominantFoot;
  final int? shirtNumber;
  final String? passNumber;
  final DateTime? joinedAt;
}
