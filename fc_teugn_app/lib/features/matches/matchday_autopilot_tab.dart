import 'package:flutter/material.dart';
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
        tacticalNote:
            'Vom Spieltags-Autopilot vorgeschlagen. Trainerfreigabe am Spieltag erforderlich.',
      );
      await widget.onLineupSaved(lineup);
      if (!mounted) return;
      setState(() {
        _plan = buildMatchdayAutopilotPlan(
          match: widget.match,
          allPlayers: widget.allPlayers,
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
        final wide = constraints.maxWidth >= 980;
        final content = [
          _AutopilotHero(
              plan: _plan,
              onRecalculate: () {
                setState(_recalculate);
              }),
          const SizedBox(height: 16),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _ReadinessCard(plan: _plan)),
                const SizedBox(width: 16),
                Expanded(child: _PlanSummaryCard(plan: _plan)),
              ],
            )
          else ...[
            _ReadinessCard(plan: _plan),
            const SizedBox(height: 16),
            _PlanSummaryCard(plan: _plan),
          ],
          const SizedBox(height: 16),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _StartingLineupCard(plan: _plan)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _RotationCard(plan: _plan)),
              ],
            )
          else ...[
            _StartingLineupCard(plan: _plan),
            const SizedBox(height: 16),
            _RotationCard(plan: _plan),
          ],
          const SizedBox(height: 16),
          _ApprovalCard(
            plan: _plan,
            editable: widget.editable,
            saving: _saving,
            onDraft: () => _apply(LineupStatus.draft),
            onPublish: () => _apply(LineupStatus.published),
          ),
          const SizedBox(height: 24),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF151713), Color(0xFF3C3600)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 16,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded),
                    ),
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text(
                        'FC Teugn Spieltags-Autopilot',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Bereitet Kader, positionsgerechte Startformation, faire Einsatzzeiten und Wechselplan in einem Schritt vor.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .75)),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onRecalculate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Neu berechnen'),
          ),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.plan});
  final MatchdayAutopilotPlan plan;

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: 'Vorbereitungscheck',
        subtitle:
            '${plan.readyChecks} von ${plan.readiness.length} Punkten bereit',
        icon: Icons.fact_check_outlined,
        child: Column(
          children: [
            for (final item in plan.readiness)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.ready
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: item.ready
                      ? const Color(0xFF16845B)
                      : const Color(0xFF9A7300),
                ),
                title: Text(item.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(item.detail),
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
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Metric(value: '${plan.players.length}', label: 'Spieler'),
            _Metric(value: '${plan.benchCount}', label: 'Bank'),
            _Metric(value: '${plan.substitutions.length}', label: 'Wechsel'),
            _Metric(value: '±${plan.minuteSpread}', label: 'Minuten'),
            _Metric(
              value: '${plan.positionMatches}/${plan.positions.length}',
              label: 'Positionsfit',
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
        title: 'Vorgeschlagene Startformation',
        subtitle:
            'Positionsdaten und bisherige Einsatzzeit werden berücksichtigt.',
        icon: Icons.dashboard_customize_rounded,
        child: plan.positions.isEmpty
            ? const Text(
                'Für eine Aufstellung sind noch nicht genügend Spieler vorhanden.')
            : Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final position in plan.positions)
                    Container(
                      width: 210,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            child: Text(
                                position.player.shirtNumber?.toString() ??
                                    'FC'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        position.player.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    if (position.isCaptain) ...[
                                      const SizedBox(width: 5),
                                      const CaptainBadge(),
                                    ],
                                  ],
                                ),
                                Text(
                                    '${position.positionCode} · ${plan.plannedMinutes[position.player.id] ?? 0} Min.'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
}

class _RotationCard extends StatelessWidget {
  const _RotationCard({required this.plan});
  final MatchdayAutopilotPlan plan;

  @override
  Widget build(BuildContext context) {
    final names = {for (final player in plan.players) player.id: player.name};
    return _SectionCard(
      title: 'Fairer Wechselplan',
      subtitle: plan.substitutions.isEmpty
          ? 'Keine Ersatzspieler – aktuell sind keine Wechsel nötig.'
          : 'Vorschlag je Spielabschnitt, jederzeit manuell änderbar.',
      icon: Icons.sync_alt_rounded,
      child: plan.substitutions.isEmpty
          ? const SizedBox.shrink()
          : Column(
              children: [
                for (final substitution in plan.substitutions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child:
                          Text('${substitution.period}.${substitution.minute}'),
                    ),
                    title: Text(
                      '${names[substitution.playerInId] ?? 'Spieler'} rein',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                        '${names[substitution.playerOutId] ?? 'Spieler'} raus · ${substitution.note ?? ''}'),
                  ),
              ],
            ),
    );
  }
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
  Widget build(BuildContext context) => _SectionCard(
        title: 'Trainerentscheidung',
        subtitle:
            'Der Autopilot macht einen Vorschlag. Die sportliche Entscheidung bleibt immer beim Trainerteam.',
        icon: Icons.verified_user_outlined,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            if (!plan.canApply)
              const Text(
                  'Bitte zuerst genügend aktive Spieler im Kader bereitstellen.'),
            if (editable) ...[
              OutlinedButton.icon(
                onPressed: saving || !plan.canApply ? null : onDraft,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Als Entwurf übernehmen'),
              ),
              FilledButton.icon(
                onPressed: saving || !plan.canApply ? null : onPublish,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_rounded),
                label: const Text('Übernehmen & veröffentlichen'),
              ),
            ],
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: 105,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}
