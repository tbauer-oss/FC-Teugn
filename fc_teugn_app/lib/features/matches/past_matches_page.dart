import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/loading/loading_widgets.dart';
import '../../core/models/organization.dart';
import '../../core/models/statistics.dart';
import '../../core/providers.dart';
import '../../core/role_permissions.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import '../statistics/statistics_page.dart';

class PastMatchesPage extends ConsumerStatefulWidget {
  const PastMatchesPage({super.key, required this.staffView});

  final bool staffView;

  @override
  ConsumerState<PastMatchesPage> createState() => _PastMatchesPageState();
}

class _PastMatchesPageState extends ConsumerState<PastMatchesPage> {
  static const _allSeasons = '__all_seasons__';

  StatisticsOverview? _overview;
  String? _selectedTeamId;
  String? _seasonId;
  String? _error;
  bool _loading = true;

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
        _error = 'Die vergangenen Spiele konnten nicht geladen werden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'Vergangene Spiele',
        subtitle: 'Ergebnisse, Torschützen, Vorlagen und Spielereignisse.',
        denseMobileHeader: true,
        action: IconButton(
          tooltip: 'Zur Spieleübersicht',
          onPressed: () => context.go(
            widget.staffView ? '/trainer/matches' : '/parent/matches',
          ),
          icon: const Icon(Icons.close_rounded),
        ),
        child: _loading
            ? const Center(
                child: LogoLoadingPanel(
                  message: 'Vergangene Spiele werden geladen …',
                ),
              )
            : _error != null || _overview == null
                ? EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Spielhistorie nicht erreichbar',
                    message: _error!,
                  )
                : _content(context, _overview!),
      );

  Widget _content(BuildContext context, StatisticsOverview overview) {
    final user = ref.watch(authProvider).user;
    final organization = ref.watch(organizationProvider).valueOrNull;
    final canSelectTeam = user != null && canSelectStatisticsTeam(user.role);
    final teams = _teamOptions(organization);
    final selectedTeamId = canSelectTeam && organization != null
        ? resolveStatisticsPageTeamId(
            registeredTeamId: user.teamId,
            currentTeamId: organization.currentTeam.id,
            workingTeamIds: organization.workingContext.teamIds,
            includeAllTeams: organization.workingContext.includeAllTeams,
            selectedTeamId: _selectedTeamId,
          )
        : user?.teamId;
    final selectedTeam = _findTeam(teams, selectedTeamId);
    final teamLabel = selectedTeam?.displayName ??
        (overview.matches.isEmpty
            ? 'Zugeordnete Mannschaft'
            : overview.matches.first.teamName);
    final seasonLabel = overview.selectedSeason?.name ?? 'Alle Saisons';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HistorySummary(
          teamLabel: teamLabel,
          seasonLabel: seasonLabel,
          statistics: overview.team,
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final teamSelector = canSelectTeam && teams.isNotEmpty
                    ? DropdownButtonFormField<String>(
                        key: ValueKey('past-matches-team-$selectedTeamId'),
                        initialValue: selectedTeamId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Jugend / Mannschaft',
                          prefixIcon: Icon(Icons.groups_rounded),
                        ),
                        items: [
                          for (final team in teams)
                            DropdownMenuItem(
                              value: team.id,
                              child: Text(
                                team.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null || value == selectedTeamId) return;
                          setState(() {
                            _selectedTeamId = value;
                            _seasonId = null;
                          });
                          _load();
                        },
                      )
                    : InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Jugend / Mannschaft',
                          prefixIcon: Icon(Icons.groups_rounded),
                        ),
                        child: Text(
                          teamLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      );
                final seasonSelector = DropdownButtonFormField<String>(
                  key: ValueKey(
                      'past-matches-season-${_seasonId ?? _allSeasons}'),
                  initialValue: _seasonId ?? _allSeasons,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Saison',
                    prefixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: _allSeasons,
                      child: Text('Alle Saisons'),
                    ),
                    for (final season in overview.seasons)
                      DropdownMenuItem(
                        value: season.id,
                        child: Text(
                          '${season.name}${season.isActive ? ' · aktiv' : ''}',
                          overflow: TextOverflow.ellipsis,
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
                final reload = IconButton.filledTonal(
                  tooltip: 'Neu laden',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      teamSelector,
                      const SizedBox(height: 10),
                      seasonSelector,
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: reload),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: teamSelector),
                    const SizedBox(width: 10),
                    Expanded(child: seasonSelector),
                    const SizedBox(width: 8),
                    reload,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Spiele · $seasonLabel',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          'Spiel aufklappen für Tore, Vorlagen und den zeitlichen Verlauf.',
          style: TextStyle(color: context.appColors.textMuted),
        ),
        const SizedBox(height: 10),
        MatchHistory(
          matches: overview.matches,
          scopeLabel: seasonLabel,
          showHeader: false,
          onOpenMatch: (matchId) => context.push(
            widget.staffView
                ? '/trainer/matches/$matchId'
                : '/parent/matches/$matchId',
          ),
        ),
      ],
    );
  }

  TeamSummary? _findTeam(List<TeamSummary> teams, String? teamId) {
    for (final team in teams) {
      if (team.id == teamId) return team;
    }
    return null;
  }

  List<TeamSummary> _teamOptions(OrganizationContext? organization) {
    if (organization == null) return const [];
    final values = <TeamSummary>[
      organization.currentTeam,
      ...organization.teams,
    ];
    final seen = <String>{};
    return values.where((team) => seen.add(team.id)).toList();
  }
}

class PastMatchesEntryCard extends StatelessWidget {
  const PastMatchesEntryCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('past-matches-entry'),
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.history_rounded,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vergangene Spiele',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ergebnisse, Torschützen, Vorlagen & Ereignisse',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onPrimaryContainer
                                .withValues(alpha: .76),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({
    required this.teamLabel,
    required this.seasonLabel,
    required this.statistics,
  });

  final String teamLabel;
  final String seasonLabel;
  final TeamStatistics statistics;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.gold],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer_rounded, color: AppColors.yellow),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  teamLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text(
                seasonLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(label: '${statistics.matches} Spiele'),
              _SummaryPill(label: '${statistics.wins} Siege'),
              _SummaryPill(label: '${statistics.draws} Remis'),
              _SummaryPill(label: '${statistics.losses} Niederlagen'),
              _SummaryPill(
                label: '${statistics.goalsFor}:${statistics.goalsAgainst} Tore',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}
