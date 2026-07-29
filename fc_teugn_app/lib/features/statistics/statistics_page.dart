import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/models/statistics.dart';
import '../../core/models/user.dart';
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
      final teamId = canSelectStatisticsTeam(user.role)
          ? (_selectedTeamId ?? user.teamId)
          : user.teamId;
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
            ? const Center(child: CircularProgressIndicator())
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
    final organization = ref.watch(organizationProvider).value;
    final canSelectTeam =
        user != null && canSelectStatisticsTeam(user.role);
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
                  key: ValueKey('statistics-season-${_seasonId ?? _allSeasons}'),
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
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Spiele · $selectedLabel',
              value: '${team.matches}',
              icon: Icons.sports_soccer_rounded,
            ),
            _MetricCard(
              label: 'Siege',
              value: '${team.wins}',
              icon: Icons.emoji_events_rounded,
              color: AppColors.teal,
            ),
            _MetricCard(
              label: 'Siegquote',
              value: '${team.winRate.toStringAsFixed(1)} %',
              icon: Icons.trending_up_rounded,
            ),
            _MetricCard(
              label: 'Tore',
              value: '${team.goalsFor}:${team.goalsAgainst}',
              icon: Icons.scoreboard_rounded,
              color: AppColors.orange,
            ),
            _MetricCard(
              label: 'Tore/Spiel',
              value: team.goalsPerMatch.toStringAsFixed(2),
              icon: Icons.analytics_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _FormCard(form: team.form),
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
    this.color = AppColors.blue,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .1),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text(label, style: const TextStyle(color: AppColors.muted)),
                  ],
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
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.timeline_rounded, color: AppColors.blue),
              const SizedBox(width: 12),
              Text('Letzte Form',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (form.isEmpty)
                const Text('Noch keine beendeten Spiele')
              else
                for (final result in form)
                  Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: CircleAvatar(
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
                  ),
            ],
          ),
        ),
      );
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
                              '${player.career!.assists} Assists',
                      ].join('\n'),
                    ),
                    trailing: Text(
                      '${player.goals} T · ${player.assists} V',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
            ],
          ),
        ),
      );
}
