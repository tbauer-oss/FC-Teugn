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
        teamId = _selectedTeamId ?? organization.currentTeam.id;
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
    final selectedTeamId = canSelectTeam
        ? (_selectedTeamId ?? registeredTeamId)
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
                      style: const TextStyle(color: AppColors.muted),
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
                  color: AppColors.teal,
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
                  color: AppColors.orange,
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
          labelText: 'Mannschaft',
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
        labelText: 'Mannschaft',
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
    this.color = AppColors.blue,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: compact ? 18 : 20,
                  backgroundColor: color.withValues(alpha: .1),
                  child: Icon(icon, color: color, size: compact ? 20 : 24),
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
                        style: const TextStyle(color: AppColors.muted),
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
              const Icon(Icons.timeline_rounded, color: AppColors.blue),
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
                      'WIN' => AppColors.teal,
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
              label: 'Mannschaftsschnitt',
              value: data.teamAverage == null
                  ? '–'
                  : '${data.teamAverage!.toStringAsFixed(1)} / 10',
            ),
            _PerformanceMetric(
              compact: compact,
              label: 'Bewertete Spiele',
              value: '${data.ratedMatches}',
            ),
            _PerformanceMetric(
              compact: compact,
              label: 'Noch offen',
              value: '${data.unratedMatches}',
            ),
          ];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 12 : 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.navy, AppColors.blue],
                    ),
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.insights_rounded,
                                  color: Colors.white,
                                  size: 25,
                                ),
                                SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Leistungszentrum · trainerintern',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        'Entwicklung erkennen – ohne Rangliste.',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
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
                        )
                      : Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(
                              Icons.insights_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 310),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Leistungszentrum · trainerintern',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'Entwicklung erkennen – ohne öffentliche Rangliste.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            ...metrics,
                          ],
                        ),
                ),
                Padding(
                  padding: EdgeInsets.all(compact ? 11 : 18),
                  child: Column(
                    children: [
                      if (data.players.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 6 : 18,
                          ),
                          child: const Text(
                            'Noch keine Spielerbewertungen in diesem Zeitraum.',
                          ),
                        )
                      else
                        for (final player in data.players)
                          _PlayerPerformanceRow(player: player),
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
        ? AppColors.teal
        : player.trend < -.15
            ? Colors.deepOrange
            : AppColors.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(child: Text(player.shirtNumber?.toString() ?? 'FC')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(
                  '${player.ratedMatches} Bewertungen · zuletzt ${player.lastScore ?? '–'} / 10',
                  style: const TextStyle(color: AppColors.muted),
                ),
                if (player.recent.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final recent in player.recent)
                        Tooltip(
                          message:
                              '${recent.opponent} · ${recent.startAt.day}.${recent.startAt.month}.${recent.startAt.year}',
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${recent.score}'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                player.average.toStringAsFixed(1),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              Icon(trendIcon, color: trendColor),
            ],
          ),
        ],
      ),
    );
  }
}

class _MatchHistory extends StatelessWidget {
  const _MatchHistory({required this.matches, required this.scopeLabel});
  final List<MatchResultStatistic> matches;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ergebnisse · $scopeLabel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child:
                      Center(child: Text('Noch keine Ergebnisse im Zeitraum')),
                )
              else
                for (final match in matches.take(10))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: match.result == 'WIN'
                          ? AppColors.teal.withValues(alpha: .12)
                          : match.result == 'LOSS'
                              ? Colors.deepOrange.withValues(alpha: .12)
                              : Colors.blueGrey.withValues(alpha: .12),
                      child: Text(
                        match.result == 'WIN'
                            ? 'S'
                            : match.result == 'LOSS'
                                ? 'N'
                                : 'U',
                      ),
                    ),
                    title: Text('${match.isHome ? '' : '@ '}${match.opponent}'),
                    subtitle: Text(match.competition ?? 'Spiel'),
                    trailing: Text(
                      '${match.ourGoals}:${match.theirGoals}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
            ],
          ),
        ),
      );
}

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
                style: const TextStyle(color: AppColors.muted),
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
