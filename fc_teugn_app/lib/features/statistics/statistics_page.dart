import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/models/statistics.dart';
import '../../core/providers.dart';
import '../../core/role_permissions.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  static const _allSeasons = '__all_seasons__';

  StatisticsOverview? _overview;
  bool _loading = true;
  String? _error;
  String? _seasonId;
  String? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = ref.read(authProvider).user;
      if (user == null || user.teamId.isEmpty) {
        throw StateError('Keine Mannschaft zugeordnet.');
      }
      var teamId = user.teamId;
      if (canSelectStatisticsTeam(user.role)) {
        final organization = await ref.read(organizationProvider.future);
        teamId = resolveStatisticsPageTeamId(
          registeredTeamId: user.teamId,
          currentTeamId: organization.currentTeam.id,
          workingTeamIds: organization.workingContext.teamIds,
          includeAllTeams: organization.workingContext.includeAllTeams,
          selectedTeamId: _selectedTeamId,
        );
      }
      final overview = await ref.read(repositoryProvider).statistics(
        teamIds: [teamId],
        seasonId: _seasonId,
      );
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Die Statistikdaten konnten nicht geladen werden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'Statistiken',
        subtitle:
            'Automatisch aus Spielen, Aufstellungen und Liveticker berechnet.',
        child: _loading
            ? const Center(
                child: LogoLoadingPanel(
                  message: 'Statistiken werden geladen …',
                ),
              )
            : _error != null || _overview == null
                ? EmptyState(
                    icon: Icons.query_stats_rounded,
                    title: 'Statistiken nicht erreichbar',
                    message: _error!,
                  )
                : _content(context, _overview!),
      );

  Widget _content(BuildContext context, StatisticsOverview overview) {
    final team = overview.team;
    final selectedLabel = overview.selectedSeason?.name ?? 'Gesamt';
    final user = ref.watch(authProvider).user;
    final organization = ref.watch(organizationProvider).valueOrNull;
    final canSelectTeam = user != null && canSelectStatisticsTeam(user.role);
    final statisticsTeams = _teamOptions(organization);
    final registeredTeamId = user?.teamId;
    final selectedTeamId = canSelectTeam && organization != null
        ? resolveStatisticsPageTeamId(
            registeredTeamId: registeredTeamId ?? '',
            currentTeamId: organization.currentTeam.id,
            workingTeamIds: organization.workingContext.teamIds,
            includeAllTeams: organization.workingContext.includeAllTeams,
            selectedTeamId: _selectedTeamId,
          )
        : registeredTeamId;
    final selectedTeam = _findTeam(statisticsTeams, selectedTeamId);
    final selectedTeamLabel =
        selectedTeam?.displayName ?? 'Zugeordnete Mannschaft';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final seasonSelector = DropdownButtonFormField<String>(
                  key:
                      ValueKey('statistics-season-${_seasonId ?? _allSeasons}'),
                  initialValue: _seasonId ?? _allSeasons,
                  decoration: const InputDecoration(
                    labelText: 'Auswertungszeitraum',
                    prefixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: _allSeasons,
                      child: Text('Gesamt – alle Saisons'),
                    ),
                    for (final season in overview.seasons)
                      DropdownMenuItem<String>(
                        value: season.id,
                        child: Text(
                          '${season.name}${season.isActive ? ' · aktiv' : ''}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    final seasonId = value == _allSeasons ? null : value;
                    if (seasonId == _seasonId) return;
                    setState(() => _seasonId = seasonId);
                    _load();
                  },
                );
                final teamSelector = _TeamSelector(
                  canSelect: canSelectTeam,
                  teams: statisticsTeams,
                  selectedTeamId: selectedTeamId,
                  selectedTeamLabel: selectedTeamLabel,
                  onChanged: (teamId) {
                    if (teamId == null || teamId == selectedTeamId) return;
                    setState(() {
                      _selectedTeamId = teamId;
                      _seasonId = null;
                    });
                    _load();
                  },
                );
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedTeamLabel · $selectedLabel',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      overview.selectedSeason == null
                          ? 'Vereins- und Spielerwerte über alle verfügbaren Saisons'
                          : 'Saisonwerte mit direktem Vergleich zur Gesamtstatistik',
                      style: TextStyle(color: context.appColors.textMuted),
                    ),
                  ],
                );
                final reload = IconButton.filledTonal(
                  onPressed: _load,
                  tooltip: 'Neu laden',
                  icon: const Icon(Icons.refresh_rounded),
                );
                if (constraints.maxWidth < 680) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      summary,
                      const SizedBox(height: 14),
                      teamSelector,
                      const SizedBox(height: 10),
                      seasonSelector,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: reload),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
                    SizedBox(
                      width: 320,
                      child: Column(
                        children: [
                          teamSelector,
                          const SizedBox(height: 10),
                          seasonSelector,
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    reload,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final cardWidth = compact ? (constraints.maxWidth - 10) / 2 : 190.0;
            return Wrap(
              spacing: compact ? 10 : 12,
              runSpacing: compact ? 10 : 12,
              children: [
                _MetricCard(
                  width: cardWidth,
                  compact: compact,
                  label: 'Spiele · $selectedLabel',
                  value: '${team.matches}',
                  icon: Icons.sports_soccer_rounded,
                ),
                _MetricCard(
                  width: cardWidth,
                  compact: compact,
                  label: 'Siege',
                  value: '${team.wins}',
                  icon: Icons.emoji_events_rounded,
                  color: context.appSuccess,
                ),
                _MetricCard(
                  width: cardWidth,
                  compact: compact,
                  label: 'Siegquote',
                  value: '${team.winRate.toStringAsFixed(1)} %',
                  icon: Icons.trending_up_rounded,
                ),
                _MetricCard(
                  width: cardWidth,
                  compact: compact,
                  label: 'Tore',
                  value: '${team.goalsFor}:${team.goalsAgainst}',
                  icon: Icons.scoreboard_rounded,
                  color: context.appWarning,
                ),
                _MetricCard(
                  width: cardWidth,
                  compact: compact,
                  label: 'Tore/Spiel',
                  value: team.goalsPerMatch.toStringAsFixed(2),
                  icon: Icons.analytics_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _FormCard(form: team.form),
        if (overview.performanceCenter != null) ...[
          const SizedBox(height: 18),
          _PerformanceCenterCard(data: overview.performanceCenter!),
        ],
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final matchList = _MatchHistory(
              matches: overview.matches,
              scopeLabel: selectedLabel,
            );
            final playerList = _PlayerStatistics(
              players: overview.players,
              ownOnly: overview.individualScope == 'OWN_PLAYERS',
              scopeLabel: selectedLabel,
              showCareer: overview.selectedSeason != null,
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: matchList),
                      const SizedBox(width: 16),
                      Expanded(child: playerList),
                    ],
                  )
                : Column(
                    children: [
                      matchList,
                      const SizedBox(height: 16),
                      playerList,
                    ],
                  );
          },
        ),
      ],
    );
  }

  TeamSummary? _findTeam(List<TeamSummary>? teams, String? teamId) {
    if (teams == null || teamId == null) return null;
    for (final team in teams) {
      if (team.id == teamId) return team;
    }
    return null;
  }

  List<TeamSummary> _teamOptions(OrganizationContext? organization) {
    if (organization == null) return const [];
    if (organization.teams.any(
      (team) => team.id == organization.currentTeam.id,
    )) {
      return organization.teams;
    }
    return [organization.currentTeam, ...organization.teams];
  }
}

