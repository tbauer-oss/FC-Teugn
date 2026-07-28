import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

enum CalendarView { day, week, month, agenda }

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, required this.canManage});

  final bool canManage;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  CalendarView view = CalendarView.month;
  DateTime cursor = DateTime.now();
  final selectedCategories = <EventCategory>{};
  final selectedTeams = <String>{};

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final organization = ref.watch(organizationProvider).value;
    final canManage = widget.canManage &&
        (organization?.can('MANAGE_EVENTS') ?? widget.canManage);

    return PageScaffold(
      title: 'Vereinskalender',
      subtitle:
          'Termine, Rückmeldungen und Fahrgemeinschaften an einem verlässlichen Ort.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: _createSubscription,
            icon: const Icon(Icons.calendar_add_on_rounded),
            label: const Text('Kalender-Abo'),
          ),
          if (canManage)
            FilledButton.icon(
              onPressed: organization == null
                  ? null
                  : () => _createEvent(organization),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Termin'),
            ),
        ],
      ),
      child: Column(
        children: [
          _CalendarToolbar(
            view: view,
            cursor: cursor,
            teams: organization?.teams ?? const [],
            selectedCategories: selectedCategories,
            selectedTeams: selectedTeams,
            onViewChanged: (value) => setState(() => view = value),
            onPrevious: () => setState(() => cursor = _shift(cursor, -1)),
            onNext: () => setState(() => cursor = _shift(cursor, 1)),
            onToday: () => setState(() => cursor = DateTime.now()),
            onCategoriesChanged: (values) =>
                setState(() => selectedCategories
                  ..clear()
                  ..addAll(values)),
            onTeamsChanged: (values) => setState(() => selectedTeams
              ..clear()
              ..addAll(values)),
          ),
          const SizedBox(height: 18),
          events.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(72),
              child: CircularProgressIndicator(),
            ),
            error: (_, __) => EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Kalender nicht erreichbar',
              message:
                  'Die Termine konnten gerade nicht geladen werden. Bitte erneut versuchen.',
              action: FilledButton(
                onPressed: () => ref.invalidate(eventsProvider),
                child: const Text('Neu laden'),
              ),
            ),
            data: (items) {
              final filtered = items.where(_matchesFilters).toList()
                ..sort((a, b) => a.startAt.compareTo(b.startAt));
              if (filtered.isEmpty) {
                return EmptyState(
                  icon: Icons.event_available_rounded,
                  title: 'Keine passenden Termine',
                  message: selectedCategories.isEmpty && selectedTeams.isEmpty
                      ? 'Sobald ein Termin angelegt wurde, erscheint er hier.'
                      : 'Passe die ausgewählten Filter an.',
                );
              }
              return switch (view) {
                CalendarView.month => _MonthView(
                    cursor: cursor,
                    events: filtered,
                    onOpen: _openEvent,
                  ),
                CalendarView.week => _PeriodAgenda(
                    dates: List.generate(
                      7,
                      (index) => _monday(cursor).add(Duration(days: index)),
                    ),
                    events: filtered,
                    onOpen: _openEvent,
                  ),
                CalendarView.day => _PeriodAgenda(
                    dates: [_dateOnly(cursor)],
                    events: filtered,
                    onOpen: _openEvent,
                  ),
                CalendarView.agenda => _AgendaView(
                    events: filtered
                        .where((event) => !event.startAt
                            .isBefore(DateTime.now().subtract(const Duration(days: 1))))
                        .toList(),
                    onOpen: _openEvent,
                  ),
              };
            },
          ),
        ],
      ),
    );
  }

  bool _matchesFilters(EventModel event) {
    final categoryMatches =
        selectedCategories.isEmpty || selectedCategories.contains(event.category);
    final eventTeamIds = event.targetTeams.isEmpty
        ? {event.teamId}
        : event.targetTeams.map((team) => team.id).toSet();
    final teamMatches =
        selectedTeams.isEmpty || eventTeamIds.any(selectedTeams.contains);
    return categoryMatches && teamMatches;
  }

  DateTime _shift(DateTime value, int direction) => switch (view) {
        CalendarView.day => value.add(Duration(days: direction)),
        CalendarView.week => value.add(Duration(days: 7 * direction)),
        CalendarView.month || CalendarView.agenda =>
          DateTime(value.year, value.month + direction, 1),
      };

  Future<void> _createEvent(OrganizationContext organization) async {
    final draft = await showDialog<EventWriteData>(
      context: context,
      builder: (context) => EventEditorDialog(
        teams: organization.teams,
        initialTeamId: organization.currentTeam.id,
      ),
    );
    if (draft == null) return;
    await _execute(() async {
      await ref.read(repositoryProvider).createEvent(draft);
    }, 'Termin wurde angelegt.');
  }

  Future<void> _openEvent(EventModel event) async {
    await showDialog<void>(
      context: context,
      builder: (context) => EventDetailsDialog(event: event),
    );
  }

  Future<void> _createSubscription() async {
    await _execute(() async {
      final url =
          await ref.read(repositoryProvider).createCalendarSubscription();
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kalender-Abo erstellt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Die persönliche Abo-Adresse wurde in die Zwischenablage kopiert. '
                'Sie enthält einen geheimen Zugriffsschlüssel und sollte nicht weitergegeben werden.',
              ),
              const SizedBox(height: 14),
              SelectableText(url),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Verstanden'),
            ),
          ],
        ),
      );
    }, 'Kalender-Abo wurde kopiert.', showSuccess: false);
  }

  Future<void> _execute(
    Future<void> Function() action,
    String success, {
    bool showSuccess = true,
  }) async {
    try {
      await action();
      ref.invalidate(eventsProvider);
      if (mounted && showSuccess) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Änderung konnte nicht gespeichert werden.'),
          ),
        );
      }
    }
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.view,
    required this.cursor,
    required this.teams,
    required this.selectedCategories,
    required this.selectedTeams,
    required this.onViewChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onCategoriesChanged,
    required this.onTeamsChanged,
  });

  final CalendarView view;
  final DateTime cursor;
  final List<TeamSummary> teams;
  final Set<EventCategory> selectedCategories;
  final Set<String> selectedTeams;
  final ValueChanged<CalendarView> onViewChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<Set<EventCategory>> onCategoriesChanged;
  final ValueChanged<Set<String>> onTeamsChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Zurück',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            SizedBox(
              width: 172,
              child: Text(
                _periodLabel(view, cursor),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Weiter',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            TextButton(onPressed: onToday, child: const Text('Heute')),
            const SizedBox(width: 4),
            SegmentedButton<CalendarView>(
              segments: const [
                ButtonSegment(value: CalendarView.day, label: Text('Tag')),
                ButtonSegment(value: CalendarView.week, label: Text('Woche')),
                ButtonSegment(value: CalendarView.month, label: Text('Monat')),
                ButtonSegment(value: CalendarView.agenda, label: Text('Agenda')),
              ],
              selected: {view},
              showSelectedIcon: false,
              onSelectionChanged: (value) => onViewChanged(value.first),
            ),
            _FilterButton<EventCategory>(
              label: 'Kategorien',
              icon: Icons.category_outlined,
              values: EventCategory.values,
              selected: selectedCategories,
              itemLabel: (item) => item.label,
              onChanged: onCategoriesChanged,
            ),
            if (teams.length > 1)
              _FilterButton<String>(
                label: 'Mannschaften',
                icon: Icons.groups_rounded,
                values: teams.map((team) => team.id).toList(),
                selected: selectedTeams,
                itemLabel: (id) =>
                    teams.firstWhere((team) => team.id == id).displayName,
                onChanged: onTeamsChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterButton<T> extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.icon,
    required this.values,
    required this.selected,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<T> values;
  final Set<T> selected;
  final String Function(T) itemLabel;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: (value) {
        final next = {...selected};
        next.contains(value) ? next.remove(value) : next.add(value);
        onChanged(next);
      },
      itemBuilder: (context) => [
        for (final value in values)
          PopupMenuItem(
            value: value,
            child: Row(
              children: [
                Icon(
                  selected.contains(value)
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(itemLabel(value))),
              ],
            ),
          ),
      ],
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text(
          selected.isEmpty ? label : '$label (${selected.length})',
        ),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.cursor,
    required this.events,
    required this.onOpen,
  });

  final DateTime cursor;
  final List<EventModel> events;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(cursor.year, cursor.month);
    final offset = first.weekday - 1;
    final days = DateTime(cursor.year, cursor.month + 1, 0).day;
    final totalCells = ((offset + days + 6) ~/ 7) * 7;

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1050,
          child: Column(
            children: [
              const Row(
                children: [
                  for (final label
                      in ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(height: 1),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: .92,
                ),
                itemCount: totalCells,
                itemBuilder: (context, index) {
                  final day = index - offset + 1;
                  if (day < 1 || day > days) {
                    return const DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: AppColors.line),
                          bottom: BorderSide(color: AppColors.line),
                        ),
                        color: Color(0xFFF9FBFC),
                      ),
                    );
                  }
                  final date = DateTime(cursor.year, cursor.month, day);
                  final dayEvents =
                      events.where((event) => _sameDay(event.startAt, date)).toList();
                  return _MonthDay(
                    date: date,
                    events: dayEvents,
                    onOpen: onOpen,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthDay extends StatelessWidget {
  const _MonthDay({
    required this.date,
    required this.events,
    required this.onOpen,
  });

  final DateTime date;
  final List<EventModel> events;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final today = _sameDay(date, DateTime.now());
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: today ? AppColors.blue : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: today ? Colors.white : AppColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final event in events.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => onOpen(event),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: _categoryColor(event.category)
                        .withValues(alpha: event.isCancelled ? .07 : .13),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${_time(event.startAt)} ${event.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      decoration:
                          event.isCancelled ? TextDecoration.lineThrough : null,
                      color: _categoryColor(event.category),
                    ),
                  ),
                ),
              ),
            ),
          if (events.length > 3)
            Text(
              '+ ${events.length - 3} weitere',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _PeriodAgenda extends StatelessWidget {
  const _PeriodAgenda({
    required this.dates,
    required this.events,
    required this.onOpen,
  });

  final List<DateTime> dates;
  final List<EventModel> events;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final date in dates) ...[
          _DayHeader(date: date),
          const SizedBox(height: 8),
          if (!events.any((event) => _sameDay(event.startAt, date)))
            const _NoEventsRow()
          else
            for (final event
                in events.where((event) => _sameDay(event.startAt, date)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EventCard(event: event, onOpen: onOpen),
              ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AgendaView extends StatelessWidget {
  const _AgendaView({required this.events, required this.onOpen});

  final List<EventModel> events;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy_rounded,
        title: 'Keine anstehenden Termine',
        message: 'In der Agenda stehen derzeit keine weiteren Termine.',
      );
    }
    DateTime? previous;
    final children = <Widget>[];
    for (final event in events) {
      if (previous == null || !_sameDay(previous, event.startAt)) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: _DayHeader(date: event.startAt),
          ),
        );
      }
      children
        ..add(_EventCard(event: event, onOpen: onOpen))
        ..add(const SizedBox(height: 9));
      previous = event.startAt;
    }
    return Column(children: children);
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${_weekday(date)}, ${date.day}. ${_month(date.month)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _NoEventsRow extends StatelessWidget {
  const _NoEventsRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text('Keine Termine', style: TextStyle(color: AppColors.muted)),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onOpen});

  final EventModel event;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(event.category);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onOpen(event),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      _time(event.startAt),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      event.endAt == null ? 'Uhr' : '– ${_time(event.endAt!)}',
                      style: TextStyle(color: color, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          event.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                decoration: event.isCancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                        if (event.isRecurring)
                          const Icon(Icons.repeat_rounded,
                              size: 17, color: AppColors.muted),
                        if (event.isCancelled)
                          const Chip(label: Text('Abgesagt')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        event.category.label,
                        event.location,
                        if (event.opponent != null) 'vs. ${event.opponent}',
                      ].join(' · '),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _CountChip(
                          icon: Icons.check_circle_rounded,
                          value: event.attendanceSummary.yes,
                          color: AppColors.teal,
                        ),
                        _CountChip(
                          icon: Icons.cancel_rounded,
                          value: event.attendanceSummary.no,
                          color: Colors.redAccent,
                        ),
                        _CountChip(
                          icon: Icons.help_rounded,
                          value: event.attendanceSummary.maybe,
                          color: AppColors.orange,
                        ),
                        if (event.capabilities.canManage)
                          _CountChip(
                            icon: Icons.hourglass_empty_rounded,
                            value: event.attendanceSummary.unknown,
                            color: AppColors.muted,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class EventDetailsDialog extends ConsumerWidget {
  const EventDetailsDialog({super.key, required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider).value ?? const <PlayerModel>[];
    final organization = ref.watch(organizationProvider).value;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 820),
        child: Column(
          children: [
            _DetailsHeader(event: event),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EventFacts(event: event),
                    if (event.description != null) ...[
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Beschreibung',
                        child: Text(event.description!),
                      ),
                    ],
                    if (event.equipment != null ||
                        event.clothing != null ||
                        event.catering != null) ...[
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Vorbereitung',
                        child: Column(
                          children: [
                            if (event.equipment != null)
                              _InfoRow(
                                icon: Icons.sports_soccer_rounded,
                                label: 'Ausrüstung',
                                value: event.equipment!,
                              ),
                            if (event.clothing != null)
                              _InfoRow(
                                icon: Icons.checkroom_rounded,
                                label: 'Kleidung',
                                value: event.clothing!,
                              ),
                            if (event.catering != null)
                              _InfoRow(
                                icon: Icons.restaurant_rounded,
                                label: 'Verpflegung',
                                value: event.catering!,
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _AttendanceSection(
                      event: event,
                      players: players,
                      onRefresh: () {
                        ref.invalidate(eventsProvider);
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 20),
                    _CarpoolSection(
                      event: event,
                      players: players,
                      onRefresh: () {
                        ref.invalidate(eventsProvider);
                        Navigator.pop(context);
                      },
                    ),
                    if (event.internalNote != null) ...[
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Interne Trainernotiz',
                        child: Text(event.internalNote!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (event.capabilities.canManage && organization != null)
              _ManagementBar(event: event, organization: organization),
          ],
        ),
      ),
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(event.category);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_categoryIcon(event.category), color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.category.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                Text(event.title,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (event.isCancelled)
                  Text(
                    'Abgesagt${event.cancellationReason == null ? '' : ': ${event.cancellationReason}'}',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Schließen',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _EventFacts extends StatelessWidget {
  const _EventFacts({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _InfoRow(
              icon: Icons.schedule_rounded,
              label: 'Termin',
              value:
                  '${_fullDate(event.startAt)} · ${_time(event.startAt)}${event.endAt == null ? '' : '–${_time(event.endAt!)}'} Uhr',
            ),
            if (event.meetingAt != null)
              _InfoRow(
                icon: Icons.groups_rounded,
                label: 'Treffpunkt',
                value: '${_time(event.meetingAt!)} Uhr',
              ),
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: 'Ort',
              value: [
                event.location,
                if (event.address != null) event.address!,
              ].join(' · '),
            ),
            if (event.opponent != null)
              _InfoRow(
                icon: Icons.sports_rounded,
                label: 'Gegner',
                value:
                    '${event.opponent}${event.homeAway == null ? '' : ' · ${_homeAway(event.homeAway!)}'}',
              ),
            if (event.targetTeams.isNotEmpty)
              _InfoRow(
                icon: Icons.shield_rounded,
                label: 'Mannschaften',
                value: event.targetTeams.map((team) => team.label).join(', '),
              ),
            if (event.responseDeadline != null)
              _InfoRow(
                icon: Icons.timer_outlined,
                label: 'Rückmeldung bis',
                value:
                    '${_fullDate(event.responseDeadline!)} · ${_time(event.responseDeadline!)} Uhr',
              ),
            if (event.contactName != null)
              _InfoRow(
                icon: Icons.contact_phone_rounded,
                label: 'Ansprechpartner',
                value: [
                  event.contactName!,
                  if (event.contactPhone != null) event.contactPhone!,
                ].join(' · '),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.blue),
          const SizedBox(width: 12),
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _AttendanceSection extends ConsumerWidget {
  const _AttendanceSection({
    required this.event,
    required this.players,
    required this.onRefresh,
  });

  final EventModel event;
  final List<PlayerModel> players;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = event.attendanceSummary;
    return _Section(
      title: 'Zu- und Absagen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusMetric(
                  label: 'Zugesagt',
                  value: summary.yes,
                  color: AppColors.teal),
              _StatusMetric(
                  label: 'Abgesagt',
                  value: summary.no,
                  color: Colors.redAccent),
              _StatusMetric(
                  label: 'Vielleicht',
                  value: summary.maybe,
                  color: AppColors.orange),
              if (event.capabilities.canManage)
                _StatusMetric(
                    label: 'Offen',
                    value: summary.unknown,
                    color: AppColors.muted),
              if (event.capabilities.canManage)
                _StatusMetric(
                    label: 'Torhüter',
                    value: summary.goalkeeperAvailable,
                    color: AppColors.blue),
            ],
          ),
          if (event.attendance.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final reply in event.attendance)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _attendanceIcon(reply.status),
                  color: _attendanceColor(reply.status),
                ),
                title: Text(reply.playerName ?? 'Spieler'),
                subtitle: reply.reason == null ? null : Text(reply.reason!),
                trailing: Text(reply.status.label),
              ),
          ],
          if (event.capabilities.canManage &&
              event.missingAttendance.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Rückmeldung fehlt: ${event.missingAttendance.map((item) => item.name).join(', ')}',
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (event.capabilities.canRespond &&
                  !event.attendanceFinalized &&
                  !event.isCancelled &&
                  players.isNotEmpty)
                FilledButton.icon(
                  onPressed: () async {
                    final response = await showDialog<_AttendanceDraft>(
                      context: context,
                      builder: (context) =>
                          _AttendanceDialog(players: players, event: event),
                    );
                    if (response == null) return;
                    try {
                      await ref.read(repositoryProvider).setAttendance(
                            eventId: event.id,
                            playerId: response.playerId,
                            status: response.status,
                            reason: response.reason,
                            goalkeeperAvailable: response.goalkeeperAvailable,
                          );
                      onRefresh();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Rückmeldung konnte nicht gespeichert werden.'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.how_to_reg_rounded),
                  label: const Text('Rückmeldung'),
                ),
              if (event.capabilities.canManage &&
                  event.missingAttendance.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await ref
                        .read(repositoryProvider)
                        .sendAttendanceReminders(event.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${result.recipients} Personen wurden erinnert.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_active_rounded),
                  label: const Text('Offene erinnern'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _CarpoolSection extends ConsumerWidget {
  const _CarpoolSection({
    required this.event,
    required this.players,
    required this.onRefresh,
  });

  final EventModel event;
  final List<PlayerModel> players;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Section(
      title: 'Fahrgemeinschaften',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.carpoolOffers.isEmpty)
            const Text('Noch keine Fahrplätze angeboten.')
          else
            for (final offer in event.carpoolOffers)
              Card(
                color: AppColors.background,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_car_rounded,
                              color: AppColors.blue),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              '${offer.driverName} · ${offer.freeSeats} freie Plätze',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_fullDate(offer.departureAt)} · ${_time(offer.departureAt)} Uhr · ${offer.departureLocation}',
                      ),
                      if (offer.driverPhone != null)
                        Text('Telefon: ${offer.driverPhone}'),
                      if (offer.notes != null) Text(offer.notes!),
                      if (offer.passengers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final passenger in offer.passengers)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${passenger.playerName} · ${_carpoolStatus(passenger.status)}',
                                ),
                              ),
                              if (offer.canManage &&
                                  passenger.status ==
                                      CarpoolRequestStatus.requested) ...[
                                IconButton(
                                  tooltip: 'Bestätigen',
                                  onPressed: () => _updatePassenger(
                                    context,
                                    ref,
                                    offer,
                                    passenger,
                                    CarpoolRequestStatus.confirmed,
                                  ),
                                  icon: const Icon(Icons.check_circle_rounded,
                                      color: AppColors.teal),
                                ),
                                IconButton(
                                  tooltip: 'Ablehnen',
                                  onPressed: () => _updatePassenger(
                                    context,
                                    ref,
                                    offer,
                                    passenger,
                                    CarpoolRequestStatus.declined,
                                  ),
                                  icon: const Icon(Icons.cancel_rounded,
                                      color: Colors.redAccent),
                                ),
                              ],
                            ],
                          ),
                      ],
                      if (offer.freeSeats > 0 &&
                          event.capabilities.canRespond &&
                          players.isNotEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              _requestSeat(context, ref, offer, players),
                          icon: const Icon(Icons.airline_seat_recline_normal),
                          label: const Text('Platz anfragen'),
                        ),
                    ],
                  ),
                ),
              ),
          if (event.capabilities.canOfferRide && !event.isCancelled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _offerRide(context, ref),
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Fahrt anbieten'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _offerRide(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_CarpoolDraft>(
      context: context,
      builder: (context) => _CarpoolDialog(event: event),
    );
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).createCarpoolOffer(
            eventId: event.id,
            seatsTotal: draft.seats,
            departureLocation: draft.location,
            departureAt: draft.departureAt,
            notes: draft.notes,
          );
      onRefresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fahrangebot konnte nicht gespeichert werden.')),
        );
      }
    }
  }

  Future<void> _requestSeat(
    BuildContext context,
    WidgetRef ref,
    CarpoolOffer offer,
    List<PlayerModel> players,
  ) async {
    final playerId = await showDialog<String>(
      context: context,
      builder: (context) => _PlayerSelectionDialog(
        title: 'Mitfahrplatz anfragen',
        players: players,
      ),
    );
    if (playerId == null) return;
    try {
      await ref.read(repositoryProvider).requestCarpoolSeat(
            eventId: event.id,
            offerId: offer.id,
            playerId: playerId,
          );
      onRefresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mitfahranfrage konnte nicht gesendet werden.')),
        );
      }
    }
  }

  Future<void> _updatePassenger(
    BuildContext context,
    WidgetRef ref,
    CarpoolOffer offer,
    CarpoolPassenger passenger,
    CarpoolRequestStatus status,
  ) async {
    await ref.read(repositoryProvider).updateCarpoolPassenger(
          eventId: event.id,
          offerId: offer.id,
          passengerId: passenger.id,
          status: status,
        );
    onRefresh();
  }
}

