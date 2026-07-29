import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/football_options.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/player_view_preferences.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

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
      action: FilledButton.icon(
        onPressed:
            teams.isEmpty ? null : () => _createPlayer(context, ref, teams),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Spieler anlegen'),
      ),
      child: players.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                    _selectedTeamId == null || player.teamId == _selectedTeamId,
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
                      context.go('/trainer/players/${player.id}'),
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
            position: draft.position,
            secondaryPosition: draft.secondaryPosition,
            dominantFoot: draft.dominantFoot,
            shirtNumber: draft.shirtNumber,
            joinedAt: draft.joinedAt,
          );
      ref.invalidate(playersProvider);
      if (context.mounted) {
        context.go('/trainer/players/${player.id}');
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
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
          final switcher = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<PlayerViewMode>(
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
              onSelectionChanged: (selection) => onModeChanged(selection.first),
            ),
          );
          final counter = Text(
            visiblePlayers == totalPlayers
                ? '$totalPlayers Spieler'
                : '$visiblePlayers von $totalPlayers Spielern',
            style: const TextStyle(
              color: AppColors.muted,
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
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Alle Jugenden'),
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
                search,
                const SizedBox(height: 10),
                teamFilter,
                const SizedBox(height: 10),
                counter,
                const SizedBox(height: 10),
                switcher,
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
      final key = [
        if (player.ageGroupCode?.isNotEmpty == true)
          '${player.ageGroupCode}-Jugend',
        if (player.teamName?.isNotEmpty == true) player.teamName!,
      ].join(' · ');
      groups
          .putIfAbsent(
            key.isEmpty ? 'Ohne Mannschaftsangabe' : key,
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
          Row(
            children: [
              const Icon(Icons.groups_rounded, size: 20, color: AppColors.blue),
              const SizedBox(width: 8),
              Text(
                entries[index].key,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entries[index].value.length} Spieler',
                style: const TextStyle(color: AppColors.muted),
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
        itemBuilder: (context, index) => _PlayerListRow(
          player: players[index],
          detailed: mode == PlayerViewMode.details,
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
                ? (columns == 1 ? 3.5 : 2.15)
                : (columns == 1 ? 3.0 : 1.9),
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
    required this.detailed,
    required this.onTap,
  });

  final PlayerModel player;
  final bool detailed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(player.status);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: detailed ? 13 : 8,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showDetailColumns = detailed && constraints.maxWidth >= 720;
              return Row(
                children: [
                  _PlayerAvatar(player: player, size: detailed ? 48 : 38),
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
                          style: TextStyle(
                            fontSize: detailed ? 16 : 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          showDetailColumns
                              ? _playerSummary(player)
                              : [
                                  _playerSummary(player),
                                  if (detailed)
                                    _dominantFootLabel(player.dominantFoot),
                                ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (showDetailColumns) ...[
                    Expanded(
                      flex: 2,
                      child: _DetailValue(
                        label: 'Position',
                        value: _positionSummary(player),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _DetailValue(
                        label: 'Starker Fuß',
                        value: _dominantFootLabel(player.dominantFoot),
                      ),
                    ),
                  ],
                  if (player.shirtNumber != null)
                    SizedBox(
                      width: 45,
                      child: Text(
                        '#${player.shirtNumber}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  _StatusBadge(status: status, compact: !detailed),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
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

class _CompactPlayerCard extends StatelessWidget {
  const _CompactPlayerCard({required this.player, required this.onTap});

  final PlayerModel player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(player.status);
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
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _StatusBadge(status: status, compact: true),
                  ],
                ),
              ),
              if (player.shirtNumber != null)
                Text(
                  '#${player.shirtNumber}',
                  style: const TextStyle(
                    color: AppColors.blue,
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
    final status = _statusStyle(player.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _PlayerAvatar(player: player, size: 58),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            player.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (player.shirtNumber != null)
                          Text(
                            '#${player.shirtNumber}',
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(_playerSummary(player)),
                    const SizedBox(height: 9),
                    _StatusBadge(status: status),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.player, required this.size});

  final PlayerModel player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      color: AppColors.blue.withValues(alpha: .1),
      child: Text(
        '${player.firstName[0]}${player.lastName[0]}'.toUpperCase(),
        style: const TextStyle(
          color: AppColors.blue,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: player.photoUrl == null
            ? fallback
            : Image.network(
                player.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
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

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
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

(String, Color) _statusStyle(PlayerStatus status) => switch (status) {
      PlayerStatus.active => ('Aktiv', AppColors.teal),
      PlayerStatus.injured => ('Verletzt', Colors.redAccent),
      PlayerStatus.paused => ('Pausiert', AppColors.orange),
      PlayerStatus.left => ('Ausgetreten', AppColors.muted),
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
  DateTime? _birthDate;
  DateTime? _joinedAt;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spielerprofil anlegen'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstName,
                        decoration:
                            const InputDecoration(labelText: 'Vorname *'),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastName,
                        decoration:
                            const InputDecoration(labelText: 'Nachname *'),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _preferredName,
                        decoration: const InputDecoration(labelText: 'Rufname'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _nationality,
                        decoration:
                            const InputDecoration(labelText: 'Nationalität'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Geburtsdatum',
                        value: _birthDate,
                        onChanged: (value) =>
                            setState(() => _birthDate = value),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Im Verein seit',
                        value: _joinedAt,
                        onChanged: (value) => setState(() => _joinedAt = value),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
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
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<DominantFoot>(
                        initialValue: _dominantFoot,
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _shirtNumber,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Trikotnummer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PlayerDraft(
                teamId: _teamId,
                firstName: _firstName.text.trim(),
                lastName: _lastName.text.trim(),
                preferredName: _optional(_preferredName),
                nationality: _optional(_nationality),
                position: _position,
                secondaryPosition: _secondaryPosition,
                dominantFoot: _dominantFoot,
                shirtNumber: int.tryParse(_shirtNumber.text),
                birthDate: _birthDate,
                joinedAt: _joinedAt,
              ),
            );
          },
          child: const Text('Profil anlegen'),
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
    this.position,
    this.secondaryPosition,
    this.shirtNumber,
    this.joinedAt,
  });

  final String teamId;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? nationality;
  final DateTime? birthDate;
  final String? position;
  final String? secondaryPosition;
  final DominantFoot dominantFoot;
  final int? shirtNumber;
  final DateTime? joinedAt;
}
