import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/matchday_autopilot.dart';
import '../../core/models/matchday.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../../core/widgets/captain_badge.dart';

class MatchdayAutopilotTab extends ConsumerStatefulWidget {
  const MatchdayAutopilotTab({
    required this.match,
    required this.allPlayers,
    required this.editable,
    required this.onSquadSaved,
    required this.onLineupSaved,
    super.key,
  });

  final MatchdayModel match;
  final List<PlayerModel> allPlayers;
  final bool editable;
  final Future<void> Function(MatchSquadModel squad) onSquadSaved;
  final Future<void> Function(LineupModel lineup) onLineupSaved;

  @override
  ConsumerState<MatchdayAutopilotTab> createState() =>
      _MatchdayAutopilotTabState();
}

class _MatchdayAutopilotTabState extends ConsumerState<MatchdayAutopilotTab> {
  late MatchdayAutopilotPlan _plan;
  AutopilotStrategy _strategy = AutopilotStrategy.balanced;
  bool _restoreStartersToStartingPositions = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _recalculate();
  }

  @override
  void didUpdateWidget(covariant MatchdayAutopilotTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match != widget.match ||
        oldWidget.allPlayers != widget.allPlayers) {
      _recalculate();
    }
  }

  void _recalculate() {
    _plan = buildMatchdayAutopilotPlan(
      match: widget.match,
      allPlayers: widget.allPlayers,
      strategy: _strategy,
      restoreStartersToStartingPositions: _restoreStartersToStartingPositions,
    );
  }

  Future<void> _apply(LineupStatus status) async {
    if (!_plan.canApply || _saving) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(repositoryProvider);
      final existingMembers = widget.match.squad?.members ?? const [];
      final existingById = {
        for (final member in existingMembers) member.player.id: member,
      };
      final playerIds = _plan.players.map((player) => player.id).toSet();
      final members = <({
        String playerId,
        NominationStatus status,
        int? plannedMinutes,
      })>[
        for (final player in _plan.players)
          (
            playerId: player.id,
            status: NominationStatus.nominated,
            plannedMinutes: _plan.plannedMinutes[player.id],
          ),
        for (final member in existingMembers)
          if (!playerIds.contains(member.player.id))
            (
              playerId: member.player.id,
              status: existingById[member.player.id]!.status,
              plannedMinutes: existingById[member.player.id]!.plannedMinutes,
            ),
      ];
      final squad = await repository.saveMatchSquad(
        eventId: widget.match.id,
        formation: _plan.formation,
        members: members,
      );
      await widget.onSquadSaved(squad);
      final lineup = await repository.saveLineup(
        eventId: widget.match.id,
        formation: _plan.formation,
        fieldSize: _plan.fieldSize,
        status: status,
        positions: _plan.positions,
        plannedSubstitutions: _plan.substitutions,
        tacticalNote: 'Vom Spieltags-Autopilot vorgeschlagen · '
            '${_plan.strategy.label}'
            '${_plan.restoreStartersToStartingPositions ? ' · Stammplätze wiederherstellen' : ''}. '
            'Trainerfreigabe am Spieltag erforderlich.',
      );
      await widget.onLineupSaved(lineup);
      if (!mounted) return;
      setState(() {
        _plan = buildMatchdayAutopilotPlan(
          match: widget.match,
          allPlayers: widget.allPlayers,
          strategy: _strategy,
          restoreStartersToStartingPositions:
              _restoreStartersToStartingPositions,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == LineupStatus.published
                ? 'Autopilot-Plan wurde gespeichert und veröffentlicht.'
                : 'Autopilot-Plan wurde als Entwurf gespeichert.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Der Autopilot-Plan konnte nicht gespeichert werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final content = [
          _AutopilotHero(
            plan: _plan,
            onRecalculate: () => setState(_recalculate),
          ),
          const SizedBox(height: 10),
          _StrategySelector(
            value: _strategy,
            restoreStartersToStartingPositions:
                _restoreStartersToStartingPositions,
            onChanged: (value) {
              setState(() {
                _strategy = value;
                _recalculate();
              });
            },
            onRestoreStartersChanged: (value) {
              setState(() {
                _restoreStartersToStartingPositions = value;
                _recalculate();
              });
            },
          ),
          const SizedBox(height: 10),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: _PlanSummaryCard(plan: _plan)),
                const SizedBox(width: 10),
                Expanded(flex: 5, child: _ReadinessCard(plan: _plan)),
              ],
            )
          else ...[
            _PlanSummaryCard(plan: _plan),
            const SizedBox(height: 10),
            _ReadinessCard(plan: _plan),
          ],
          const SizedBox(height: 10),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _StartingLineupCard(plan: _plan)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _RotationCard(plan: _plan)),
              ],
            )
          else ...[
            _StartingLineupCard(plan: _plan),
            const SizedBox(height: 10),
            _RotationCard(plan: _plan),
          ],
          const SizedBox(height: 10),
          _ApprovalCard(
            plan: _plan,
            editable: widget.editable,
            saving: _saving,
            onDraft: () => _apply(LineupStatus.draft),
            onPublish: () => _apply(LineupStatus.published),
          ),
          const SizedBox(height: 16),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(children: content),
        );
      },
    );
  }
}