class _ManagementBar extends ConsumerWidget {
  const _ManagementBar({required this.event, required this.organization});

  final EventModel event;
  final OrganizationContext organization;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (!event.attendanceFinalized)
            TextButton.icon(
              onPressed: () async {
                await ref
                    .read(repositoryProvider)
                    .finalizeAttendance(event.id);
                ref.invalidate(eventsProvider);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Rückmeldungen abschließen'),
            ),
          OutlinedButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Bearbeiten'),
          ),
          if (!event.isCancelled)
            FilledButton.tonalIcon(
              onPressed: () => _cancel(context, ref),
              icon: const Icon(Icons.event_busy_rounded),
              label: const Text('Absagen'),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<EventWriteData>(
      context: context,
      builder: (context) => EventEditorDialog(
        teams: organization.teams,
        initialTeamId: organization.currentTeam.id,
        event: event,
      ),
    );
    if (draft == null || !context.mounted) return;
    final entireSeries =
        event.isRecurring ? await _seriesScope(context, 'Änderung') : false;
    if (entireSeries == null) return;
    await ref.read(repositoryProvider).updateEvent(
          eventId: event.id,
          data: draft,
          entireSeries: entireSeries,
        );
    ref.invalidate(eventsProvider);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_CancelDraft>(
      context: context,
      builder: (context) => _CancelDialog(recurring: event.isRecurring),
    );
    if (result == null) return;
    await ref.read(repositoryProvider).cancelEvent(
          eventId: event.id,
          reason: result.reason,
          entireSeries: result.entireSeries,
        );
    ref.invalidate(eventsProvider);
    if (context.mounted) Navigator.pop(context);
  }
}

