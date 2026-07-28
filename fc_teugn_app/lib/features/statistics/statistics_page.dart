import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/statistics.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  StatisticsOverview? _overview;
  bool _loading = true;
  String? _error;
  String _range = 'Saison';

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
      final now = DateTime.now();
      final from = switch (_range) {
        '90 Tage' => now.subtract(const Duration(days: 90)),
        'Jahr' => DateTime(now.year),
        _ => DateTime(now.month >= 7 ? now.year : now.year - 1, 7),
      };
      final overview = await ref.read(repositoryProvider).statistics(
            from: from,
            to: now.add(const Duration(days: 1)),
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
        subtitle: 'Automatisch aus Spielen, Aufstellungen und Liveticker berechnet.',
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
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Saison', label: Text('Saison')),
                  ButtonSegment(value: '90 Tage', label: Text('90 Tage')),
                  ButtonSegment(value: 'Jahr', label: Text('Kalenderjahr')),
                ],
                selected: {_range},
                onSelectionChanged: (value) {
                  _range = value.first;
                  _load();
                },
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: _load,
              tooltip: 'Neu laden',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Spiele',
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
            final matchList = _MatchHistory(matches: overview.matches);
            final playerList = _PlayerStatistics(
              players: overview.players,
              ownOnly: overview.individualScope == 'OWN_PLAYERS',
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
                    Text(value, style: Theme.of(context).textTheme.headlineSmall),
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
              Text('Letzte Form', style: Theme.of(context).textTheme.titleMedium),
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
                        result == 'WIN' ? 'S' : result == 'LOSS' ? 'N' : 'U',
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
  const _MatchHistory({required this.matches});
  final List<MatchResultStatistic> matches;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ergebnisse', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('Noch keine Ergebnisse im Zeitraum')),
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
                        match.result == 'WIN' ? 'S' : match.result == 'LOSS' ? 'N' : 'U',
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
  const _PlayerStatistics({required this.players, required this.ownOnly});
  final List<PlayerSeasonStatistic> players;
  final bool ownOnly;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ownOnly ? 'Persönliche Übersicht' : 'Kaderübersicht',
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
                  child: Center(child: Text('Noch keine Spielerdaten berechnet')),
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
                      '${player.appearances} Einsätze · ${player.starts} Startelf · ${player.minutes} Min.',
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