class _AutopilotHero extends StatelessWidget {
  const _AutopilotHero({required this.plan, required this.onRecalculate});

  final MatchdayAutopilotPlan plan;
  final VoidCallback onRecalculate;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final ready = plan.readyChecks;
    final total = plan.readiness.length;
    final progress = total == 0 ? 0.0 : ready / total;
    final missing = total - ready;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF151713), Color(0xFF3C3600)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.black,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spieltags-Autopilot',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 19 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      plan.canApply
                          ? 'Dein Spielplan ist vorbereitet'
                          : 'Noch nicht einsatzbereit',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRecalculate,
                tooltip: 'Neu berechnen',
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: .1),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'BEREITSCHAFT',
                style: TextStyle(
                  color: AppColors.yellow,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const Spacer(),
              Text(
                '$ready/$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(
                missing == 0 ? AppColors.success : AppColors.yellow,
              ),
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _HeroChip(
                icon: Icons.account_tree_rounded,
                label: plan.formation,
              ),
              _HeroChip(
                icon: Icons.groups_rounded,
                label: '${plan.fieldSize} gegen ${plan.fieldSize}',
              ),
              _HeroChip(
                icon: Icons.tune_rounded,
                label: plan.strategy.label,
              ),
              if (plan.restoreStartersToStartingPositions)
                const _HeroChip(
                  icon: Icons.settings_backup_restore_rounded,
                  label: 'Stammplätze aktiv',
                ),
              _HeroChip(
                icon: missing == 0
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                label: missing == 0 ? 'Bereit' : '$missing Punkte offen',
                highlighted: missing > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StrategySelector extends StatelessWidget {
  const _StrategySelector({
    required this.value,
    required this.restoreStartersToStartingPositions,
    required this.onChanged,
    required this.onRestoreStartersChanged,
  });

  final AutopilotStrategy value;
  final bool restoreStartersToStartingPositions;
  final ValueChanged<AutopilotStrategy> onChanged;
  final ValueChanged<bool> onRestoreStartersChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, color: AppColors.blue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Wechselstrategie wählen',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value.description,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final segments = SegmentedButton<AutopilotStrategy>(
                    key: const ValueKey('autopilot-strategy-selector'),
                    showSelectedIcon: true,
                    multiSelectionEnabled: false,
                    selected: {value},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) onChanged(selection.first);
                    },
                    segments: [
                      for (final strategy in AutopilotStrategy.values)
                        ButtonSegment(
                          value: strategy,
                          icon: Icon(_strategyIcon(strategy), size: 18),
                          label: Text(strategy.label),
                        ),
                    ],
                  );
                  if (!compact) return segments;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: segments,
                  );
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: value == AutopilotStrategy.positionFidelity
                    ? Padding(
                        key: const ValueKey(
                            'restore-starters-to-starting-positions'),
                        padding: const EdgeInsets.only(top: 12),
                        child: Material(
                          color: AppColors.yellowSoft.withValues(alpha: .55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppColors.line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SwitchListTile.adaptive(
                            key: const ValueKey(
                                'autopilot-restore-starters-switch'),
                            value: restoreStartersToStartingPositions,
                            onChanged: onRestoreStartersChanged,
                            secondary: const Icon(
                              Icons.settings_backup_restore_rounded,
                              color: AppColors.gold,
                            ),
                            title: const Text(
                              'Stammspieler auf Stammplätze zurückführen',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Bei späteren Wechseln kehren Startspieler bevorzugt auf ihren ursprünglichen Platz in der Startelf zurück.',
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
}

IconData _strategyIcon(AutopilotStrategy strategy) => switch (strategy) {
      AutopilotStrategy.balanced => Icons.balance_rounded,
      AutopilotStrategy.playingTime => Icons.timer_outlined,
      AutopilotStrategy.positionFidelity => Icons.account_tree_outlined,
    };

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.yellow.withValues(alpha: .2)
              : Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: highlighted ? AppColors.yellow : Colors.white,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: highlighted ? AppColors.yellow : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _ReadinessCard extends StatefulWidget {
  const _ReadinessCard({required this.plan});
  final MatchdayAutopilotPlan plan;

  @override
  State<_ReadinessCard> createState() => _ReadinessCardState();
}

class _ReadinessCardState extends State<_ReadinessCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final missing = plan.readiness.where((item) => !item.ready).toList();
    final visible = _showAll ? plan.readiness : missing;
    return _SectionCard(
      title: 'Vorbereitungscheck',
      subtitle: missing.isEmpty
          ? 'Alle Angaben sind vollständig'
          : '${missing.length} Punkte brauchen Aufmerksamkeit',
      icon: missing.isEmpty
          ? Icons.verified_rounded
          : Icons.warning_amber_rounded,
      trailing: _StatusPill(
        label: '${plan.readyChecks}/${plan.readiness.length}',
        ready: missing.isEmpty,
      ),
      child: Column(
        children: [
          if (visible.isEmpty)
            const _ReadyState()
          else
            for (var index = 0; index < visible.length; index++) ...[
              _ReadinessRow(item: visible[index]),
              if (index < visible.length - 1)
                const Divider(height: 1, indent: 37),
            ],
          if (missing.length != plan.readiness.length) ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showAll = !_showAll),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: Icon(
                  _showAll
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _showAll ? 'Nur offene Punkte' : 'Alle Checks anzeigen',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.item});

  final AutopilotReadinessItem item;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              item.ready
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: item.ready ? AppColors.success : AppColors.gold,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ReadyState extends StatelessWidget {
  const _ReadyState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bereit für die Trainerfreigabe',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.plan});
  final MatchdayAutopilotPlan plan;

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: 'Plan auf einen Blick',
        subtitle:
            '${plan.formation} · ${plan.fieldSize} gegen ${plan.fieldSize}',
        icon: Icons.insights_rounded,
        trailing: _StatusPill(
          label: plan.canApply ? 'Plan bereit' : 'Unvollständig',
          ready: plan.canApply,
        ),
        child: _MetricGrid(
          metrics: [
            ('${plan.players.length}', 'Spieler'),
            ('${plan.benchCount}', 'Bank'),
            ('${plan.substitutions.length}', 'Wechsel'),
            ('±${plan.minuteSpread}', 'Minuten'),
            (
              '${plan.positionMatches}/${plan.positions.length}',
              'Positionsfit'
            ),
          ],
        ),
      );
}

class _StartingLineupCard extends StatelessWidget {
  const _StartingLineupCard({required this.plan});
  final MatchdayAutopilotPlan plan;

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: 'Startformation',
        subtitle: 'Positionsgerecht und nach bisheriger Einsatzzeit',
        icon: Icons.dashboard_customize_rounded,
        trailing: _StatusPill(
          label: plan.formation,
          ready: plan.positions.isNotEmpty,
        ),
        child: plan.positions.isEmpty
            ? const Text(
                'Für eine Aufstellung sind noch nicht genügend Spieler vorhanden.')
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700
                      ? 4
                      : constraints.maxWidth >= 460
                          ? 3
                          : 2;
                  const gap = 8.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final position in plan.positions)
                        SizedBox(
                          width: width,
                          child: _LineupPlayerTile(
                            position: position,
                            minutes:
                                plan.plannedMinutes[position.player.id] ?? 0,
                          ),
                        ),
                    ],
                  );
                },
              ),
      );
}

