import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models/pitch_occupancy.dart';
import '../shared/page_scaffold.dart';

enum _OccupancyViewMode { list, timeline, table }

class PitchOccupancyBoard extends StatefulWidget {
  const PitchOccupancyBoard({
    required this.plan,
    this.onConflictApproval,
    this.onEditSpecialEntry,
    this.onDeleteSpecialEntry,
    super.key,
  });

  final PitchOccupancyPlan plan;
  final void Function(PitchOccupancyConflict conflict, bool approved)?
      onConflictApproval;
  final void Function(IndoorOccupancyEntry entry)? onEditSpecialEntry;
  final void Function(IndoorOccupancyEntry entry)? onDeleteSpecialEntry;

  @override
  State<PitchOccupancyBoard> createState() => _PitchOccupancyBoardState();
}

class _PitchOccupancyBoardState extends State<PitchOccupancyBoard> {
  _OccupancyViewMode _viewMode = _OccupancyViewMode.list;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
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
          specialCount: plan.specialEntries.length,
        ),
        if (plan.indoor && plan.specialEntries.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SpecialOccupancySection(
            entries: plan.specialEntries,
            canManage: plan.canManageOccupancy,
            onEdit: widget.onEditSpecialEntry,
            onDelete: widget.onDeleteSpecialEntry,
          ),
        ],
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
                onChanged: widget.onConflictApproval,
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
                  onChanged: widget.onConflictApproval,
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
        if (slots.isEmpty && plan.specialEntries.isEmpty)
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
        else if (slots.isNotEmpty) ...[
          const SizedBox(height: 2),
          _OccupancyViewSelector(
            value: _viewMode,
            onChanged: (value) => setState(() => _viewMode = value),
          ),
          const SizedBox(height: 10),
          switch (_viewMode) {
            _OccupancyViewMode.list => _MobileBoard(
                slots: slots,
                conflictSlots: conflictSlots,
                approvedSlots: approvedSlots,
              ),
            _OccupancyViewMode.timeline => _TimelineBoard(
                slots: slots,
                conflictSlots: conflictSlots,
                approvedSlots: approvedSlots,
              ),
            _OccupancyViewMode.table => _DesktopBoard(
                plan: plan,
                conflictSlots: conflictSlots,
                approvedSlots: approvedSlots,
              ),
          },
        ],
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
    required this.specialCount,
  });

  final PitchOccupancyPlan plan;
  final int slotCount;
  final int conflictCount;
  final int matchdayCount;
  final int specialCount;

  @override
  Widget build(BuildContext context) {
    final locations = plan.slots.map((slot) => slot.location).toSet().toList()
      ..sort();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plan.indoor ? 'HALLENBELEGUNG' : 'PLATZBELEGUNG'} '
              '· ${plan.seasonName}',
              style: TextStyle(
                color: AppColors.yellow,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w900,
                letterSpacing: compact ? .45 : .8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${plan.clubName} · Wochenplan',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleLarge)
                  ?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        );
        return Container(
          padding: EdgeInsets.all(compact ? 13 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.black, Color(0xFF343000)],
            ),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                Row(
                  children: [
                    _PlanIcon(indoor: plan.indoor, compact: true),
                    const SizedBox(width: 11),
                    Expanded(child: heading),
                  ],
                )
              else
                Row(
                  children: [
                    _PlanIcon(indoor: plan.indoor),
                    const SizedBox(width: 16),
                    Expanded(child: heading),
                  ],
                ),
              SizedBox(height: compact ? 12 : 16),
              Row(
                children: [
                  Expanded(
                    child: _HeaderMetric(
                      value: '$slotCount',
                      label: 'Belegungen',
                      compact: compact,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _HeaderMetric(
                      value: '${plan.indoor ? specialCount : matchdayCount}',
                      label: plan.indoor ? 'Extern' : 'Spieltage',
                      compact: compact,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _HeaderMetric(
                      value: '$conflictCount',
                      label: 'Konflikte',
                      alert: conflictCount > 0,
                      compact: compact,
                    ),
                  ),
                ],
              ),
              if (locations.isNotEmpty) ...[
                SizedBox(height: compact ? 9 : 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final location in locations)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 9,
                          vertical: compact ? 4 : 5,
                        ),
                        decoration: BoxDecoration(
                          color: _locationColor(location),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          location,
                          style: TextStyle(
                            color: AppColors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 10 : 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PlanIcon extends StatelessWidget {
  const _PlanIcon({required this.indoor, this.compact = false});

  final bool indoor;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: compact ? 42 : 52,
        height: compact ? 42 : 52,
        decoration: BoxDecoration(
          color: AppColors.yellow,
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
        ),
        child: Icon(
          indoor ? Icons.sports_handball_rounded : Icons.stadium_rounded,
          color: AppColors.black,
          size: compact ? 23 : 28,
        ),
      );
}

class _SpecialOccupancySection extends StatelessWidget {
  const _SpecialOccupancySection({
    required this.entries,
    required this.canManage,
    this.onEdit,
    this.onDelete,
  });

  final List<IndoorOccupancyEntry> entries;
  final bool canManage;
  final void Function(IndoorOccupancyEntry entry)? onEdit;
  final void Function(IndoorOccupancyEntry entry)? onDelete;

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _weekdays(List<int> values) {
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return values
        .where((value) => value >= 1 && value <= 7)
        .map((value) => labels[value - 1])
        .join(', ');
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF73D2DE).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF73D2DE).withValues(alpha: .45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_busy_rounded, color: AppColors.blue),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Individuelle Hallenbelegungen',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Regelmäßige oder einmalige Nutzungen der Sporthalle durch '
              'andere Abteilungen, Vereine oder Veranstaltungen.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFF73D2DE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.business_rounded,
                          color: AppColors.black,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.isRecurring
                                  ? '${entry.recurrenceIntervalWeeks == 1 ? 'Wöchentlich' : 'Alle ${entry.recurrenceIntervalWeeks} Wochen'} '
                                      '${_weekdays(entry.recurrenceWeekdays)} · '
                                      '${_time(entry.startAt)}–${_time(entry.endAt)} Uhr'
                                  : '${_date(entry.startAt)} · '
                                      '${_time(entry.startAt)}–${_time(entry.endAt)} Uhr',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              entry.isRecurring && entry.recurrenceUntil != null
                                  ? 'Sporthalle · ${_date(entry.startAt)}–'
                                      '${_date(entry.recurrenceUntil!)}'
                                  : 'Sporthalle',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            if (entry.notes?.trim().isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  entry.notes!,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canManage)
                        PopupMenuButton<String>(
                          tooltip: 'Sonderbelegung verwalten',
                          onSelected: (value) {
                            if (value == 'edit') onEdit?.call(entry);
                            if (value == 'delete') onDelete?.call(entry);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Bearbeiten'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Löschen'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.value,
    required this.label,
    this.alert = false,
    this.compact = false,
  });

  final String value;
  final String label;
  final bool alert;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 15,
          vertical: compact ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: alert
              ? Colors.deepOrange.withValues(alpha: .22)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(compact ? 11 : 14),
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
                fontSize: compact ? 17 : 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white60,
                fontSize: compact ? 9 : 11,
              ),
            ),
          ],
        ),
      );
}