class EventEditorDialog extends StatefulWidget {
  const EventEditorDialog({
    super.key,
    required this.teams,
    required this.initialTeamId,
    this.event,
  });

  final List<TeamSummary> teams;
  final String initialTeamId;
  final EventModel? event;

  @override
  State<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<EventEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController location;
  late final TextEditingController address;
  late final TextEditingController mapUrl;
  late final TextEditingController opponent;
  late final TextEditingController venue;
  late final TextEditingController contactName;
  late final TextEditingController contactPhone;
  late final TextEditingController description;
  late final TextEditingController equipment;
  late final TextEditingController clothing;
  late final TextEditingController catering;
  late final TextEditingController maxParticipants;
  late final TextEditingController internalNote;
  late final TextEditingController attachmentName;
  late final TextEditingController attachmentUrl;
  late EventCategory category;
  late EventVisibility visibility;
  HomeAway? homeAway;
  late DateTime startAt;
  DateTime? endAt;
  DateTime? meetingAt;
  DateTime? responseDeadline;
  late Set<String> teamIds;
  bool carpoolRequired = false;
  bool recurring = false;
  RecurrenceFrequency frequency = RecurrenceFrequency.weekly;
  DateTime? recurrenceUntil;
  int interval = 1;
  final weekdays = <int>{};
  final reminderMinutes = <int>{1440, 120};

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    title = TextEditingController(text: event?.title);
    location = TextEditingController(text: event?.location);
    address = TextEditingController(text: event?.address);
    mapUrl = TextEditingController(text: event?.mapUrl);
    opponent = TextEditingController(text: event?.opponent);
    venue = TextEditingController(text: event?.venue);
    contactName = TextEditingController(text: event?.contactName);
    contactPhone = TextEditingController(text: event?.contactPhone);
    description = TextEditingController(text: event?.description);
    equipment = TextEditingController(text: event?.equipment);
    clothing = TextEditingController(text: event?.clothing);
    catering = TextEditingController(text: event?.catering);
    maxParticipants =
        TextEditingController(text: event?.maxParticipants?.toString());
    internalNote = TextEditingController(text: event?.internalNote);
    attachmentName = TextEditingController();
    attachmentUrl = TextEditingController();
    category = event?.category ?? EventCategory.training;
    visibility = event?.visibility ?? EventVisibility.team;
    homeAway = event?.homeAway;
    startAt = event?.startAt ??
        DateTime.now().add(const Duration(days: 1, hours: 1));
    endAt = event?.endAt ?? startAt.add(const Duration(hours: 1, minutes: 30));
    meetingAt = event?.meetingAt;
    responseDeadline = event?.responseDeadline;
    teamIds = event == null
        ? {widget.initialTeamId}
        : (event.targetTeams.isEmpty
            ? {event.teamId}
            : event.targetTeams.map((team) => team.id).toSet());
    carpoolRequired = event?.carpoolRequired ?? false;
    reminderMinutes
      ..clear()
      ..addAll(event?.reminderMinutes ?? const [1440, 120]);
  }

  @override
  void dispose() {
    for (final controller in [
      title,
      location,
      address,
      mapUrl,
      opponent,
      venue,
      contactName,
      contactPhone,
      description,
      equipment,
      clothing,
      catering,
      maxParticipants,
      internalNote,
      attachmentName,
      attachmentUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.event == null ? 'Termin anlegen' : 'Termin bearbeiten',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<EventCategory>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: 'Kategorie'),
                        items: [
                          for (final value in EventCategory.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => category = value ?? category),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: title,
                        decoration: const InputDecoration(labelText: 'Titel'),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      _DateTimeField(
                        label: 'Beginn',
                        value: startAt,
                        onChanged: (value) => setState(() => startAt = value),
                      ),
                      const SizedBox(height: 12),
                      _DateTimeField(
                        label: 'Ende',
                        value: endAt,
                        allowClear: true,
                        onChanged: (value) => setState(() => endAt = value),
                      ),
                      const SizedBox(height: 12),
                      _DateTimeField(
                        label: 'Treffpunktzeit',
                        value: meetingAt,
                        allowClear: true,
                        onChanged: (value) => setState(() => meetingAt = value),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: location,
                        decoration: const InputDecoration(labelText: 'Ort'),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: address,
                        decoration:
                            const InputDecoration(labelText: 'Adresse (optional)'),
                      ),
                      if (category.isMatch) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: opponent,
                          decoration:
                              const InputDecoration(labelText: 'Gegner'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<HomeAway>(
                          initialValue: homeAway,
                          decoration: const InputDecoration(
                              labelText: 'Heim / Auswärts'),
                          items: const [
                            DropdownMenuItem(
                                value: HomeAway.home, child: Text('Heim')),
                            DropdownMenuItem(
                                value: HomeAway.away, child: Text('Auswärts')),
                            DropdownMenuItem(
                                value: HomeAway.neutral, child: Text('Neutral')),
                          ],
                          onChanged: (value) => setState(() => homeAway = value),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text('Mannschaften',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final team in widget.teams)
                            FilterChip(
                              label: Text(team.displayName),
                              selected: teamIds.contains(team.id),
                              onSelected: (selected) => setState(() {
                                selected
                                    ? teamIds.add(team.id)
                                    : teamIds.remove(team.id);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Weitere Termindaten'),
                        children: [
                          TextFormField(
                            controller: description,
                            maxLines: 3,
                            decoration:
                                const InputDecoration(labelText: 'Beschreibung'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: mapUrl,
                            decoration:
                                const InputDecoration(labelText: 'Kartenlink'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: venue,
                            decoration:
                                const InputDecoration(labelText: 'Spielstätte'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: contactName,
                            decoration: const InputDecoration(
                                labelText: 'Ansprechpartner'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: contactPhone,
                            decoration: const InputDecoration(
                                labelText: 'Telefon Ansprechpartner'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: equipment,
                            decoration: const InputDecoration(
                                labelText: 'Erforderliche Ausrüstung'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: clothing,
                            decoration: const InputDecoration(
                                labelText: 'Kleidungshinweis'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: catering,
                            decoration: const InputDecoration(
                                labelText: 'Verpflegungshinweis'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: maxParticipants,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Maximale Teilnehmerzahl'),
                          ),
                          const SizedBox(height: 12),
                          _DateTimeField(
                            label: 'Rückmeldefrist',
                            value: responseDeadline,
                            allowClear: true,
                            onChanged: (value) =>
                                setState(() => responseDeadline = value),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Fahrgemeinschaft benötigt'),
                            value: carpoolRequired,
                            onChanged: (value) =>
                                setState(() => carpoolRequired = value),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<EventVisibility>(
                            initialValue: visibility,
                            decoration:
                                const InputDecoration(labelText: 'Sichtbarkeit'),
                            items: const [
                              DropdownMenuItem(
                                  value: EventVisibility.team,
                                  child: Text('Mannschaften')),
                              DropdownMenuItem(
                                  value: EventVisibility.club,
                                  child: Text('Gesamter Verein')),
                              DropdownMenuItem(
                                  value: EventVisibility.staffOnly,
                                  child: Text('Nur Trainerteam')),
                            ],
                            onChanged: (value) =>
                                setState(() => visibility = value ?? visibility),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: internalNote,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                labelText: 'Interne Trainernotiz'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: attachmentName,
                            decoration: const InputDecoration(
                                labelText: 'Anhang: Bezeichnung'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: attachmentUrl,
                            decoration: const InputDecoration(
                                labelText: 'Anhang: sichere URL'),
                          ),
                        ],
                      ),
                      if (widget.event == null) ...[
                        const Divider(height: 30),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Als Serientermin anlegen'),
                          subtitle: const Text(
                              'Einzelne Vorkommnisse bleiben später separat änderbar.'),
                          value: recurring,
                          onChanged: (value) =>
                              setState(() => recurring = value),
                        ),
                        if (recurring) ...[
                          DropdownButtonFormField<RecurrenceFrequency>(
                            initialValue: frequency,
                            decoration: const InputDecoration(
                                labelText: 'Wiederholung'),
                            items: const [
                              DropdownMenuItem(
                                value: RecurrenceFrequency.weekly,
                                child: Text('Wöchentlich'),
                              ),
                              DropdownMenuItem(
                                value: RecurrenceFrequency.biweekly,
                                child: Text('Zweiwöchentlich'),
                              ),
                              DropdownMenuItem(
                                value: RecurrenceFrequency.custom,
                                child: Text('Individuell'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => frequency = value ?? frequency),
                          ),
                          const SizedBox(height: 12),
                          _DateTimeField(
                            label: 'Serienende',
                            dateOnly: true,
                            value: recurrenceUntil,
                            onChanged: (value) =>
                                setState(() => recurrenceUntil = value),
                          ),
                          if (frequency == RecurrenceFrequency.custom) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (var day = 1; day <= 7; day++)
                                  FilterChip(
                                    label: Text(
                                      const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
                                          [day - 1],
                                    ),
                                    selected: weekdays.contains(day),
                                    onSelected: (selected) => setState(() {
                                      selected
                                          ? weekdays.add(day)
                                          : weekdays.remove(day);
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  void _save() {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (teamIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mindestens eine Mannschaft auswählen.')),
      );
      return;
    }
    if (endAt != null && endAt!.isBefore(startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Das Ende liegt vor dem Beginn.')),
      );
      return;
    }
    if (recurring && recurrenceUntil == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte ein Serienende auswählen.')),
      );
      return;
    }
    Navigator.pop(
      context,
      EventWriteData(
        category: category,
        title: title.text.trim(),
        startAt: startAt,
        endAt: endAt,
        meetingAt: meetingAt,
        location: location.text.trim(),
        teamIds: teamIds.toList(),
        address: _optional(address),
        mapUrl: _optional(mapUrl),
        homeAway: homeAway,
        opponent: _optional(opponent),
        venue: _optional(venue),
        contactName: _optional(contactName),
        contactPhone: _optional(contactPhone),
        description: _optional(description),
        equipment: _optional(equipment),
        clothing: _optional(clothing),
        catering: _optional(catering),
        carpoolRequired: carpoolRequired,
        maxParticipants: int.tryParse(maxParticipants.text.trim()),
        responseDeadline: responseDeadline,
        internalNote: _optional(internalNote),
        visibility: visibility,
        reminderMinutes: reminderMinutes.toList(),
        attachmentName: _optional(attachmentName),
        attachmentUrl: _optional(attachmentUrl),
        recurrence: recurring
            ? EventRecurrenceDraft(
                frequency: frequency,
                until: recurrenceUntil!,
                interval: interval,
                weekdays: weekdays.toList(),
              )
            : null,
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.dateOnly = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final initial = value ?? DateTime.now().add(const Duration(days: 1));
        final date = await showDatePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 1095)),
          initialDate: initial,
        );
        if (date == null || !context.mounted) return;
        if (dateOnly) {
          onChanged(date);
          return;
        }
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
        );
        if (time == null) return;
        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: allowClear && value != null
              ? IconButton(
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.clear_rounded),
                )
              : const Icon(Icons.calendar_today_rounded),
        ),
        child: Text(
          value == null
              ? 'Auswählen'
              : dateOnly
                  ? _fullDate(value!)
                  : '${_fullDate(value!)} · ${_time(value!)} Uhr',
        ),
      ),
    );
  }
}

class _AttendanceDialog extends StatefulWidget {
  const _AttendanceDialog({required this.players, required this.event});

  final List<PlayerModel> players;
  final EventModel event;

  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  late String playerId;
  AttendanceStatus status = AttendanceStatus.yes;
  final reason = TextEditingController();
  bool goalkeeperAvailable = false;

  @override
  void initState() {
    super.initState();
    playerId = widget.players.first.id;
    final existing = widget.event.attendanceFor(playerId);
    status = existing?.status ?? AttendanceStatus.yes;
    reason.text = existing?.reason ?? '';
    goalkeeperAvailable = existing?.goalkeeperAvailable ?? false;
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rückmeldung abgeben'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: playerId,
            decoration: const InputDecoration(labelText: 'Spieler/in'),
            items: [
              for (final player in widget.players)
                DropdownMenuItem(
                  value: player.id,
                  child: Text(player.fullName),
                ),
            ],
            onChanged: (value) => setState(() {
              playerId = value ?? playerId;
              final existing = widget.event.attendanceFor(playerId);
              status = existing?.status ?? AttendanceStatus.yes;
              reason.text = existing?.reason ?? '';
              goalkeeperAvailable = existing?.goalkeeperAvailable ?? false;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AttendanceStatus>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final value in AttendanceStatus.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) =>
                setState(() => status = value ?? status),
          ),
          if (status == AttendanceStatus.no) ...[
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration:
                  const InputDecoration(labelText: 'Grund (optional)'),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Als Torhüter verfügbar'),
            value: goalkeeperAvailable,
            onChanged: (value) =>
                setState(() => goalkeeperAvailable = value ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _AttendanceDraft(
              playerId: playerId,
              status: status,
              reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
              goalkeeperAvailable: goalkeeperAvailable,
            ),
          ),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _AttendanceDraft {
  const _AttendanceDraft({
    required this.playerId,
    required this.status,
    required this.goalkeeperAvailable,
    this.reason,
  });

  final String playerId;
  final AttendanceStatus status;
  final String? reason;
  final bool goalkeeperAvailable;
}

class _CarpoolDialog extends StatefulWidget {
  const _CarpoolDialog({required this.event});

  final EventModel event;

  @override
  State<_CarpoolDialog> createState() => _CarpoolDialogState();
}

class _CarpoolDialogState extends State<_CarpoolDialog> {
  final location = TextEditingController();
  final notes = TextEditingController();
  int seats = 2;
  late DateTime departureAt;

  @override
  void initState() {
    super.initState();
    departureAt =
        widget.event.meetingAt ?? widget.event.startAt.subtract(const Duration(minutes: 30));
  }

  @override
  void dispose() {
    location.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fahrt anbieten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: seats,
            decoration: const InputDecoration(labelText: 'Freie Plätze'),
            items: [
              for (var value = 1; value <= 8; value++)
                DropdownMenuItem(value: value, child: Text('$value')),
            ],
            onChanged: (value) => setState(() => seats = value ?? seats),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: location,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Abfahrtsort'),
          ),
          const SizedBox(height: 12),
          _DateTimeField(
            label: 'Abfahrtszeit',
            value: departureAt,
            onChanged: (value) =>
                setState(() => departureAt = value ?? departureAt),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            decoration: const InputDecoration(labelText: 'Hinweis (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: location.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _CarpoolDraft(
                      seats: seats,
                      location: location.text.trim(),
                      departureAt: departureAt,
                      notes:
                          notes.text.trim().isEmpty ? null : notes.text.trim(),
                    ),
                  ),
          child: const Text('Anbieten'),
        ),
      ],
    );
  }
}

class _CarpoolDraft {
  const _CarpoolDraft({
    required this.seats,
    required this.location,
    required this.departureAt,
    this.notes,
  });

  final int seats;
  final String location;
  final DateTime departureAt;
  final String? notes;
}

class _PlayerSelectionDialog extends StatefulWidget {
  const _PlayerSelectionDialog({
    required this.title,
    required this.players,
  });

  final String title;
  final List<PlayerModel> players;

  @override
  State<_PlayerSelectionDialog> createState() =>
      _PlayerSelectionDialogState();
}

class _PlayerSelectionDialogState extends State<_PlayerSelectionDialog> {
  late String playerId;

  @override
  void initState() {
    super.initState();
    playerId = widget.players.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: DropdownButtonFormField<String>(
        initialValue: playerId,
        decoration: const InputDecoration(labelText: 'Spieler/in'),
        items: [
          for (final player in widget.players)
            DropdownMenuItem(
              value: player.id,
              child: Text(player.fullName),
            ),
        ],
        onChanged: (value) => setState(() => playerId = value ?? playerId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, playerId),
          child: const Text('Anfragen'),
        ),
      ],
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.recurring});

  final bool recurring;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final reason = TextEditingController();
  bool entireSeries = false;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Termin absagen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: reason,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Grund'),
          ),
          if (widget.recurring)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Diesen und alle folgenden Termine absagen'),
              value: entireSeries,
              onChanged: (value) =>
                  setState(() => entireSeries = value ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _CancelDraft(
                      reason: reason.text.trim(),
                      entireSeries: entireSeries,
                    ),
                  ),
          child: const Text('Absagen'),
        ),
      ],
    );
  }
}

class _CancelDraft {
  const _CancelDraft({
    required this.reason,
    required this.entireSeries,
  });

  final String reason;
  final bool entireSeries;
}

Future<bool?> _seriesScope(BuildContext context, String action) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$action für Serientermin'),
      content: const Text(
        'Soll nur dieser Termin oder dieser und alle folgenden Termine geändert werden?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nur dieser'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Gesamte Serie'),
        ),
      ],
    ),
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _monday(DateTime value) =>
    _dateOnly(value).subtract(Duration(days: value.weekday - 1));

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _fullDate(DateTime value) =>
    '${_weekday(value)}, ${value.day}. ${_month(value.month)} ${value.year}';

String _weekday(DateTime value) => const [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ][value.weekday - 1];

String _month(int value) => const [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ][value - 1];

String _periodLabel(CalendarView view, DateTime value) => switch (view) {
      CalendarView.day => '${value.day}. ${_month(value.month)} ${value.year}',
      CalendarView.week =>
        '${_monday(value).day}. ${_month(_monday(value).month)} – ${_monday(value).add(const Duration(days: 6)).day}. ${_month(_monday(value).add(const Duration(days: 6)).month)}',
      CalendarView.month || CalendarView.agenda =>
        '${_month(value.month)} ${value.year}',
    };

Color _categoryColor(EventCategory category) {
  if (category == EventCategory.training) return AppColors.teal;
  if (category.isMatch) return AppColors.blue;
  if (category == EventCategory.parentsMeeting ||
      category == EventCategory.teamMeeting) {
    return const Color(0xFF7C4DFF);
  }
  return AppColors.orange;
}

IconData _categoryIcon(EventCategory category) {
  if (category == EventCategory.training) return Icons.fitness_center_rounded;
  if (category.isMatch) return Icons.sports_soccer_rounded;
  if (category == EventCategory.trip) return Icons.hiking_rounded;
  if (category == EventCategory.photoSession) return Icons.photo_camera_rounded;
  return Icons.celebration_rounded;
}

IconData _attendanceIcon(AttendanceStatus status) => switch (status) {
      AttendanceStatus.yes => Icons.check_circle_rounded,
      AttendanceStatus.no => Icons.cancel_rounded,
      AttendanceStatus.maybe => Icons.help_rounded,
      AttendanceStatus.unknown => Icons.hourglass_empty_rounded,
    };

Color _attendanceColor(AttendanceStatus status) => switch (status) {
      AttendanceStatus.yes => AppColors.teal,
      AttendanceStatus.no => Colors.redAccent,
      AttendanceStatus.maybe => AppColors.orange,
      AttendanceStatus.unknown => AppColors.muted,
    };

String _homeAway(HomeAway value) => switch (value) {
      HomeAway.home => 'Heim',
      HomeAway.away => 'Auswärts',
      HomeAway.neutral => 'Neutral',
    };

String _carpoolStatus(CarpoolRequestStatus value) => switch (value) {
      CarpoolRequestStatus.requested => 'angefragt',
      CarpoolRequestStatus.confirmed => 'bestätigt',
      CarpoolRequestStatus.declined => 'abgelehnt',
      CarpoolRequestStatus.cancelled => 'storniert',
    };