class _LineupPlayerTile extends StatelessWidget {
  const _LineupPlayerTile({
    required this.position,
    required this.minutes,
  });

  final LineupPositionModel position;
  final int minutes;

  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: position.isCaptain ? AppColors.gold : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: position.isGoalkeeper
                  ? AppColors.yellow
                  : AppColors.yellowSoft,
              foregroundColor: AppColors.black,
              child: Text(
                position.player.shirtNumber?.toString() ?? 'FC',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          position.player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (position.isCaptain) ...[
                        const SizedBox(width: 3),
                        const CaptainBadge(),
                      ],
                    ],
                  ),
                  Text(
                    '${position.positionCode} · $minutes Min.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RotationCard extends StatefulWidget {
  const _RotationCard({required this.plan});
  final MatchdayAutopilotPlan plan;

  @override
  State<_RotationCard> createState() => _RotationCardState();
}

class _RotationCardState extends State<_RotationCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final names = {for (final player in plan.players) player.id: player.name};
    final visible = _showAll
        ? plan.substitutions
        : plan.substitutions.take(4).toList(growable: false);
    return _SectionCard(
      title: 'Fairer Wechselplan',
      subtitle: plan.substitutions.isEmpty
          ? 'Keine Wechsel erforderlich'
          : 'Positionsnah und fair verteilt',
      icon: Icons.sync_alt_rounded,
      trailing: _StatusPill(
        label: '${plan.substitutions.length} Wechsel',
        ready: true,
      ),
      child: plan.substitutions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(Icons.event_available_rounded, color: AppColors.success),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Alle nominierten Spieler starten auf dem Feld.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  _SubstitutionRow(
                    substitution: visible[index],
                    playerIn: names[visible[index].playerInId] ?? 'Spieler',
                    playerOut: names[visible[index].playerOutId] ?? 'Spieler',
                  ),
                  if (index < visible.length - 1)
                    const Divider(height: 1, indent: 41),
                ],
                if (plan.substitutions.length > 4) ...[
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      icon: Icon(
                        _showAll
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _showAll
                            ? 'Weniger anzeigen'
                            : 'Alle ${plan.substitutions.length} Wechsel',
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SubstitutionRow extends StatelessWidget {
  const _SubstitutionRow({
    required this.substitution,
    required this.playerIn,
    required this.playerOut,
  });

  final PlannedSubstitutionModel substitution;
  final String playerIn;
  final String playerOut;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 33,
              height: 33,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.yellowSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${substitution.period}.${substitution.minute}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      playerIn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(Icons.swap_horiz_rounded,
                        color: AppColors.muted, size: 17),
                  ),
                  Expanded(
                    child: Text(
                      playerOut,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.plan,
    required this.editable,
    required this.saving,
    required this.onDraft,
    required this.onPublish,
  });
  final MatchdayAutopilotPlan plan;
  final bool editable;
  final bool saving;
  final VoidCallback onDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    return _SectionCard(
      title: 'Trainerfreigabe',
      subtitle: plan.canApply
          ? 'Vorschlag prüfen und übernehmen'
          : 'Noch nicht freigabebereit',
      icon: Icons.verified_user_outlined,
      trailing: _StatusPill(
        label: plan.canApply ? 'Bereit' : 'Gesperrt',
        ready: plan.canApply,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!plan.canApply)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Bitte zuerst genügend aktive Spieler bereitstellen und offene Angaben ergänzen.',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Die sportliche Entscheidung bleibt beim Trainerteam. Der Vorschlag kann anschließend in der Aufstellung geändert werden.',
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (editable)
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 520;
                final draft = OutlinedButton.icon(
                  onPressed: saving || !plan.canApply ? null : onDraft,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Entwurf speichern'),
                );
                final publish = FilledButton.icon(
                  onPressed: saving || !plan.canApply ? null : onPublish,
                  icon: saving
                      ? const LogoLoadingIndicator(
                          size: 22,
                          semanticsLabel: 'Aufstellung wird gespeichert',
                        )
                      : const Icon(Icons.publish_rounded, size: 18),
                  label: const Text('Übernehmen & veröffentlichen'),
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 44, child: publish),
                      const SizedBox(height: 7),
                      SizedBox(height: 42, child: draft),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    draft,
                    const SizedBox(width: 9),
                    publish,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 620 ? 5 : 3;
          const gap = 7.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final metric in metrics)
                Container(
                  width: width,
                  height: 57,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        metric.$1,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metric.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (ready ? AppColors.success : AppColors.gold)
              .withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: ready ? AppColors.success : AppColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.yellowSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.gold, size: 19),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 7),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}