class _OccupancyViewSelector extends StatelessWidget {
  const _OccupancyViewSelector({
    required this.value,
    required this.onChanged,
  });

  final _OccupancyViewMode value;
  final ValueChanged<_OccupancyViewMode> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Darstellung der Belegung wählen',
        child: Container(
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF0EEE4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              _OccupancyViewButton(
                label: 'Liste',
                icon: Icons.view_agenda_outlined,
                selected: value == _OccupancyViewMode.list,
                onTap: () => onChanged(_OccupancyViewMode.list),
              ),
              _OccupancyViewButton(
                label: 'Zeitplan',
                icon: Icons.timeline_rounded,
                selected: value == _OccupancyViewMode.timeline,
                onTap: () => onChanged(_OccupancyViewMode.timeline),
              ),
              _OccupancyViewButton(
                label: 'Tabelle',
                icon: Icons.table_chart_outlined,
                selected: value == _OccupancyViewMode.table,
                onTap: () => onChanged(_OccupancyViewMode.table),
              ),
            ],
          ),
        ),
      );
}

class _OccupancyViewButton extends StatelessWidget {
  const _OccupancyViewButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x17000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? AppColors.gold : AppColors.muted,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TimelineBoard extends StatelessWidget {
  const _TimelineBoard({
    required this.slots,
    required this.conflictSlots,
    required this.approvedSlots,
  });

  final List<PitchOccupancySlot> slots;
  final Set<PitchOccupancySlot> conflictSlots;
  final Set<PitchOccupancySlot> approvedSlots;

  String _clock(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final earliest = slots.map((slot) => slot.startMinute).reduce(
          (a, b) => a < b ? a : b,
        );
    final latest = slots.map((slot) => slot.endMinute).reduce(
          (a, b) => a > b ? a : b,
        );
    final rangeStart = (earliest ~/ 60) * 60;
    final roundedEnd = ((latest + 59) ~/ 60) * 60;
    final rangeEnd = roundedEnd <= rangeStart ? rangeStart + 60 : roundedEnd;
    final range = rangeEnd - rangeStart;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 17, color: AppColors.blue),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Grafische Wochenansicht · ${_clock(rangeStart)}–${_clock(rangeEnd)} Uhr',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var weekday = 1; weekday <= 7; weekday++)
          if (slots.any((slot) => slot.weekday == weekday))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _TimelineDay(
                weekday: weekday,
                slots: slots.where((slot) => slot.weekday == weekday).toList()
                  ..sort((a, b) => a.startMinute.compareTo(b.startMinute)),
                rangeStart: rangeStart,
                range: range,
                conflictSlots: conflictSlots,
                approvedSlots: approvedSlots,
              ),
            ),
      ],
    );
  }
}