String resolveStatisticsPageTeamId({
  required String registeredTeamId,
  required String currentTeamId,
  required List<String> workingTeamIds,
  required bool includeAllTeams,
  String? selectedTeamId,
}) {
  if (selectedTeamId?.isNotEmpty == true) return selectedTeamId!;
  if (includeAllTeams && workingTeamIds.contains(registeredTeamId)) {
    return registeredTeamId;
  }
  if (!includeAllTeams && workingTeamIds.isNotEmpty) {
    return workingTeamIds.first;
  }
  return currentTeamId;
}

class _TeamSelector extends StatelessWidget {
  const _TeamSelector({
    required this.canSelect,
    required this.teams,
    required this.selectedTeamId,
    required this.selectedTeamLabel,
    required this.onChanged,
  });

  final bool canSelect;
  final List<TeamSummary> teams;
  final String? selectedTeamId;
  final String selectedTeamLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!canSelect || teams.isEmpty) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Jugend / Mannschaft',
          prefixIcon: Icon(Icons.groups_rounded),
        ),
        child: Text(
          selectedTeamLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final effectiveValue = teams.any((team) => team.id == selectedTeamId)
        ? selectedTeamId
        : teams.first.id;
    return DropdownButtonFormField<String>(
      key: ValueKey('statistics-team-$effectiveValue'),
      initialValue: effectiveValue,
      decoration: const InputDecoration(
        labelText: 'Jugend / Mannschaft',
        prefixIcon: Icon(Icons.groups_rounded),
      ),
      items: [
        for (final team in teams)
          DropdownMenuItem<String>(
            value: team.id,
            child: Text(
              '${team.displayName} · ${team.seasonName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.width = 190,
    this.compact = false,
    this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.appInfo;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 18),
          child: Row(
            children: [
              CircleAvatar(
                radius: compact ? 18 : 20,
                backgroundColor: accent.withValues(alpha: .1),
                child: Icon(icon, color: accent, size: compact ? 20 : 24),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: compact
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.appColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.form});
  final List<String> form;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.timeline_rounded, color: context.appInfo),
              Text(
                'Letzte Form',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (form.isEmpty)
                const Text('Noch keine beendeten Spiele')
              else
                for (final result in form)
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: switch (result) {
                      'WIN' => context.appSuccess,
                      'LOSS' => Colors.deepOrange,
                      _ => Colors.blueGrey,
                    },
                    child: Text(
                      result == 'WIN'
                          ? 'S'
                          : result == 'LOSS'
                              ? 'N'
                              : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
}

class _PerformanceCenterCard extends StatelessWidget {
  const _PerformanceCenterCard({required this.data});

  final PerformanceCenter data;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final metrics = [
            _PerformanceMetric(
              compact: compact,
              label: 'Trainer',
              value: data.teamAverage == null
                  ? '–'
                  : '${data.teamAverage!.toStringAsFixed(1)} / 10',
            ),
            _PerformanceMetric(
              compact: compact,
              label: 'Eltern · anonym',
              value: data.parentTeamAverage == null
                  ? '–'
                  : '${data.parentTeamAverage!.toStringAsFixed(1)} / 10',
            ),
            _PerformanceMetric(
              compact: compact,
              label: 'Spiele / offen',
              value: '${data.ratedMatches} / ${data.unratedMatches}',
            ),
          ];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 10 : 15),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.navy, AppColors.blue],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.insights_rounded,
                            color: Colors.white,
                            size: compact ? 25 : 28,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Leistungszentrum · trainerintern',
                                  maxLines: 2,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 15 : 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Entwicklung erkennen – ohne Rangliste.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: compact ? 11 : 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          for (var index = 0;
                              index < metrics.length;
                              index++) ...[
                            if (index > 0) const SizedBox(width: 6),
                            Expanded(child: metrics[index]),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(compact ? 11 : 18),
                  child: Column(
                    children: [
                      _PerformancePlayerList(
                        players: data.players,
                        compact: compact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

@visibleForTesting
Widget performanceCenterCardForTesting(PerformanceCenter data) =>
    _PerformanceCenterCard(data: data);

class _PerformanceMetric extends StatelessWidget {
  const _PerformanceMetric({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 14,
          vertical: compact ? 7 : 9,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 9.5 : 12,
                height: 1.05,
              ),
            ),
            if (compact) const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 14 : null,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _PerformancePlayerList extends StatefulWidget {
  const _PerformancePlayerList({
    required this.players,
    required this.compact,
  });

  final List<PlayerPerformance> players;
  final bool compact;

  @override
  State<_PerformancePlayerList> createState() => _PerformancePlayerListState();
}

class _PerformancePlayerListState extends State<_PerformancePlayerList> {
  String _query = '';
  String _strength = 'ALL';
  String _position = 'ALL';

  List<String> get _positions => [
        'ALL',
        ...{
          for (final player in widget.players)
            if (player.position?.trim().isNotEmpty == true)
              player.position!.trim(),
        }.toList()
          ..sort((a, b) => a.compareTo(b)),
      ];

  int get _activeFilterCount =>
      (_strength == 'ALL' ? 0 : 1) + (_position == 'ALL' ? 0 : 1);

  Future<void> _openFilters() async {
    var strength = _strength;
    var position = _position;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Spieler filtern',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: strength,
                  decoration: const InputDecoration(labelText: 'Stärke'),
                  items: const [
                    DropdownMenuItem(
                      value: 'ALL',
                      child: Text('Alle Stärken'),
                    ),
                    DropdownMenuItem(
                      value: 'STRONG',
                      child: Text('Stark · ab 8'),
                    ),
                    DropdownMenuItem(
                      value: 'MIDDLE',
                      child: Text('Mittel · 5 bis 7,9'),
                    ),
                    DropdownMenuItem(
                      value: 'DEVELOPMENT',
                      child: Text('Entwicklung · unter 5'),
                    ),
                  ],
                  onChanged: (value) => setSheetState(
                    () => strength = value ?? 'ALL',
                  ),
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: position,
                  decoration: const InputDecoration(labelText: 'Position'),
                  items: [
                    for (final item in _positions)
                      DropdownMenuItem(
                        value: item,
                        child: Text(
                          item == 'ALL' ? 'Alle Positionen' : item,
                        ),
                      ),
                  ],
                  onChanged: (value) => setSheetState(
                    () => position = value ?? 'ALL',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, ('ALL', 'ALL')),
                        child: const Text('Zurücksetzen'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, (strength, position)),
                        child: const Text('Anwenden'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _strength = result.$1;
      _position = result.$2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final players = widget.players.where((player) {
      if (normalizedQuery.isNotEmpty &&
          !player.name.toLowerCase().contains(normalizedQuery)) {
        return false;
      }
      if (_position != 'ALL' && player.position != _position) return false;
      final reference =
          player.average > 0 ? player.average : (player.parentAverage ?? 0);
      return switch (_strength) {
        'STRONG' => reference >= 8,
        'MIDDLE' => reference >= 5 && reference < 8,
        'DEVELOPMENT' => reference > 0 && reference < 5,
        _ => true,
      };
    }).toList();
    if (widget.players.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: widget.compact ? 6 : 18),
        child: const Text(
          'Noch keine Spielerbewertungen in diesem Zeitraum.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Spieler suchen',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(width: 7),
            OutlinedButton.icon(
              key: const ValueKey('performance-filter-button'),
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: _activeFilterCount > 0,
                label: Text('$_activeFilterCount'),
                child: const Icon(Icons.tune_rounded, size: 18),
              ),
              label: const Text('Filter'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 11),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 7, 2, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${players.length} von ${widget.players.length} Spielern',
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_activeFilterCount > 0)
                TextButton(
                  onPressed: () => setState(() {
                    _strength = 'ALL';
                    _position = 'ALL';
                  }),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('Filter löschen'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        if (players.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Für diesen Filter wurden keine Spieler gefunden.'),
          )
        else
          for (final player in players) _PlayerPerformanceRow(player: player),
      ],
    );
  }
}

class _PlayerPerformanceRow extends StatelessWidget {
  const _PlayerPerformanceRow({required this.player});

  final PlayerPerformance player;

  @override
  Widget build(BuildContext context) {
    final trendIcon = player.trend > .15
        ? Icons.trending_up_rounded
        : player.trend < -.15
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;
    final trendColor = player.trend > .15
        ? context.appSuccess
        : player.trend < -.15
            ? Colors.deepOrange
            : context.appColors.textMuted;
    return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _PerformanceDetailSheet(player: player),
            ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(child: Text(player.shirtNumber?.toString() ?? 'FC')),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.name,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      [player.position, player.secondaryPosition]
                          .whereType<String>()
                          .where((value) => value.trim().isNotEmpty)
                          .join(' / '),
                      style: TextStyle(color: context.appColors.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Trainer '
                                '${player.ratedMatches == 0 ? '–' : player.average.toStringAsFixed(1)}',
                            style: TextStyle(
                              color: context.appInfo,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(
                            text: '  ·  Eltern '
                                '${player.parentAverage?.toStringAsFixed(1) ?? '–'}',
                            style: TextStyle(
                              color: context.appWarning,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(
                            text: '  ·  ${player.ratedMatches} '
                                '${player.ratedMatches == 1 ? 'Spiel' : 'Spiele'}',
                            style: TextStyle(
                              color: context.appColors.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(trendIcon, color: trendColor),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ));
  }
}

class _RatingValueChip extends StatelessWidget {
  const _RatingValueChip({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final double? value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label ${value == null ? '–' : '${value!.toStringAsFixed(1)} / 10'}',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
            Text(
              detail,
              style:
                  TextStyle(fontSize: 9.5, color: context.appColors.textMuted),
            ),
          ],
        ),
      );
}

class _PerformanceDetailSheet extends StatelessWidget {
  const _PerformanceDetailSheet({required this.player});

  final PlayerPerformance player;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .88,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  player.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Entwicklung · nur für das Trainerteam sichtbar',
                  style: TextStyle(color: context.appColors.textMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RatingValueChip(
                        label: 'Trainer',
                        value: player.ratedMatches == 0 ? null : player.average,
                        detail: '${player.ratedMatches} Spiele',
                        color: context.appInfo,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RatingValueChip(
                        label: 'Eltern',
                        value: player.parentAverage,
                        detail: '${player.parentRatingCount} anonyme Stimmen',
                        color: context.appWarning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Entwicklungskurve',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (player.timeline.isEmpty)
                  const Text('Noch keine Werte für eine Kurve vorhanden.')
                else
                  Container(
                    height: 210,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: CustomPaint(
                      painter: _PerformanceChartPainter(
                        player.timeline,
                        gridColor: context.appColors.outline,
                        labelColor: context.appColors.textMuted,
                        trainerColor: context.appInfo,
                        parentColor: context.appWarning,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  children: [
                    _ChartLegend(label: 'Trainer', color: context.appInfo),
                    _ChartLegend(
                      label: 'Eltern · anonym',
                      color: context.appWarning,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Zeitleiste',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                for (final point in player.timeline.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child:
                          Text('${point.startAt.day}.${point.startAt.month}.'),
                    ),
                    title: Text(point.opponent),
                    subtitle: Text(
                      'Trainer ${point.trainerScore?.toStringAsFixed(1) ?? '–'} · '
                      'Eltern ${point.parentAverage?.toStringAsFixed(1) ?? '–'} '
                      '(${point.parentRatingCount} Stimmen)',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _PerformanceChartPainter extends CustomPainter {
  const _PerformanceChartPainter(
    this.points, {
    required this.gridColor,
    required this.labelColor,
    required this.trainerColor,
    required this.parentColor,
  });
  final List<PerformanceTimelinePoint> points;
  final Color gridColor;
  final Color labelColor;
  final Color trainerColor;
  final Color parentColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 24.0;
    const top = 8.0;
    const bottom = 20.0;
    final chartWidth = size.width - left - 6;
    final chartHeight = size.height - top - bottom;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final label = TextPainter(textDirection: TextDirection.ltr);
    for (final score in [1, 5, 10]) {
      final y = top + (10 - score) / 9 * chartHeight;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      label
        ..text = TextSpan(
          text: '$score',
          style: TextStyle(fontSize: 9, color: labelColor),
        )
        ..layout();
      label.paint(canvas, Offset(1, y - label.height / 2));
    }
    void drawSeries(
        double? Function(PerformanceTimelinePoint) value, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final dot = Paint()..color = color;
      Path? path;
      for (var index = 0; index < points.length; index++) {
        final score = value(points[index]);
        if (score == null) {
          path = null;
          continue;
        }
        final x = left +
            (points.length == 1
                ? chartWidth / 2
                : index / (points.length - 1) * chartWidth);
        final y = top + (10 - score.clamp(1, 10)) / 9 * chartHeight;
        if (path == null) {
          path = Path()..moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3.5, dot);
        if (index == points.length - 1 || value(points[index + 1]) == null) {
          canvas.drawPath(path, paint);
        }
      }
    }

    drawSeries((point) => point.trainerScore, trainerColor);
    drawSeries((point) => point.parentAverage, parentColor);
  }

  @override
  bool shouldRepaint(covariant _PerformanceChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.trainerColor != trainerColor ||
      oldDelegate.parentColor != parentColor;
}

class _MatchHistory extends StatelessWidget {
  const _MatchHistory({required this.matches, required this.scopeLabel});
  final List<MatchResultStatistic> matches;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vergangene Spiele · $scopeLabel',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 3),
          Text(
            'Ergebnis antippen für Torschützen, Vorlagen und Spielereignisse.',
            style: TextStyle(color: context.appColors.textMuted),
          ),
          const SizedBox(height: 10),
          if (matches.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                child: Center(
                  child: Text('Noch keine beendeten Spiele im Zeitraum'),
                ),
              ),
            )
          else
            for (final match in matches.take(20)) ...[
              _PastMatchCard(match: match),
              const SizedBox(height: 9),
            ],
        ],
      );
}

@visibleForTesting
Widget matchHistoryForTesting(
  List<MatchResultStatistic> matches, {
  String scopeLabel = 'Gesamt',
}) =>
    _MatchHistory(matches: matches, scopeLabel: scopeLabel);

class _PastMatchCard extends StatelessWidget {
  const _PastMatchCard({required this.match});

  final MatchResultStatistic match;

  @override
  Widget build(BuildContext context) {
    final homeName = match.isHome ? match.teamName : match.opponent;
    final awayName = match.isHome ? match.opponent : match.teamName;
    final homeGoals = match.isHome ? match.ourGoals : match.theirGoals;
    final awayGoals = match.isHome ? match.theirGoals : match.ourGoals;
    final ownGoals = match.events.where((event) => event.isOwnGoal).toList();
    final assists = ownGoals.where((event) => event.assist != null).length;
    final otherEvents = match.events.where((event) => !event.isGoal).length;
    final dateLabel = MaterialLocalizations.of(context)
        .formatCompactDate(match.startAt.toLocal());

    return Card(
      key: ValueKey('past-match-${match.id}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: _MatchResultBadge(result: match.result),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [dateLabel, match.competition ?? 'Spiel'].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.appColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 5),
            _ScoreTeamRow(name: homeName, goals: homeGoals),
            const SizedBox(height: 2),
            _ScoreTeamRow(name: awayName, goals: awayGoals),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              _MatchSummaryPill(
                icon: Icons.sports_soccer_rounded,
                label: _countLabel(ownGoals.length, 'Tor', 'Tore'),
              ),
              _MatchSummaryPill(
                icon: Icons.assistant_direction_rounded,
                label: _countLabel(assists, 'Vorlage', 'Vorlagen'),
              ),
              _MatchSummaryPill(
                icon: Icons.bolt_rounded,
                label: _countLabel(otherEvents, 'weiteres', 'weitere'),
              ),
            ],
          ),
        ),
        children: [
          Divider(color: context.appColors.outline),
          const SizedBox(height: 10),
          _MatchEventDetails(match: match),
        ],
      ),
    );
  }
}

class _MatchResultBadge extends StatelessWidget {
  const _MatchResultBadge({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'WIN' => context.appSuccess,
      'LOSS' => Colors.deepOrange,
      _ => Colors.blueGrey,
    };
    final label = switch (result) {
      'WIN' => 'S',
      'LOSS' => 'N',
      _ => 'U',
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ScoreTeamRow extends StatelessWidget {
  const _ScoreTeamRow({required this.name, required this.goals});

  final String name;
  final int goals;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$goals',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      );
}

class _MatchSummaryPill extends StatelessWidget {
  const _MatchSummaryPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.appColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.appColors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      );
}

class _MatchEventDetails extends StatelessWidget {
  const _MatchEventDetails({required this.match});

  final MatchResultStatistic match;

  @override
  Widget build(BuildContext context) {
    final ownGoals = match.events.where((event) => event.isOwnGoal).toList();
    final scorerSummary = _participantSummary(
      ownGoals.map((event) => event.scorer),
      fallback: ownGoals.isEmpty ? '–' : 'FC Teugn',
    );
    final assistSummary = _participantSummary(
      ownGoals.map((event) => event.assist),
      fallback: '–',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final summaries = [
              _ContributorBox(
                icon: Icons.sports_soccer_rounded,
                label: 'Torschützen',
                value: scorerSummary,
              ),
              _ContributorBox(
                icon: Icons.assistant_direction_rounded,
                label: 'Vorlagen',
                value: assistSummary,
              ),
            ];
            if (constraints.maxWidth < 390) {
              return Column(
                children: [
                  summaries.first,
                  const SizedBox(height: 7),
                  summaries.last,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: summaries.first),
                const SizedBox(width: 8),
                Expanded(child: summaries.last),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          'Spielereignisse',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 7),
        if (match.events.isEmpty)
          Text(
            'Für dieses Spiel wurden keine einzelnen Ereignisse erfasst.',
            style: TextStyle(color: context.appColors.textMuted),
          )
        else
          for (final event in match.events) _MatchEventRow(event: event),
      ],
    );
  }
}

class _ContributorBox extends StatelessWidget {
  const _ContributorBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: context.appWarning),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.appColors.textMuted,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MatchEventRow extends StatelessWidget {
  const _MatchEventRow({required this.event});

  final MatchStatisticEvent event;

  @override
  Widget build(BuildContext context) {
    final presentation = _eventPresentation(context, event);
    final details = <String>[
      if (event.assist != null) 'Vorlage: ${event.assist!.name}',
      if (event.comment?.trim().isNotEmpty == true) event.comment!.trim(),
      if (event.isGoal) 'Spielstand ${event.ourGoals}:${event.theirGoals}',
    ];
    final minute =
        event.elapsedSeconds <= 0 ? '–' : '${event.elapsedSeconds ~/ 60 + 1}.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 35,
            child: Text(
              '$minute Min',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.appColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: presentation.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              presentation.icon,
              size: 17,
              color: presentation.color,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
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

({IconData icon, Color color, String title}) _eventPresentation(
  BuildContext context,
  MatchStatisticEvent event,
) {
  if (event.isGoal) {
    final own = event.teamSide == 'OWN';
    return (
      icon: Icons.sports_soccer_rounded,
      color: own ? context.appSuccess : Colors.deepOrange,
      title: own
          ? 'Tor · ${event.scorer?.name ?? 'FC Teugn'}'
          : event.type == MatchStatisticEventType.ownGoal
              ? 'Eigentor'
              : 'Gegentor',
    );
  }
  return switch (event.type) {
    MatchStatisticEventType.card => (
        icon: Icons.style_rounded,
        color: context.appWarning,
        title: 'Karte',
      ),
    MatchStatisticEventType.injury => (
        icon: Icons.health_and_safety_rounded,
        color: Colors.deepOrange,
        title: 'Verletzungsunterbrechung',
      ),
    MatchStatisticEventType.substitution => (
        icon: Icons.swap_horiz_rounded,
        color: Colors.blue,
        title: 'Wechsel',
      ),
    MatchStatisticEventType.penalty => (
        icon: Icons.adjust_rounded,
        color: context.appWarning,
        title: 'Strafstoß',
      ),
    MatchStatisticEventType.interruption => (
        icon: Icons.pause_rounded,
        color: Colors.blueGrey,
        title: 'Unterbrechung',
      ),
    MatchStatisticEventType.resume => (
        icon: Icons.play_arrow_rounded,
        color: context.appSuccess,
        title: 'Fortsetzung',
      ),
    _ => (
        icon: Icons.bolt_rounded,
        color: context.appWarning,
        title: 'Spielereignis',
      ),
  };
}

String _participantSummary(
  Iterable<MatchStatisticParticipant?> participants, {
  required String fallback,
}) {
  final counts = <String, int>{};
  for (final participant
      in participants.whereType<MatchStatisticParticipant>()) {
    counts.update(participant.name, (count) => count + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return fallback;
  return counts.entries
      .map((entry) =>
          entry.value > 1 ? '${entry.key} ×${entry.value}' : entry.key)
      .join(', ');
}

String _countLabel(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

class _PlayerStatistics extends StatelessWidget {
  const _PlayerStatistics({
    required this.players,
    required this.ownOnly,
    required this.scopeLabel,
    required this.showCareer,
  });
  final List<PlayerSeasonStatistic> players;
  final bool ownOnly;
  final String scopeLabel;
  final bool showCareer;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ownOnly
                    ? 'Persönliche Übersicht · $scopeLabel'
                    : 'Kaderübersicht · $scopeLabel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                ownOnly
                    ? 'Nur Werte der zugeordneten Kinder beziehungsweise des eigenen Profils.'
                    : 'Interne Arbeitsansicht – keine öffentliche Rangliste.',
                style: TextStyle(color: context.appColors.textMuted),
              ),
              const SizedBox(height: 10),
              if (players.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child:
                      Center(child: Text('Noch keine Spielerdaten berechnet')),
                )
              else
                for (final player in players)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(player.shirtNumber?.toString() ?? 'FC'),
                    ),
                    title: Text(player.name),
                    subtitle: Text(
                      [
                        '${player.appearances} Einsätze · ${player.starts} Startelf · ${player.minutes} Min.',
                        if (showCareer && player.career != null)
                          'Gesamt: ${player.career!.appearances} Einsätze · '
                              '${player.career!.goals} Tore · '
                              '${player.career!.assists} Assists'
                              '${player.career!.cleanSheetEligible ? ' · ${player.career!.cleanSheets} Spiele zu null' : ''}',
                      ].join('\n'),
                    ),
                    trailing: Text(
                      '${player.goals} T · ${player.assists} V'
                      '${player.cleanSheetEligible ? ' · ${player.cleanSheets} ZN' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
            ],
          ),
        ),
      );
}
