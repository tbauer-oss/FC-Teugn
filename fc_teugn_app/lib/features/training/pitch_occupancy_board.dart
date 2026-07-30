import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models/pitch_occupancy.dart';
import '../shared/page_scaffold.dart';

class PitchOccupancyBoard extends StatelessWidget {
  const PitchOccupancyBoard({
    required this.plan,
    this.onConflictApproval,
    super.key,
  });

  final PitchOccupancyPlan plan;
  final void Function(PitchOccupancyConflict conflict, bool approved)?
      onConflictApproval;

  @override
  Widget build(BuildContext context) {
    final slots = plan.slots;
    final conflicts = plan.conflicts;
    final openConflicts =
        conflicts.where((conflict) => !conflict.approved).toList();
    final conflictSlots = {
      for (final conflict in openConflicts) ...[
        conflict.first,
        conflict.second,
      ],
    };
    final approvedSlots = {
      for (final conflict in conflicts.where((item) => item.approved)) ...[
        conflict.first,
        conflict.second,
      ],
    };
    final jointTrainingLabels = <String>{
      for (final team in plan.teams)
        for (final partnerId in team.trainingPartnerIds)
          if (plan.teams.any((candidate) => candidate.id == partnerId))
            ([
              team.label,
              plan.teams.firstWhere((item) => item.id == partnerId).label
            ]..sort())
                .join(' + '),
    }.toList()
      ..sort();
    final unparsedCount = plan.teams.fold<int>(
      0,
      (sum, team) =>
          sum +
          team.trainingTimes.length +
          team.matchdayTimes.length -
          team.slots.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlanHeader(
          plan: plan,
          slotCount: slots.length,
          conflictCount: openConflicts.length,
          matchdayCount: slots
              .where((slot) => slot.kind == PitchOccupancySlotKind.matchday)
              .length,
        ),
        const SizedBox(height: 10),
        if (openConflicts.isNotEmpty)
          _Notice(
            icon: Icons.warning_amber_rounded,
            color: Colors.deepOrange,
            title: 'Mögliche Platzüberschneidung',
            message:
                '${openConflicts.length} Überschneidung(en) sind noch offen. Berechtigte Leitungen können abgestimmte Belegungen bestätigen.',
          ),
        if (openConflicts.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final conflict in openConflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ConflictRow(
                conflict: conflict,
                canManage: plan.canManageOccupancy,
                onChanged: onConflictApproval,
              ),
            ),
        ],
        if (conflicts.any((conflict) => conflict.approved)) ...[
          const SizedBox(height: 8),
          _Notice(
            icon: Icons.verified_rounded,
            color: AppColors.teal,
            title: 'Abgestimmte Überschneidungen',
            message:
                '${conflicts.where((conflict) => conflict.approved).length} Überschneidung(en) wurden bestätigt und gelten nicht mehr als Konflikt.',
          ),
          if (plan.canManageOccupancy)
            for (final conflict
                in conflicts.where((conflict) => conflict.approved))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _ConflictRow(
                  conflict: conflict,
                  canManage: true,
                  onChanged: onConflictApproval,
                ),
              ),
        ],
        if (jointTrainingLabels.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Notice(
            icon: Icons.groups_2_rounded,
            color: AppColors.blue,
            title: 'Gemeinsame Trainings',
            message: jointTrainingLabels.join(' · '),
          ),
        ],
        if (unparsedCount > 0)
          _Notice(
            icon: Icons.edit_calendar_outlined,
            color: AppColors.blue,
            title: 'Zeitangaben ergänzen',
            message:
                '$unparsedCount Einträge konnten nicht eingeordnet werden. Format: „Dienstag 17:00–18:30“.',
          ),
        if (unparsedCount > 0) const SizedBox(height: 12),
        if (slots.isEmpty)
          EmptyState(
            icon: plan.indoor
                ? Icons.sports_handball_outlined
                : Icons.stadium_outlined,
            title: plan.indoor
                ? 'Noch keine Hallenbelegung hinterlegt'
                : 'Noch keine Platzbelegung hinterlegt',
            message: plan.indoor
                ? 'Sobald Hallenzeiten bei den Mannschaften gepflegt sind, '
                    'erscheint hier der gemeinsame Winterplan.'
                : 'Sobald reguläre Trainingszeiten bei den Mannschaften '
                    'gepflegt sind, erscheint hier der gemeinsame Wochenplan.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 820
                ? _DesktopBoard(
                    plan: plan,
                    conflictSlots: conflictSlots,
                    approvedSlots: approvedSlots,
                  )
                : _MobileBoard(
                    slots: slots,
                    conflictSlots: conflictSlots,
                    approvedSlots: approvedSlots,
                  ),
          ),
        const SizedBox(height: 14),
        const _Notice(
          icon: Icons.handshake_outlined,
          color: AppColors.teal,
          title: 'Fair koordinieren',
          message:
              'Trifft ein Spiel kurzfristig auf eine Trainingszeit, stimmen sich die betroffenen Trainer bitte direkt miteinander ab.',
        ),
      ],
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({
    required this.plan,
    required this.slotCount,
    required this.conflictCount,
    required this.matchdayCount,
  });

  final PitchOccupancyPlan plan;
  final int slotCount;
  final int conflictCount;
  final int matchdayCount;

  @override
  Widget build(BuildContext context) {
    final locations = plan.slots.map((slot) => slot.location).toSet().toList()
      ..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.black, Color(0xFF343000)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  plan.indoor
                      ? Icons.sports_handball_rounded
                      : Icons.stadium_rounded,
                  color: AppColors.black,
                  size: 28,
                ),
              ),
              SizedBox(
                width: 430,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${plan.indoor ? 'HALLENBELEGUNG' : 'PLATZBELEGUNG'} '
                      '· SAISON ${plan.seasonName}',
                      style: const TextStyle(
                        color: AppColors.yellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${plan.clubName} · gemeinsamer Wochenplan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              _HeaderMetric(value: '$slotCount', label: 'Belegungen'),
              _HeaderMetric(value: '$matchdayCount', label: 'Spieltage'),
              _HeaderMetric(
                value: '$conflictCount',
                label: 'Konflikte',
                alert: conflictCount > 0,
              ),
            ],
          ),
          if (locations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final location in locations)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: _locationColor(location),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      location,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.value,
    required this.label,
    this.alert = false,
  });

  final String value;
  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: alert
              ? Colors.deepOrange.withValues(alpha: .22)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: alert
                ? Colors.deepOrangeAccent
                : Colors.white.withValues(alpha: .12),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: alert ? Colors.deepOrangeAccent : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      );
}