class _TimelineDay extends StatelessWidget {
  const _TimelineDay({
    required this.weekday,
    required this.slots,
    required this.rangeStart,
    required this.range,
    required this.conflictSlots,
    required this.approvedSlots,
  });

  final int weekday;
  final List<PitchOccupancySlot> slots;
  final int rangeStart;
  final int range;
  final Set<PitchOccupancySlot> conflictSlots;
  final Set<PitchOccupancySlot> approvedSlots;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  PitchOccupancySlot.weekdays[weekday - 1],
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '${slots.length} ${slots.length == 1 ? 'Zeit' : 'Zeiten'}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            for (final slot in slots)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const timeWidth = 52.0;
                    final trackWidth = constraints.maxWidth - timeWidth - 7;
                    final left = ((slot.startMinute - rangeStart) / range)
                            .clamp(0.0, 1.0) *
                        trackWidth;
                    final rawWidth = (slot.endMinute - slot.startMinute) /
                        range *
                        trackWidth;
                    final remainingWidth = trackWidth - left;
                    final minimumWidth =
                        remainingWidth < 54 ? remainingWidth : 54.0;
                    final width = rawWidth.clamp(minimumWidth, remainingWidth);
                    final conflict = conflictSlots.contains(slot);
                    final approved = approvedSlots.contains(slot);
                    return SizedBox(
                      height: 42,
                      child: Row(
                        children: [
                          SizedBox(
                            width: timeWidth,
                            child: Text(
                              slot.timeLabel.split('–').first,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: AppColors.line,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                Positioned(
                                  left: left,
                                  width: width,
                                  top: 2,
                                  bottom: 2,
                                  child: Tooltip(
                                    message:
                                        '${slot.teamLabel}\n${slot.timeLabel}\n${slot.location}',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _locationColor(slot.location),
                                        borderRadius: BorderRadius.circular(9),
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
                                            child: Text(
                                              slot.teamLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.black,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          if (slot.kind ==
                                              PitchOccupancySlotKind.matchday)
                                            const Icon(
                                              Icons.sports_soccer_rounded,
                                              size: 12,
                                              color: AppColors.blue,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
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
                    padding: const EdgeInsets.all(9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.yellow,
                                borderRadius: BorderRadius.circular(9),
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
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                PitchOccupancySlot.weekdays[weekday - 1],
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Text(
                              '${slots.where((slot) => slot.weekday == weekday).length}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final slot
                            in slots
                                .where((slot) => slot.weekday == weekday)
                                .toList()
                              ..sort(
                                (a, b) =>
                                    a.startMinute.compareTo(b.startMinute),
                              ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
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
            horizontal: compact ? 7 : 9,
            vertical: compact ? 5 : 7,
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
                        fontSize: compact ? 11 : 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      compact
                          ? slot.location
                          : '${slot.teamLabel} · ${slot.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: compact ? 9 : 10,
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