class _DesktopBoard extends StatelessWidget {
  const _DesktopBoard({
    required this.plan,
    required this.conflictSlots,
    required this.approvedSlots,
  });

  final PitchOccupancyPlan plan;
  final Set<PitchOccupancySlot> conflictSlots;
  final Set<PitchOccupancySlot> approvedSlots;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const teamWidth = 150.0;
              const dayWidth = 124.0;
              return SizedBox(
                width: teamWidth + dayWidth * 7,
                child: Column(
                  children: [
                    Container(
                      color: AppColors.black,
                      child: Row(
                        children: [
                          const _BoardHeaderCell(
                            width: teamWidth,
                            label: 'Mannschaft',
                            alignedLeft: true,
                          ),
                          for (final day in PitchOccupancySlot.weekdays)
                            _BoardHeaderCell(width: dayWidth, label: day),
                        ],
                      ),
                    ),
                    for (var index = 0; index < plan.teams.length; index++)
                      _DesktopTeamRow(
                        team: plan.teams[index],
                        teamWidth: teamWidth,
                        dayWidth: dayWidth,
                        shaded: index.isOdd,
                        conflictSlots: conflictSlots,
                        approvedSlots: approvedSlots,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _BoardHeaderCell extends StatelessWidget {
  const _BoardHeaderCell({
    required this.width,
    required this.label,
    this.alignedLeft = false,
  });

  final double width;
  final String label;
  final bool alignedLeft;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 42,
        child: Align(
          alignment: alignedLeft ? Alignment.centerLeft : Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
}

class _DesktopTeamRow extends StatelessWidget {
  const _DesktopTeamRow({
    required this.team,
    required this.teamWidth,
    required this.dayWidth,
    required this.shaded,
    required this.conflictSlots,
    required this.approvedSlots,
  });

  final PitchOccupancyTeam team;
  final double teamWidth;
  final double dayWidth;
  final bool shaded;
  final Set<PitchOccupancySlot> conflictSlots;
  final Set<PitchOccupancySlot> approvedSlots;

  @override
  Widget build(BuildContext context) {
    final background = shaded ? const Color(0xFFF8F7F2) : Colors.white;
    return Container(
      color: background,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: teamWidth,
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.all(9),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: AppColors.line),
                  bottom: BorderSide(color: AppColors.line),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    team.label,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    team.locationLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            for (var weekday = 1; weekday <= 7; weekday++)
              Container(
                width: dayWidth,
                constraints: const BoxConstraints(minHeight: 62),
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.line),
                    bottom: BorderSide(color: AppColors.line),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final slot
                        in team.slots.where((slot) => slot.weekday == weekday))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _SlotPill(
                          slot: slot,
                          conflict: conflictSlots.contains(slot),
                          approved: approvedSlots.contains(slot),
                          compact: true,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileBoard extends StatelessWidget {
  const _MobileBoard({
    required this.slots,
    required this.conflictSlots,
    required this.approvedSlots,
  });

  final List<PitchOccupancySlot> slots;
  final Set<PitchOccupancySlot> conflictSlots;
  final Set<PitchOccupancySlot> approvedSlots;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var weekday = 1; weekday <= 7; weekday++)
            if (slots.any((slot) => slot.weekday == weekday))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.yellow,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Center(
                                child: Text(
                                  PitchOccupancySlot.weekdays[weekday - 1]
                                      .substring(0, 2)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              PitchOccupancySlot.weekdays[weekday - 1],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final slot
                            in slots
                                .where((slot) => slot.weekday == weekday)
                                .toList()
                              ..sort(
                                (a, b) =>
                                    a.startMinute.compareTo(b.startMinute),
                              ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SlotPill(
                              slot: slot,
                              conflict: conflictSlots.contains(slot),
                              approved: approvedSlots.contains(slot),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      );
}

class _SlotPill extends StatelessWidget {
  const _SlotPill({
    required this.slot,
    required this.conflict,
    this.approved = false,
    this.compact = false,
  });

  final PitchOccupancySlot slot;
  final bool conflict;
  final bool approved;
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '${slot.teamLabel}\n${slot.location}\n${slot.timeLabel}',
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 12,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: _locationColor(slot.location),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: conflict
                  ? Colors.deepOrange
                  : approved
                      ? AppColors.teal
                      : Colors.transparent,
              width: conflict ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.kind == PitchOccupancySlotKind.matchday
                          ? 'Spieltag · ${slot.timeLabel}'
                          : slot.timeLabel,
                      style: TextStyle(
                        color: AppColors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 11 : 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      compact
                          ? slot.location
                          : '${slot.teamLabel} · ${slot.location}',
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: compact ? 9 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (conflict)
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.deepOrange,
                  size: 18,
                ),
              if (!conflict && approved)
                const Icon(
                  Icons.verified_rounded,
                  color: AppColors.teal,
                  size: 17,
                ),
              if (slot.kind == PitchOccupancySlotKind.matchday)
                const Icon(
                  Icons.sports_soccer_rounded,
                  color: AppColors.blue,
                  size: 17,
                ),
            ],
          ),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.conflict,
    required this.canManage,
    required this.onChanged,
  });

  final PitchOccupancyConflict conflict;
  final bool canManage;
  final void Function(PitchOccupancyConflict conflict, bool approved)?
      onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (conflict.approved ? AppColors.teal : Colors.deepOrange)
              .withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (conflict.approved ? AppColors.teal : Colors.deepOrange)
                .withValues(alpha: .2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              conflict.approved
                  ? Icons.verified_rounded
                  : Icons.compare_arrows_rounded,
              color: conflict.approved ? AppColors.teal : Colors.deepOrange,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${conflict.first.teamLabel} ↔ ${conflict.second.teamLabel} · '
                '${PitchOccupancySlot.weekdays[conflict.first.weekday - 1]} '
                '${conflict.first.timeLabel} · ${conflict.first.location}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (canManage)
              TextButton.icon(
                onPressed: onChanged == null
                    ? null
                    : () => onChanged!(conflict, !conflict.approved),
                icon: Icon(
                  conflict.approved
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                ),
                label: Text(
                  conflict.approved ? 'Wieder öffnen' : 'Abgestimmt',
                ),
              ),
          ],
        ),
      );
}

Color _locationColor(String location) {
  final normalized = location.toLowerCase();
  if (normalized.contains('platz 1') || normalized.contains('unten')) {
    return AppColors.yellow;
  }
  if (normalized.contains('platz 2') || normalized.contains('oben')) {
    return const Color(0xFF9BD65B);
  }
  if (normalized.contains('halle')) {
    return const Color(0xFF73D2DE);
  }
  const palette = [
    Color(0xFFFFC857),
    Color(0xFF8FD5A6),
    Color(0xFF7CC6FE),
    Color(0xFFFFA69E),
  ];
  final hash = location.codeUnits.fold<int>(0, (sum, item) => sum + item);
  return palette[(hash < 0 ? -hash : hash) % palette.length];
}
