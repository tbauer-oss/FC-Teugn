import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/data_repository.dart';
import '../../core/meeting_time.dart';
import '../../core/models/communication.dart';
import '../../core/models/competition.dart';
import '../../core/models/emergency.dart';
import '../../core/models/event.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../../core/regular_training_schedule.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../shared/attendance_reminder_action.dart';
import '../shared/page_scaffold.dart';
import 'tournament_plan_browser_page.dart';

enum CalendarView { day, week, month, year, agenda }

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({
    super.key,
    required this.canManage,
    this.initialEventId,
  });

  final bool canManage;
  final String? initialEventId;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  CalendarView view = CalendarView.month;
  DateTime cursor = DateTime.now();
  bool savingEvent = false;
  int _navigationDirection = 1;
  final selectedCategories = <EventCategory>{};
  final selectedTeams = <String>{};
  bool _initialEventOpened = false;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final organization = ref.watch(organizationProvider).valueOrNull;
    final canManage = widget.canManage &&
        (organization?.can('MANAGE_EVENTS') ?? widget.canManage);

    return PageScaffold(
      title: 'Vereinskalender',
      subtitle:
          'Termine, Rückmeldungen und Fahrgemeinschaften an einem verlässlichen Ort.',
      denseMobileHeader: true,
      action: _CalendarPageActions(
        canManage: canManage,
        saving: savingEvent,
        canCreate: organization != null,
        onSubscribe: _createSubscription,
        onCreate:
            organization == null ? null : () => _createEvent(organization),
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
            onPrevious: () => _navigate(-1),
            onNext: () => _navigate(1),
            onToday: () => setState(() => cursor = DateTime.now()),
            onCategoriesChanged: (values) => setState(() => selectedCategories
              ..clear()
              ..addAll(values)),
            onTeamsChanged: (values) => setState(() => selectedTeams
              ..clear()
              ..addAll(values)),
          ),
          const SizedBox(height: 18),
          events.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: LogoLoadingPanel(message: 'Termine werden geladen …'),
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
              final calendarItems = _withRegularTrainings(
                items,
                organization,
              );
              _openInitialEvent(calendarItems);
              final filtered = calendarItems.where(_matchesFilters).toList()
                ..sort((a, b) => a.startAt.compareTo(b.startAt));
              return switch (view) {
                CalendarView.month => _SwipeableMonthView(
                    cursor: cursor,
                    navigationDirection: _navigationDirection,
                    onPrevious: () => _navigate(-1),
                    onNext: () => _navigate(1),
                    previousChild: _MonthView(
                      key: ValueKey(
                        'calendar-${cursor.year}-${cursor.month - 1}',
                      ),
                      cursor: DateTime(cursor.year, cursor.month - 1, 1),
                      events: filtered,
                      onOpen: _openEvent,
                    ),
                    nextChild: _MonthView(
                      key: ValueKey(
                        'calendar-${cursor.year}-${cursor.month + 1}',
                      ),
                      cursor: DateTime(cursor.year, cursor.month + 1, 1),
                      events: filtered,
                      onOpen: _openEvent,
                    ),
                    child: _MonthView(
                      key: ValueKey('calendar-${cursor.year}-${cursor.month}'),
                      cursor: cursor,
                      events: filtered,
                      onOpen: _openEvent,
                    ),
                  ),
                CalendarView.week => _WeekView(
                    cursor: cursor,
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
                        .where((event) => !event.startAt.isBefore(
                            DateTime.now().subtract(const Duration(days: 1))))
                        .toList(),
                    onOpen: _openEvent,
                  ),
                CalendarView.year => _YearView(
                    cursor: cursor,
                    events: filtered,
                    onMonthSelected: (month) => setState(() {
                      cursor = DateTime(cursor.year, month);
                      view = CalendarView.month;
                    }),
                  ),
              };
            },
          ),
        ],
      ),
    );
  }

  void _openInitialEvent(List<EventModel> events) {
    if (_initialEventOpened || widget.initialEventId == null) return;
    final event =
        events.where((item) => item.id == widget.initialEventId).firstOrNull;
    if (event == null) return;
    _initialEventOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        cursor = event.startAt;
        view = CalendarView.agenda;
      });
      _openEvent(event);
    });
  }

  List<EventModel> _withRegularTrainings(
    List<EventModel> events,
    OrganizationContext? organization,
  ) {
    if (organization == null) return events;
    final result =
        events.where((event) => !event.isHiddenRegularOccurrence).toList();
    for (final team in organization.teams) {
      final seasonStart = team.seasonStartDate ?? organization.season.startDate;
      final seasonEnd = team.seasonEndDate ?? organization.season.endDate;
      void addSchedule(
        List<String> rawSlots,
        String? fallbackLocation,
        DateTime start,
        DateTime end, {
        required bool indoor,
        DateTime? pauseStart,
        DateTime? pauseEnd,
      }) {
        for (final rawSlot in rawSlots) {
          final slot = RegularTrainingSlot.tryParse(
            rawSlot,
            fallbackLocation: fallbackLocation,
          );
          if (slot == null) continue;
          for (final occurrence in slot.occurrences(
            start,
            end,
          )) {
            if (pauseStart != null &&
                pauseEnd != null &&
                !occurrence.$1.isBefore(pauseStart) &&
                !occurrence.$1.isAfter(pauseEnd)) {
              continue;
            }
            final alreadyStored = result.any(
              (event) =>
                  event.category == EventCategory.training &&
                  (event.teamId == team.id ||
                      event.targetTeams
                          .any((target) => target.id == team.id)) &&
                  event.startAt.difference(occurrence.$1).abs() <
                      const Duration(minutes: 5),
            );
            if (alreadyStored) continue;
            result.add(
              EventModel(
                id: 'training-plan:${team.id}:'
                    '${occurrence.$1.millisecondsSinceEpoch}',
                teamId: team.id,
                type: EventType.training,
                category: EventCategory.training,
                status: EventStatus.scheduled,
                visibility: EventVisibility.team,
                title: 'Training · ${team.displayName}',
                startAt: occurrence.$1,
                endAt: occurrence.$2,
                location: slot.location,
                attendanceFinalized: false,
                targetTeams: [
                  EventTeam(
                    id: team.id,
                    name: team.name,
                    ageGroupCode: team.ageGroup.code,
                  ),
                ],
                attachments: const [],
                attendance: const [],
                attendanceSummary: const AttendanceSummary(),
                missingAttendance: const [],
                carpoolOffers: const [],
                capabilities: EventCapabilities(
                  canManage: organization.can('CANCEL_TRAINING_OCCURRENCE'),
                  canCancel: organization.can('CANCEL_TRAINING_OCCURRENCE'),
                ),
                reminderMinutes: const [],
                description:
                    'Reguläre ${indoor ? 'Hallen' : 'Platz'}trainingszeit '
                    'laut Belegungsplan der Saison '
                    '${organization.season.name}.',
              ),
            );
          }
        }
      }

      addSchedule(
        team.trainingTimes,
        team.trainingLocation,
        seasonStart,
        seasonEnd,
        indoor: false,
        pauseStart: team.indoorSeasonStartDate,
        pauseEnd: team.indoorSeasonEndDate,
      );
      if (team.indoorSeasonStartDate != null &&
          team.indoorSeasonEndDate != null) {
        addSchedule(
          team.indoorTrainingTimes,
          team.indoorTrainingLocation,
          team.indoorSeasonStartDate!,
          team.indoorSeasonEndDate!,
          indoor: true,
        );
      }

      EventModel seasonMarker(
        String id,
        String title,
        DateTime date,
        EventCategory category,
      ) =>
          EventModel(
            id: '$id:${team.id}:${date.millisecondsSinceEpoch}',
            teamId: team.id,
            type: EventType.event,
            category: category,
            status: EventStatus.scheduled,
            visibility: EventVisibility.team,
            title: '$title · ${team.displayName}',
            startAt: DateTime(date.year, date.month, date.day, 9),
            endAt: DateTime(date.year, date.month, date.day, 10),
            location: '',
            attendanceFinalized: false,
            targetTeams: [
              EventTeam(
                id: team.id,
                name: team.name,
                ageGroupCode: team.ageGroup.code,
              ),
            ],
            attachments: const [],
            attendance: const [],
            attendanceSummary: const AttendanceSummary(),
            missingAttendance: const [],
            carpoolOffers: const [],
            capabilities: const EventCapabilities(),
            reminderMinutes: const [],
            description: 'Automatische Markierung der Mannschaftssaison.',
          );
      result
        ..add(seasonMarker(
          'season-start',
          'Saisonanfang',
          seasonStart,
          EventCategory.specialEvent,
        ))
        ..add(seasonMarker(
          'season-end',
          'Saisonende',
          seasonEnd,
          EventCategory.seasonClosing,
        ));
    }
    return result;
  }

  bool _matchesFilters(EventModel event) {
    final categoryMatches = selectedCategories.isEmpty ||
        selectedCategories.contains(event.category);
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
        CalendarView.month ||
        CalendarView.agenda =>
          DateTime(value.year, value.month + direction, 1),
        CalendarView.year => DateTime(value.year + direction),
      };

  void _navigate(int direction) => setState(() {
        _navigationDirection = direction;
        cursor = _shift(cursor, direction);
      });

  Future<void> _createEvent(OrganizationContext organization) async {
    final draft = await showDialog<EventWriteData>(
      context: context,
      builder: (context) => EventEditorDialog(
        repository: ref.read(repositoryProvider),
        teams: organization.teams,
        initialTeamId: organization.currentTeam.id,
        seasonName: organization.season.name,
        seasonEnd: organization.currentTeam.seasonEndDate ??
            organization.season.endDate,
      ),
    );
    if (draft == null) return;
    setState(() => savingEvent = true);
    List<EventModel> created;
    try {
      created = await ref.read(repositoryProvider).createEvent(draft);
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_apiErrorMessage(
            error,
            'Der Termin konnte nicht gespeichert werden.',
          ))),
        );
      }
      if (mounted) setState(() => savingEvent = false);
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Der Termin konnte nicht gespeichert werden.'),
          ),
        );
      }
      if (mounted) setState(() => savingEvent = false);
      return;
    }

    final createdIds = created.map((event) => event.id).toSet();
    ref.invalidate(eventsProvider);
    try {
      final refreshed = await ref.read(eventsProvider.future);
      final confirmedIds = refreshed.map((event) => event.id).toSet();
      if (!confirmedIds.containsAll(createdIds)) {
        throw StateError('Mindestens ein Serientermin fehlt im Kalender.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created.length == 1
                  ? draft.requestPitchConflictApprovals
                      ? 'Termin gespeichert. Die Platzfreigabe wurde beim '
                          'zuständigen Haupttrainer angefragt.'
                      : 'Termin wurde gespeichert und bestätigt.'
                  : '${created.length} Serientermine wurden gespeichert und bestätigt.',
            ),
          ),
        );
      }
    } catch (_) {
      ref.invalidate(eventsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created.length == 1
                  ? 'Termin wurde gespeichert. Der Kalender wird neu geladen.'
                  : '${created.length} Serientermine wurden gespeichert. '
                      'Der Kalender wird neu geladen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => savingEvent = false);
    }
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
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_apiErrorMessage(
            error,
            'Die Änderung konnte nicht gespeichert werden.',
          ))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Änderung konnte nicht bestätigt werden.'),
          ),
        );
      }
    }
  }
}

class _CalendarPageActions extends StatelessWidget {
  const _CalendarPageActions({
    required this.canManage,
    required this.saving,
    required this.canCreate,
    required this.onSubscribe,
    required this.onCreate,
  });

  final bool canManage;
  final bool saving;
  final bool canCreate;
  final VoidCallback onSubscribe;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    final subscribe = OutlinedButton.icon(
      onPressed: onSubscribe,
      icon: const Icon(Icons.event_repeat_rounded, size: 19),
      label: AdaptiveButtonLabel(mobile ? 'Abo' : 'Kalender-Abo'),
    );
    final create = FilledButton.icon(
      onPressed: canCreate && !saving ? onCreate : null,
      icon: saving
          ? const LogoLoadingIndicator(
              size: 22,
              semanticsLabel: 'Termin wird gespeichert',
            )
          : const Icon(Icons.add_rounded, size: 20),
      label: AdaptiveButtonLabel(saving ? 'Speichert…' : 'Termin anlegen'),
    );
    if (!mobile) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [subscribe, if (canManage) create],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: subscribe),
        if (canManage) ...[
          const SizedBox(width: 8),
          Expanded(flex: 3, child: create),
        ],
      ],
    );
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            final viewPicker = DropdownButton<CalendarView>(
              value: view,
              borderRadius: BorderRadius.circular(14),
              items: [
                for (final value in CalendarView.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_calendarViewLabel(value)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onViewChanged(value);
              },
            );
            final filters = [
              _FilterButton<EventCategory>(
                label: 'Kategorien',
                icon: Icons.category_outlined,
                values: EventCategory.values,
                selected: selectedCategories,
                itemLabel: (item) => '${_categoryEmoji(item)} ${item.label}',
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
            ];
            if (compact) {
              return Column(
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Zurück',
                        onPressed: onPrevious,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
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
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: onToday,
                          child: const Text('Heute'),
                        ),
                        const SizedBox(width: 8),
                        viewPicker,
                        const SizedBox(width: 10),
                        ...filters.expand(
                          (item) => [item, const SizedBox(width: 8)],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Wrap(
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
                SegmentedButton<CalendarView>(
                  segments: const [
                    ButtonSegment(value: CalendarView.day, label: Text('Tag')),
                    ButtonSegment(
                        value: CalendarView.week, label: Text('Woche')),
                    ButtonSegment(
                        value: CalendarView.month, label: Text('Monat')),
                    ButtonSegment(
                        value: CalendarView.year, label: Text('Jahr')),
                    ButtonSegment(
                        value: CalendarView.agenda, label: Text('Agenda')),
                  ],
                  selected: {view},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => onViewChanged(value.first),
                ),
                ...filters,
              ],
            );
          },
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

class _SwipeableMonthView extends StatefulWidget {
  const _SwipeableMonthView({
    required this.cursor,
    required this.navigationDirection,
    required this.onPrevious,
    required this.onNext,
    required this.previousChild,
    required this.child,
    required this.nextChild,
  });

  final DateTime cursor;
  final int navigationDirection;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget previousChild;
  final Widget child;
  final Widget nextChild;

  @override
  State<_SwipeableMonthView> createState() => _SwipeableMonthViewState();
}

class _SwipeableMonthViewState extends State<_SwipeableMonthView>
    with TickerProviderStateMixin {
  double _horizontalDistance = 0;
  double _verticalDistance = 0;
  double _dragOffset = 0;
  double _viewportWidth = 1;
  double _pendingSwipeProgress = 0;
  bool _axisDecided = false;
  bool _horizontalGesture = false;
  late final AnimationController _pageController;
  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;
  late Widget _currentPage;
  Widget? _outgoingPage;
  int _slideDirection = 1;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.child;
    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _outgoingPage != null &&
            mounted) {
          setState(() => _outgoingPage = null);
        }
      });
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final animation = _snapAnimation;
        if (animation != null && mounted) {
          setState(() => _dragOffset = animation.value);
        }
      });
  }

  @override
  void didUpdateWidget(covariant _SwipeableMonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.key != widget.child.key) {
      _outgoingPage = _currentPage;
      _currentPage = widget.child;
      _slideDirection = widget.navigationDirection >= 0 ? 1 : -1;
      final progress = _pendingSwipeProgress.clamp(0.0, .82);
      _pendingSwipeProgress = 0;
      _dragOffset = 0;
      _pageController.forward(from: progress);
    } else {
      _currentPage = widget.child;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  void _beginSwipe() {
    _snapController.stop();
    _snapAnimation = null;
    _horizontalDistance = 0;
    _verticalDistance = 0;
    _axisDecided = false;
    _horizontalGesture = false;
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  void _updateSwipe(PointerMoveEvent event) {
    _horizontalDistance += event.delta.dx;
    _verticalDistance += event.delta.dy;
    if (!_axisDecided &&
        (_horizontalDistance.abs() > 8 || _verticalDistance.abs() > 8)) {
      _axisDecided = true;
      _horizontalGesture =
          _horizontalDistance.abs() > _verticalDistance.abs() * 1.15;
    }
    if (!_horizontalGesture) return;
    final limit = _viewportWidth * .92;
    setState(() {
      _dragOffset = _horizontalDistance.clamp(-limit, limit).toDouble();
    });
  }

  void _snapBack() {
    if (_dragOffset == 0) return;
    _snapAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0);
  }

  void _finishSwipe() {
    final distance = _horizontalDistance;
    final verticalDistance = _verticalDistance;
    _horizontalDistance = 0;
    _verticalDistance = 0;
    _axisDecided = false;
    final isHorizontalSwipe = _horizontalGesture &&
        distance.abs() >= (_viewportWidth * .16).clamp(44, 72) &&
        distance.abs() > verticalDistance.abs() * 1.15;
    _horizontalGesture = false;
    final direction = isHorizontalSwipe ? distance.sign : 0;
    if (direction == 0) {
      _snapBack();
      return;
    }
    _pendingSwipeProgress =
        (_dragOffset.abs() / _viewportWidth).clamp(0.0, .82);
    if (direction < 0) {
      widget.onNext();
    } else if (direction > 0) {
      widget.onPrevious();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) return widget.child;
    return Semantics(
      label:
          'Monatskalender ${_periodLabel(CalendarView.month, widget.cursor)}. '
          'Nach links oder rechts wischen, um den Monat zu wechseln.',
      child: GestureDetector(
        // Nur horizontale Monatsgesten werden übernommen. Reine vertikale
        // Bewegungen bleiben beim umgebenden Seiten-Scroll, damit auch die
        // Terminliste unter dem Kalender jederzeit hoch- und runterscrollt.
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        child: Listener(
          key: const ValueKey('calendar-month-swipe-surface'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _beginSwipe(),
          onPointerMove: _updateSwipe,
          onPointerUp: (_) => _finishSwipe(),
          onPointerCancel: (_) {
            _horizontalDistance = 0;
            _verticalDistance = 0;
            _horizontalGesture = false;
            _axisDecided = false;
            _snapBack();
          },
          child: ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewportWidth = constraints.maxWidth;
                  final travel = constraints.maxWidth;
                  return AnimatedBuilder(
                    key: const ValueKey('calendar-month-page-transition'),
                    animation: _pageController,
                    builder: (context, _) {
                      if (_outgoingPage == null && _dragOffset != 0) {
                        final dragProgress =
                            (_dragOffset.abs() / travel).clamp(0.0, 1.0);
                        final movingForward = _dragOffset < 0;
                        final adjacentPage = movingForward
                            ? widget.nextChild
                            : widget.previousChild;
                        final adjacentOffset =
                            _dragOffset + (movingForward ? travel : -travel);
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            const Positioned.fill(
                              child: ColoredBox(
                                color: AppColors.background,
                              ),
                            ),
                            Opacity(
                              opacity: 1 - dragProgress * .16,
                              child: Transform.translate(
                                key: const ValueKey(
                                  'calendar-month-dragging-page',
                                ),
                                offset: Offset(_dragOffset, 0),
                                child: _currentPage,
                              ),
                            ),
                            IgnorePointer(
                              child: Transform.translate(
                                key: const ValueKey(
                                  'calendar-month-adjacent-page',
                                ),
                                offset: Offset(adjacentOffset, 0),
                                child: adjacentPage,
                              ),
                            ),
                          ],
                        );
                      }
                      final progress =
                          Curves.easeInOutCubicEmphasized.transform(
                        _pageController.value,
                      );
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          if (_outgoingPage != null)
                            IgnorePointer(
                              child: Opacity(
                                opacity: 1 - progress * .55,
                                child: Transform.translate(
                                  offset: Offset(
                                    -_slideDirection * progress * travel,
                                    0,
                                  ),
                                  child: _outgoingPage,
                                ),
                              ),
                            ),
                          Opacity(
                            opacity: .55 + progress * .45,
                            child: Transform.translate(
                              offset: Offset(
                                _slideDirection * (1 - progress) * travel,
                                0,
                              ),
                              child: _currentPage,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    super.key,
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
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobileMonthView(
        cursor: cursor,
        events: events,
        onOpen: onOpen,
      );
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1050,
          child: Column(
            children: [
              _CalendarCategoryLegend(
                categories: events.map((event) => event.category),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  for (final label in [
                    'Mo',
                    'Di',
                    'Mi',
                    'Do',
                    'Fr',
                    'Sa',
                    'So'
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
                  final dayEvents = events
                      .where((event) => _sameDay(event.startAt, date))
                      .toList();
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

class _MobileMonthView extends StatelessWidget {
  const _MobileMonthView({
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
    final dayCount = DateTime(cursor.year, cursor.month + 1, 0).day;
    final totalCells = ((offset + dayCount + 6) ~/ 7) * 7;
    final monthEvents = events
        .where(
          (event) =>
              event.startAt.year == cursor.year &&
              event.startAt.month == cursor.month,
        )
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: Column(
              children: [
                _CalendarCategoryLegend(
                  categories: monthEvents.map((event) => event.category),
                  compact: true,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final label in const [
                      'Mo',
                      'Di',
                      'Mi',
                      'Do',
                      'Fr',
                      'Sa',
                      'So'
                    ])
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    final day = index - offset + 1;
                    if (day < 1 || day > dayCount) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime(cursor.year, cursor.month, day);
                    final dayEvents = monthEvents
                        .where((event) => _sameDay(event.startAt, date))
                        .toList();
                    final today = _sameDay(date, DateTime.now());
                    return Semantics(
                      button: dayEvents.isNotEmpty,
                      label: dayEvents.isEmpty
                          ? '$day, keine Termine'
                          : '$day, ${dayEvents.map((event) => event.category.label).join(', ')}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: dayEvents.isEmpty
                            ? null
                            : () => _showMobileDay(
                                  context,
                                  date,
                                  dayEvents,
                                  onOpen,
                                ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 27,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: today
                                      ? AppColors.yellow
                                      : dayEvents.isNotEmpty
                                          ? _categoryColor(
                                              dayEvents.first.category,
                                            ).withValues(alpha: .10)
                                          : Colors.transparent,
                                  border: dayEvents.isEmpty
                                      ? null
                                      : Border.all(
                                          color: _categoryColor(
                                            dayEvents.first.category,
                                          ).withValues(alpha: .28),
                                        ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$day',
                                  style: const TextStyle(
                                    color: AppColors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (dayEvents.isNotEmpty)
                                _CompactEmojiPreview(events: dayEvents),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Termine im Monat',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (monthEvents.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('In diesem Monat sind keine Termine eingetragen.'),
            ),
          )
        else
          for (final event in monthEvents)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: _EventEmojiBadge(
                  event: event,
                  footer: '${event.startAt.day}.',
                ),
                title: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_time(event.startAt)} Uhr · ${event.location}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onOpen(event),
              ),
            ),
      ],
    );
  }

  void _showMobileDay(
    BuildContext context,
    DateTime date,
    List<EventModel> dayEvents,
    ValueChanged<EventModel> onOpen,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.day}.${date.month}.${date.year}',
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: dayEvents.length,
                  itemBuilder: (context, index) {
                    final event = dayEvents[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _EventEmojiBadge(event: event),
                      title: Text(event.title),
                      subtitle: Text(
                          '${_time(event.startAt)} Uhr · ${event.location}'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onOpen(event);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarCategoryLegend extends StatelessWidget {
  const _CalendarCategoryLegend({
    required this.categories,
    this.compact = false,
  });

  final Iterable<EventCategory> categories;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final present = categories.toSet();
    final ordered =
        EventCategory.values.where(present.contains).toList(growable: false);
    if (ordered.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 10),
        child: const Text(
          'Noch keine Termine in diesem Zeitraum',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return Semantics(
      label: 'Legende der Terminarten',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 12,
            vertical: compact ? 1 : 8,
          ),
          child: Row(
            children: [
              for (var index = 0; index < ordered.length; index++) ...[
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 7 : 9,
                    vertical: compact ? 4 : 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _categoryColor(ordered[index]).withValues(alpha: .09),
                    border: Border.all(
                      color:
                          _categoryColor(ordered[index]).withValues(alpha: .22),
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_categoryEmoji(ordered[index])} ${ordered[index].label}',
                    style: TextStyle(
                      color: _categoryColor(ordered[index]),
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (index != ordered.length - 1)
                  SizedBox(width: compact ? 5 : 7),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactEmojiPreview extends StatelessWidget {
  const _CompactEmojiPreview({required this.events});

  final List<EventModel> events;

  @override
  Widget build(BuildContext context) {
    final emojis = events
        .map((event) => _categoryEmoji(event.category))
        .toSet()
        .take(2)
        .join();
    final overflow = events.length > 2 ? '+${events.length - 2}' : '';
    return Text(
      '$emojis$overflow',
      maxLines: 1,
      style: const TextStyle(
        fontSize: 8,
        height: 1,
        fontWeight: FontWeight.w800,
        color: AppColors.muted,
      ),
    );
  }
}

class _EventEmojiBadge extends StatelessWidget {
  const _EventEmojiBadge({required this.event, this.footer});

  final EventModel event;
  final String? footer;

  @override
  Widget build(BuildContext context) => Semantics(
        label: event.category.label,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _categoryColor(event.category).withValues(alpha: .10),
            border: Border.all(
              color: _categoryColor(event.category).withValues(alpha: .22),
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _categoryEmoji(event.category),
                style: TextStyle(fontSize: footer == null ? 21 : 18),
              ),
              if (footer != null)
                Text(
                  footer!,
                  style: TextStyle(
                    height: .9,
                    color: _categoryColor(event.category),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      );
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
    const previewLimit = 2;
    final hasOverflow = events.length > previewLimit;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('calendar-day-${date.toIso8601String()}'),
        onTap: hasOverflow ? () => _showAllEvents(context) : null,
        child: Container(
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
              for (final event in events.take(previewLimit))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: hasOverflow ? null : () => onOpen(event),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _categoryColor(event.category).withValues(
                          alpha: event.isCancelled ? .07 : .13,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${_categoryEmoji(event.category)} ${_time(event.startAt)} ${event.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          decoration: event.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                          color: _categoryColor(event.category),
                        ),
                      ),
                    ),
                  ),
                ),
              if (hasOverflow)
                Text(
                  '+ ${events.length - previewLimit} weitere',
                  key: const ValueKey('calendar-day-overflow'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllEvents(BuildContext context) async {
    final sortedEvents = [...events]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final selected = await showDialog<EventModel>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('calendar-day-events-dialog'),
        title: Text('${_weekday(date)}, ${date.day}. ${_month(date.month)}'),
        content: SizedBox(
          width: 440,
          height: sortedEvents.length <= 4 ? sortedEvents.length * 72.0 : 360,
          child: ListView.separated(
            itemCount: sortedEvents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = sortedEvents[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _EventEmojiBadge(event: event),
                title: Text(event.title),
                subtitle: Text(
                  '${_time(event.startAt)} Uhr · ${event.location}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(dialogContext, event),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
    if (selected != null) onOpen(selected);
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.cursor,
    required this.events,
    required this.onOpen,
  });

  static const hourHeight = 52.0;
  static const timeColumnWidth = 62.0;
  static const dayColumnWidth = 146.0;

  final DateTime cursor;
  final List<EventModel> events;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final monday = _monday(cursor);
    final dates = List.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
    const bodyHeight = 24 * hourHeight;
    const calendarWidth = timeColumnWidth + 7 * dayColumnWidth;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: calendarWidth,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: timeColumnWidth, height: 68),
                  for (final date in dates)
                    SizedBox(
                      width: dayColumnWidth,
                      height: 68,
                      child: _WeekDayHeader(date: date),
                    ),
                ],
              ),
              const Divider(height: 1),
              SizedBox(
                height: bodyHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: timeColumnWidth,
                      height: bodyHeight,
                      child: _TimeScale(),
                    ),
                    for (final date in dates)
                      SizedBox(
                        width: dayColumnWidth,
                        height: bodyHeight,
                        child: _WeekDayColumn(
                          date: date,
                          events: events
                              .where((event) => _sameDay(event.startAt, date))
                              .toList(),
                          onOpen: onOpen,
                        ),
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

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final today = _sameDay(date, DateTime.now());
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekday(date).substring(0, 2).toUpperCase(),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: today ? AppColors.yellow : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${date.day}',
                style: const TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeScale extends StatelessWidget {
  const _TimeScale();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var hour = 0; hour < 24; hour++)
          Positioned(
            top: hour * _WeekView.hourHeight - 7,
            right: 9,
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.date,
    required this.events,
    required this.onOpen,
  });

  final DateTime date;
  final List<EventModel> events;
  final ValueChanged<EventModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _sameDay(date, now)
                  ? AppColors.yellow.withValues(alpha: .035)
                  : Colors.white,
              border: const Border(
                left: BorderSide(color: AppColors.line),
              ),
            ),
          ),
        ),
        for (var hour = 0; hour < 24; hour++)
          Positioned(
            left: 0,
            right: 0,
            top: hour * _WeekView.hourHeight,
            child: const Divider(height: 1, color: AppColors.line),
          ),
        for (final event in events) _eventBlock(context, event),
        if (_sameDay(date, now))
          Positioned(
            top: (now.hour + now.minute / 60) * _WeekView.hourHeight,
            left: 0,
            right: 0,
            child: Container(height: 2, color: Colors.redAccent),
          ),
      ],
    );
  }

  Widget _eventBlock(BuildContext context, EventModel event) {
    final start = event.startAt.hour + event.startAt.minute / 60;
    final durationMinutes = (event.endAt == null
            ? 60
            : event.endAt!.difference(event.startAt).inMinutes.clamp(30, 720))
        .toDouble();
    final height = (durationMinutes / 60 * _WeekView.hourHeight)
        .clamp(34.0, 310.0)
        .toDouble();
    final color = _categoryColor(event.category);
    return Positioned(
      top: start * _WeekView.hourHeight + 1,
      left: 4,
      right: 4,
      height: height,
      child: Material(
        color: color.withValues(alpha: event.isCancelled ? .08 : .16),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onOpen(event),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: height < 52 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    decoration:
                        event.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (height >= 52)
                  Text(
                    '${_time(event.startAt)} · ${event.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 9),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YearView extends StatelessWidget {
  const _YearView({
    required this.cursor,
    required this.events,
    required this.onMonthSelected,
  });

  final DateTime cursor;
  final List<EventModel> events;
  final ValueChanged<int> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 500
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.08,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            final month = index + 1;
            return _MiniMonth(
              year: cursor.year,
              month: month,
              events: events
                  .where((event) =>
                      event.startAt.year == cursor.year &&
                      event.startAt.month == month)
                  .toList(),
              onTap: () => onMonthSelected(month),
            );
          },
        );
      },
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.year,
    required this.month,
    required this.events,
    required this.onTap,
  });

  final int year;
  final int month;
  final List<EventModel> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month);
    final offset = first.weekday - 1;
    final days = DateTime(year, month + 1, 0).day;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _month(month),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (events.isNotEmpty) Chip(label: Text('${events.length}')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final label in ['M', 'D', 'M', 'D', 'F', 'S', 'S'])
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                  ),
                  itemCount: 42,
                  itemBuilder: (context, index) {
                    final day = index - offset + 1;
                    if (day < 1 || day > days) return const SizedBox.shrink();
                    final date = DateTime(year, month, day);
                    final dayEvents = events
                        .where((event) => _sameDay(event.startAt, date))
                        .toList();
                    final today = _sameDay(date, DateTime.now());
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 25,
                          height: 25,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                today ? AppColors.yellow : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$day',
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (dayEvents.isNotEmpty)
                          Positioned(
                            bottom: 1,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _categoryColor(dayEvents.first.category),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
      child:
          const Text('Keine Termine', style: TextStyle(color: AppColors.muted)),
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
                      _categoryEmoji(event.category),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 2),
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
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
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

class EventDetailsDialog extends ConsumerStatefulWidget {
  const EventDetailsDialog({super.key, required this.event});

  final EventModel event;

  @override
  ConsumerState<EventDetailsDialog> createState() => _EventDetailsDialogState();
}

class _EventDetailsDialogState extends ConsumerState<EventDetailsDialog> {
  late EventModel _event;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
  }

  Future<void> _refresh() async {
    final updated = await ref.read(repositoryProvider).event(_event.id);
    if (!mounted) return;
    setState(() => _event = updated);
    ref.invalidate(eventsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final players =
        ref.watch(playersProvider).valueOrNull ?? const <PlayerModel>[];
    final organization = ref.watch(organizationProvider).valueOrNull;
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
                    if (event.capabilities.canOpenEmergencyView) ...[
                      const SizedBox(height: 16),
                      _EmergencyAccessCard(event: event),
                    ],
                    if (event.description != null) ...[
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Beschreibung',
                        child: Text(event.description!),
                      ),
                    ],
                    if (event.meinTurnierplanAttachment != null) ...[
                      const SizedBox(height: 20),
                      _TournamentPlanCard(event: event),
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
                      onRefresh: _refresh,
                    ),
                    const SizedBox(height: 20),
                    _CarpoolSection(
                      event: event,
                      players: players,
                      onRefresh: _refresh,
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

class _TournamentPlanCard extends StatelessWidget {
  const _TournamentPlanCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final attachment = event.meinTurnierplanAttachment!;
    return _Section(
      title: 'Turnierplan & Ergebnisse',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.yellowSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: .28)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final button = FilledButton.icon(
              onPressed: () => openTournamentPlanBrowser(
                context,
                url: attachment.url,
                tournamentName: event.title,
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Live-Turnierplan öffnen'),
            );
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Zeitplan, Spiele, Tabellen und Platzierungen',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  'Die Ansicht bleibt in der App und zeigt immer den aktuellen '
                  'Stand von MeinTurnierplan.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            );
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [info, const SizedBox(height: 14), button],
                  )
                : Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          color: AppColors.gold, size: 34),
                      const SizedBox(width: 14),
                      Expanded(child: info),
                      const SizedBox(width: 14),
                      button,
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class _EmergencyAccessCard extends ConsumerWidget {
  const _EmergencyAccessCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.health_and_safety_rounded,
                color: Color(0xFF9A3412), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Geschützte Notfallansicht',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF7C2D12),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Nur für einen akuten Bedarf: anwesende Spieler, '
                    'Kontaktpersonen und freigegebene medizinische Hinweise. '
                    'Jeder Zugriff wird protokolliert.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF9A3412),
                    ),
                    onPressed: () => _open(context, ref),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Sicher öffnen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _EmergencyPasswordDialog(),
    );
    if (password == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(repositoryProvider);
      final grant = await repository.requestEmergencyAccess(
        eventId: event.id,
        password: password,
      );
      final view = await repository.emergencyView(
        eventId: event.id,
        accessToken: grant.token,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _EmergencyViewDialog(
          view: view,
          expiresAt: grant.expiresAt,
        ),
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      final message =
          data is Map<String, dynamic> ? data['message'] as String? : null;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            message ?? 'Die Notfallansicht konnte nicht geöffnet werden.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Die Notfallansicht konnte nicht geöffnet werden.'),
        ),
      );
    }
  }
}

class _EmergencyPasswordDialog extends StatefulWidget {
  const _EmergencyPasswordDialog();

  @override
  State<_EmergencyPasswordDialog> createState() =>
      _EmergencyPasswordDialogState();
}

class _EmergencyPasswordDialogState extends State<_EmergencyPasswordDialog> {
  final controller = TextEditingController();
  bool obscure = true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final value = controller.text;
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.verified_user_rounded, color: AppColors.blue),
      title: const Text('Identität bestätigen'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gib dein Passwort erneut ein. Der Zugriff gilt anschließend '
              'fünf Minuten und nur für diesen Termin.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: 'Passwort',
                prefixIcon: const Icon(Icons.password_rounded),
                suffixIcon: IconButton(
                  tooltip: obscure ? 'Passwort anzeigen' : 'Passwort verbergen',
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: submit,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Bestätigen'),
        ),
      ],
    );
  }
}

class _EmergencyViewDialog extends StatelessWidget {
  const _EmergencyViewDialog({
    required this.view,
    required this.expiresAt,
  });

  final EmergencyView view;
  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final event = view.event;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF7F1D1D),
          foregroundColor: Colors.white,
          title: const Text('Geschützte Notfallansicht'),
          leading: IconButton(
            tooltip: 'Sicher schließen',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFB7185)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: const Color(0xFF881337),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_fullDate(event.startAt)} · '
                          '${_time(event.startAt)} Uhr · ${event.location}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (event.address != null) Text(event.address!),
                        const SizedBox(height: 8),
                        Text(
                          '${view.players.length} anwesende Spieler · '
                          '${view.usesActualAttendance ? 'tatsächliche Anwesenheit' : 'bestätigte Zusagen'} · '
                          'Zugriff bis ${_time(expiresAt)} Uhr',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (view.players.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Für diesen Termin sind aktuell keine anwesenden '
                          'Spieler erfasst.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final player in view.players) ...[
                      _EmergencyPlayerCard(player: player),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 10),
                  Text(
                    'Erzeugt ${_fullDate(view.generatedAt)} um '
                    '${_time(view.generatedAt)} Uhr. Nicht weitergeben oder '
                    'dauerhaft speichern.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmergencyPlayerCard extends StatelessWidget {
  const _EmergencyPlayerCard({required this.player});

  final EmergencyPlayer player;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: player.photoUrl == null
                      ? null
                      : NetworkImage(player.photoUrl!),
                  child: player.photoUrl == null
                      ? Text(
                          player.firstName.isEmpty
                              ? '?'
                              : player.firstName.substring(0, 1),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    player.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            if (player.medical.hasInformation) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDA4AF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Medizinische Notfallhinweise',
                      style: TextStyle(
                        color: Color(0xFF9F1239),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (_hasText(player.medical.allergies))
                      _EmergencyInfoLine(
                        label: 'Allergien',
                        value: player.medical.allergies!,
                      ),
                    if (_hasText(player.medical.medications))
                      _EmergencyInfoLine(
                        label: 'Medikamente',
                        value: player.medical.medications!,
                      ),
                    if (_hasText(player.medical.conditions))
                      _EmergencyInfoLine(
                        label: 'Erkrankungen',
                        value: player.medical.conditions!,
                      ),
                    if (_hasText(player.medical.emergencyNotes))
                      _EmergencyInfoLine(
                        label: 'Hinweise',
                        value: player.medical.emergencyNotes!,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Erziehungsberechtigte',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (player.guardians.isEmpty)
              const Text('Keine Erziehungsberechtigten hinterlegt.')
            else
              for (final guardian in player.guardians)
                _EmergencyContactTile(
                  icon: Icons.family_restroom_rounded,
                  name: guardian.name,
                  detail: [
                    _relationshipLabel(guardian.relationship),
                    if (guardian.isLegalGuardian) 'sorgeberechtigt',
                    if (guardian.canPickup) 'abholberechtigt',
                  ].join(' · '),
                  phone: guardian.phone,
                ),
            const SizedBox(height: 10),
            Text(
              'Notfallkontakte',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (player.emergencyContacts.isEmpty)
              const Text('Keine zusätzlichen Notfallkontakte hinterlegt.')
            else
              for (final contact in player.emergencyContacts)
                _EmergencyContactTile(
                  icon: Icons.emergency_rounded,
                  name: '${contact.priority}. ${contact.name}',
                  detail: [
                    if (_hasText(contact.relationship)) contact.relationship!,
                    if (contact.isAuthorizedPickup) 'abholberechtigt',
                  ].join(' · '),
                  phone: contact.phone,
                ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyInfoLine extends StatelessWidget {
  const _EmergencyInfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _EmergencyContactTile extends StatelessWidget {
  const _EmergencyContactTile({
    required this.icon,
    required this.name,
    required this.detail,
    this.phone,
  });

  final IconData icon;
  final String name;
  final String detail;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final phoneAvailable = _hasText(phone);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.blue),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        [
          if (detail.isNotEmpty) detail,
          if (phoneAvailable) phone!,
        ].join('\n'),
      ),
      trailing: phoneAvailable
          ? IconButton.filledTonal(
              tooltip: '$name anrufen',
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call_rounded),
            )
          : const Text('Keine Nummer'),
    );
  }
}

bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

String _relationshipLabel(String value) {
  switch (value) {
    case 'MOTHER':
      return 'Mutter';
    case 'FATHER':
      return 'Vater';
    case 'STEP_PARENT':
      return 'Stiefelternteil';
    case 'FOSTER_PARENT':
      return 'Pflegeelternteil';
    default:
      return 'Sorgeperson';
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
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w800)),
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
                value: [
                  '${_time(event.meetingAt!)} Uhr',
                  if (event.meetingLocation?.isNotEmpty == true)
                    event.meetingLocation!,
                ].join(' · '),
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
                  label: 'Zugesagt', value: summary.yes, color: AppColors.teal),
              _StatusMetric(
                  label: 'Abgesagt',
                  value: summary.no,
                  color: Colors.redAccent),
              if (event.type != EventType.match || summary.maybe > 0)
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
                      ref.invalidate(personalResponsesProvider);
                      ref.invalidate(eventsProvider);
                      await Future.wait<void>([
                        ref
                            .read(personalResponsesProvider.future)
                            .then<void>((_) {}),
                        ref.read(eventsProvider.future).then<void>((_) {}),
                      ]);
                      onRefresh();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Rückmeldung konnte nicht gespeichert werden.'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.how_to_reg_rounded),
                  label: const Text('Rückmeldung'),
                ),
              if (event.capabilities.canManage &&
                  (event.category == EventCategory.training ||
                      event.missingAttendance.isNotEmpty))
                OutlinedButton.icon(
                  onPressed: () =>
                      showEventAttendanceReminder(context, ref, event),
                  icon: const Icon(Icons.notifications_active_rounded),
                  label: Text(
                    event.category == EventCategory.training
                        ? 'Training erinnern'
                        : 'Offene erinnern',
                  ),
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
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openNeeds = event.carpoolNeeds
        .where((need) => need.status == CarpoolNeedStatus.open)
        .toList();
    final freeSeats = event.carpoolOffers.fold<int>(
      0,
      (sum, offer) => sum + offer.freeSeats,
    );
    return _Section(
      title: 'Fahrgemeinschaften',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.yellow.withValues(alpha: .45),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.route_rounded, color: AppColors.blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Einfach auswählen: Braucht dein Kind eine Mitfahrt oder '
                    'kannst du freie Plätze anbieten? Mehrere Kinder können '
                    'in einem Schritt eingetragen werden.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CarpoolMetric(
                icon: Icons.airline_seat_recline_normal_rounded,
                value: '$freeSeats',
                label: 'freie Plätze',
                color: AppColors.teal,
              ),
              _CarpoolMetric(
                icon: Icons.front_hand_outlined,
                value: '${openNeeds.length}',
                label: 'Mitfahrbedarf',
                color: AppColors.blue,
              ),
              _CarpoolMetric(
                icon: Icons.directions_car_rounded,
                value: '${event.carpoolOffers.length}',
                label: 'Fahrangebote',
                color: AppColors.navy,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 540;
              final needButton = FilledButton.icon(
                onPressed: event.isCancelled || players.isEmpty
                    ? null
                    : () => _createNeeds(context, ref),
                icon: const Icon(Icons.front_hand_outlined),
                label: const Text('Mitfahrt benötigt'),
              );
              final offerButton = OutlinedButton.icon(
                onPressed: event.capabilities.canOfferRide && !event.isCancelled
                    ? () => _offerRide(context, ref)
                    : null,
                icon: const Icon(Icons.add_road_rounded),
                label: const Text('Plätze anbieten'),
              );
              if (!compact) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [needButton, offerButton],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [needButton, const SizedBox(height: 8), offerButton],
              );
            },
          ),
          if (event.carpoolNeeds.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Wer braucht eine Mitfahrt?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            for (final need in event.carpoolNeeds)
              if (need.status != CarpoolNeedStatus.cancelled)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: need.status == CarpoolNeedStatus.matched
                        ? AppColors.teal.withValues(alpha: .09)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        need.status == CarpoolNeedStatus.matched
                            ? Icons.check_circle_rounded
                            : Icons.front_hand_outlined,
                        color: need.status == CarpoolNeedStatus.matched
                            ? AppColors.teal
                            : AppColors.blue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              need.playerName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              need.status == CarpoolNeedStatus.matched
                                  ? 'Mitfahrplatz gefunden'
                                  : need.note?.trim().isNotEmpty == true
                                      ? need.note!
                                      : 'Mitfahrplatz wird gesucht',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (need.canCancel)
                        IconButton(
                          tooltip: 'Mitfahrbedarf zurückziehen',
                          onPressed: () => _deleteNeed(context, ref, need),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 12),
          Text(
            'Angebotene Fahrten',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (event.carpoolOffers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Noch keine Fahrt angeboten. Sobald Eltern Plätze anbieten, '
                'können diese hier direkt angefragt werden.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
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
                          if (offer.canManage)
                            IconButton(
                              tooltip: 'Fahrangebot zurückziehen',
                              onPressed: () =>
                                  _deleteOffer(context, ref, offer),
                              icon: const Icon(Icons.delete_outline_rounded),
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
                              if (passenger.canCancel &&
                                  (passenger.status ==
                                          CarpoolRequestStatus.requested ||
                                      passenger.status ==
                                          CarpoolRequestStatus.confirmed))
                                IconButton(
                                  tooltip: 'Mitfahranfrage zurückziehen',
                                  onPressed: () => _updatePassenger(
                                    context,
                                    ref,
                                    offer,
                                    passenger,
                                    CarpoolRequestStatus.cancelled,
                                  ),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                      ],
                      if (offer.freeSeats > 0 &&
                          event.capabilities.canRespond &&
                          players.isNotEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              _requestSeats(context, ref, offer, players),
                          icon: const Icon(Icons.airline_seat_recline_normal),
                          label: const Text('Platz für Kind(er) anfragen'),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _createNeeds(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_CarpoolNeedDraft>(
      context: context,
      builder: (context) => _CarpoolNeedDialog(players: players),
    );
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).createCarpoolNeeds(
            eventId: event.id,
            playerIds: draft.playerIds,
            note: draft.note,
          );
      await onRefresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Der Mitfahrbedarf konnte nicht gespeichert werden.'),
          ),
        );
      }
    }
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
      await onRefresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Fahrangebot konnte nicht gespeichert werden.')),
        );
      }
    }
  }

  Future<void> _requestSeats(
    BuildContext context,
    WidgetRef ref,
    CarpoolOffer offer,
    List<PlayerModel> players,
  ) async {
    final playerIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => _CarpoolPlayerSelectionDialog(
        players: players,
        maxSelections: offer.freeSeats,
      ),
    );
    if (playerIds == null || playerIds.isEmpty) return;
    try {
      for (final playerId in playerIds.take(offer.freeSeats)) {
        await ref.read(repositoryProvider).requestCarpoolSeat(
              eventId: event.id,
              offerId: offer.id,
              playerId: playerId,
            );
      }
      await onRefresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Mitfahranfrage konnte nicht gesendet werden.')),
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
    await onRefresh();
  }

  Future<void> _deleteNeed(
    BuildContext context,
    WidgetRef ref,
    CarpoolNeed need,
  ) async {
    await ref.read(repositoryProvider).deleteCarpoolNeed(
          eventId: event.id,
          needId: need.id,
        );
    await onRefresh();
  }

  Future<void> _deleteOffer(
    BuildContext context,
    WidgetRef ref,
    CarpoolOffer offer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fahrangebot zurückziehen?'),
        content: const Text(
          'Bereits angefragte Plätze werden freigegeben und offene '
          'Mitfahrbedarfe wieder angezeigt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zurückziehen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repositoryProvider).deleteCarpoolOffer(
          eventId: event.id,
          offerId: offer.id,
        );
    await onRefresh();
  }
}

class _CarpoolMetric extends StatelessWidget {
  const _CarpoolMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 7),
            Text(
              '$value $label',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

class _ManagementBar extends ConsumerWidget {
  const _ManagementBar({required this.event, required this.organization});

  final EventModel event;
  final OrganizationContext organization;

  bool get _isRegularTraining =>
      event.id.startsWith('training-plan:') ||
      event.id.startsWith('regular-training:') ||
      (event.category == EventCategory.training &&
          (event.description ?? '').startsWith(
            'Reguläre Trainingszeit laut Belegungsplan der Saison ',
          ));

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
          if (!event.id.startsWith('training-plan:') &&
              !event.attendanceFinalized)
            TextButton.icon(
              onPressed: () async {
                await ref.read(repositoryProvider).finalizeAttendance(event.id);
                ref.invalidate(eventsProvider);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Rückmeldungen abschließen'),
            ),
          if (!_isRegularTraining)
            OutlinedButton.icon(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Bearbeiten'),
            ),
          if (event.type == EventType.match &&
              !event.category.isTournament &&
              event.capabilities.canReschedule)
            OutlinedButton.icon(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.event_repeat_rounded),
              label: const Text('Spiel verlegen'),
            ),
          if (!event.isCancelled && event.capabilities.canCancel)
            FilledButton.tonalIcon(
              onPressed: () => _cancel(context, ref),
              icon: const Icon(Icons.event_busy_rounded),
              label: Text(
                event.category == EventCategory.training
                    ? 'Dieses Training absagen'
                    : 'Absagen',
              ),
            ),
          if (_isRegularTraining &&
              organization.can('CONFIGURE_TRAINING_REMINDERS'))
            OutlinedButton.icon(
              onPressed: () => _deleteRegularTrainingSeries(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('Trainingsserie löschen'),
            ),
          if (event.capabilities.canDelete &&
              (!_isRegularTraining || event.isCancelled))
            OutlinedButton.icon(
              onPressed: () => _deletePermanently(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(
                event.type == EventType.match
                    ? 'Spiel löschen'
                    : event.category == EventCategory.training &&
                            event.isCancelled
                        ? 'Abgesagtes Training endgültig löschen'
                        : 'Termin löschen',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<EventWriteData>(
      context: context,
      builder: (context) => EventEditorDialog(
        repository: ref.read(repositoryProvider),
        teams: organization.teams,
        initialTeamId: organization.currentTeam.id,
        seasonName: organization.season.name,
        seasonEnd: organization.teams
                .where((team) => team.id == event.teamId)
                .firstOrNull
                ?.seasonEndDate ??
            organization.season.endDate,
        event: event,
      ),
    );
    if (draft == null || !context.mounted) return;
    final entireSeries =
        event.isRecurring ? await _seriesScope(context, 'Änderung') : false;
    if (entireSeries == null) return;
    try {
      final repository = ref.read(repositoryProvider);
      final updated = await repository.updateEvent(
        eventId: event.id,
        data: draft,
        entireSeries: entireSeries,
      );
      final confirmed = await repository.event(event.id);
      if (confirmed.id != updated.id ||
          confirmed.title != draft.title ||
          confirmed.startAt.toUtc() != draft.startAt.toUtc()) {
        throw StateError('Terminänderung wurde nicht bestätigt.');
      }
      ref.invalidate(eventsProvider);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Terminänderung wurde gespeichert.')),
        );
      }
    } on DioException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_apiErrorMessage(
            error,
            'Der Termin konnte nicht geändert werden.',
          ))),
        );
      }
    } catch (_) {
      ref.invalidate(eventsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Terminänderung konnte nicht bestätigt werden.'),
          ),
        );
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_CancelDraft>(
      context: context,
      builder: (context) => _CancelDialog(recurring: event.isRecurring),
    );
    if (result == null) return;
    try {
      final repository = ref.read(repositoryProvider);
      final confirmed = event.id.startsWith('training-plan:')
          ? await repository.cancelRegularTrainingOccurrence(
              teamId: event.teamId,
              title: event.title,
              startAt: event.startAt,
              endAt: event.endAt,
              location: event.location,
              reason: result.reason,
            )
          : await (() async {
              await repository.cancelEvent(
                eventId: event.id,
                reason: result.reason,
                entireSeries: result.entireSeries,
              );
              return repository.event(event.id);
            })();
      if (!confirmed.isCancelled) {
        throw StateError('Terminabsage wurde nicht bestätigt.');
      }
      ref.invalidate(eventsProvider);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Termin wurde abgesagt.')),
        );
      }
    } on DioException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_apiErrorMessage(
            error,
            'Der Termin konnte nicht abgesagt werden.',
          ))),
        );
      }
    } catch (_) {
      ref.invalidate(eventsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Terminabsage konnte nicht bestätigt werden.'),
          ),
        );
      }
    }
  }

  Future<void> _deletePermanently(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final deleteScope = event.isRecurring
        ? await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_rounded),
                    title: const Text('Nur diesen Termin löschen'),
                    onTap: () => Navigator.pop(sheetContext, 'single'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.update_rounded),
                    title: const Text('Diesen und alle folgenden löschen'),
                    subtitle: const Text(
                        'Vergangene Serientermine bleiben erhalten.'),
                    onTap: () => Navigator.pop(sheetContext, 'future'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_rounded),
                    title: const Text('Gesamte Terminserie löschen'),
                    onTap: () => Navigator.pop(sheetContext, 'all'),
                  ),
                ],
              ),
            ),
          )
        : 'single';
    if (deleteScope == null || !context.mounted) return;
    final entity = event.type == EventType.match ? 'Spiel' : 'Termin';
    var deleteLeagueMatch = event.matchDetails?.leagueId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: Text('$entity endgültig löschen?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '„${event.title}“ · ${_fullDate(event.startAt)} · '
                  '${_time(event.startAt)} Uhr · ${event.location}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  deleteScope == 'all'
                      ? 'Die gesamte Serie wird mit Rückmeldungen, Erinnerungen und Verknüpfungen gelöscht.'
                      : deleteScope == 'future'
                          ? 'Dieser und alle folgenden Serientermine werden gelöscht. Vergangene Termine bleiben erhalten.'
                          : 'Kader, Aufstellung, Rückmeldungen, Erinnerungen und Liveticker-Daten werden entfernt.',
                ),
                if (event.matchDetails?.leagueId != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteLeagueMatch,
                    title:
                        const Text('Verknüpfte Ligapartie ebenfalls löschen'),
                    subtitle: const Text(
                        'Die Ligatabelle wird unmittelbar neu berechnet.'),
                    onChanged: (value) => update(
                      () => deleteLeagueMatch = value ?? false,
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Diese Aktion kann in der App nicht rückgängig gemacht werden.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Endgültig löschen'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final repository = ref.read(repositoryProvider);
      await repository.deleteEventPermanently(
        eventId: event.id,
        scope: deleteScope,
        deleteLeagueMatch: deleteLeagueMatch,
      );
      ref.invalidate(eventsProvider);
      final refreshed = await ref.read(eventsProvider.future);
      if (refreshed.any(
        (item) => item.id == event.id && !item.isHiddenRegularOccurrence,
      )) {
        throw StateError('Der gelöschte Termin ist weiterhin vorhanden.');
      }
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(content: Text('$entity wurde endgültig gelöscht.')),
        );
      }
    } on DioException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _apiErrorMessage(
                error,
                '$entity konnte nicht gelöscht werden.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      ref.invalidate(eventsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$entity konnte nicht sicher gelöscht werden.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteRegularTrainingSeries(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final team = organization.teams
        .where((candidate) => candidate.id == event.teamId)
        .firstOrNull;
    if (team == null) return;
    final date = DateTime(
      event.startAt.year,
      event.startAt.month,
      event.startAt.day,
    );
    final indoorStart = team.indoorSeasonStartDate;
    final indoorEnd = team.indoorSeasonEndDate;
    final indoor = indoorStart != null &&
        indoorEnd != null &&
        !date.isBefore(DateTime(
          indoorStart.year,
          indoorStart.month,
          indoorStart.day,
        )) &&
        !date.isAfter(DateTime(
          indoorEnd.year,
          indoorEnd.month,
          indoorEnd.day,
        ));
    bool matchingSlot(String value) {
      final slot = RegularTrainingSlot.tryParse(
        value,
        fallbackLocation:
            indoor ? team.indoorTrainingLocation : team.trainingLocation,
      );
      if (slot == null) return false;
      return slot.weekday == event.startAt.weekday &&
          slot.startMinutes == event.startAt.hour * 60 + event.startAt.minute &&
          (event.endAt == null ||
              slot.endMinutes == event.endAt!.hour * 60 + event.endAt!.minute);
    }

    final source = indoor ? team.indoorTrainingTimes : team.trainingTimes;
    final matching = source.where(matchingSlot).toList();
    if (matching.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die zugehörige Trainingsserie konnte nicht eindeutig gefunden werden.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_sweep_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Gesamte Trainingsserie löschen?'),
        content: Text(
          '${matching.first}\n\nAlle noch kommenden automatisch erzeugten '
          'Termine dieser Trainingszeit werden entfernt. Andere '
          'Trainingszeiten und vergangene Vereinsdaten bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Serie löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final remaining = source.where((value) => !matchingSlot(value)).toList();
    try {
      final repository = ref.read(repositoryProvider);
      await repository.updateTrainingSchedule(
        teamId: team.id,
        trainingTimes: indoor ? team.trainingTimes : remaining,
        trainingPartnerIds: team.trainingPartnerIds,
        matchdayTimes: team.matchdayTimes,
        defaultReminderMinutes: team.defaultReminderMinutes,
        secondaryReminderMinutes: team.secondaryReminderMinutes,
        defaultReminderPushEnabled: team.defaultReminderPushEnabled,
        trainingLocation: team.trainingLocation,
        indoorTrainingLocation: indoor ? team.indoorTrainingLocation : null,
        indoorTrainingTimes: indoor ? remaining : null,
      );
      ref.invalidate(organizationProvider);
      ref.invalidate(eventsProvider);
      await Future.wait([
        ref.read(organizationProvider.future),
        ref.read(eventsProvider.future),
      ]);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Trainingsserie wurde gelöscht.')),
        );
      }
    } on DioException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_apiErrorMessage(
              error,
              'Die Trainingsserie konnte nicht gelöscht werden.',
            )),
          ),
        );
      }
    }
  }
}

class EventEditorDialog extends StatefulWidget {
  const EventEditorDialog({
    super.key,
    required this.repository,
    required this.teams,
    required this.initialTeamId,
    this.seasonName,
    this.seasonEnd,
    this.event,
  });

  final DataRepository repository;
  final List<TeamSummary> teams;
  final String initialTeamId;
  final String? seasonName;
  final DateTime? seasonEnd;
  final EventModel? event;

  @override
  State<EventEditorDialog> createState() => _EventEditorDialogState();
}

enum _MeetingTimeMode { beforeKickoff, exactTime }

class _EventEditorDialogState extends State<EventEditorDialog> {
  static const homeMatchVenue = 'Stadion am Kreutweg, Teugn';
  static const awayMeetingLocation = 'Vereinsheim Teugn';
  static const pitchOptions = [
    'Platz 1 unten',
    'Platz 2 oben',
    'Sportplatz Teugn · beide Plätze',
    'Platz noch offen / unklar',
  ];

  final formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController location;
  late final TextEditingController meetingLocation;
  late final TextEditingController address;
  late final TextEditingController mapUrl;
  late final TextEditingController opponent;
  late final TextEditingController periodCount;
  late final TextEditingController periodMinutes;
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
  late final TextEditingController meinTurnierplanUrl;
  late final TextEditingController pitchConflictMessage;
  late EventCategory category;
  late EventVisibility visibility;
  HomeAway? homeAway;
  late DateTime startAt;
  String? selectedOpponentId;
  String? selectedOpponentName;
  String? selectedOpponentClubId;
  String? selectedOpponentDesignation;
  DateTime? endAt;
  DateTime? meetingAt;
  late _MeetingTimeMode meetingTimeMode;
  int meetingMinutesBefore = 30;
  DateTime? responseDeadline;
  late Set<String> teamIds;
  bool carpoolRequired = false;
  bool recurring = false;
  RecurrenceFrequency frequency = RecurrenceFrequency.weekly;
  DateTime? recurrenceUntil;
  int interval = 1;
  final weekdays = <int>{};
  String reminderMode = 'none';
  bool reminderPushEnabled = true;
  bool reminderSetByMatchDefault = false;
  EventNotificationMode notificationMode = EventNotificationMode.none;
  String? lastAutomaticLocation;
  late final TextEditingController customReminderMinutes;
  late final Future<List<PlayerModel>> participantPlayers;
  List<OpponentClubModel> availableOpponentClubs = const [];
  List<OpponentModel> availableOpponents = const [];
  bool loadingOpponentChoices = false;
  bool savingOpponent = false;
  late String opponentAgeGroupId;
  AgeGroupSummary? opponentAgeGroup;
  final participantPlayerIds = <String>{};
  bool limitParticipants = false;
  String selectedPitch = 'Platz noch offen / unklar';
  List<PitchConflictPreview> pitchConflicts = const [];
  bool checkingPitchConflicts = false;
  String? pitchConflictError;
  bool requestPitchConflictApprovals = true;
  int pitchCheckRevision = 0;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final initialTeam = widget.teams.cast<TeamSummary?>().firstWhere(
          (team) => team?.id == widget.initialTeamId,
          orElse: () => widget.teams.isEmpty ? null : widget.teams.first,
        );
    title = TextEditingController(text: event?.title);
    location = TextEditingController(text: event?.location);
    meetingLocation = TextEditingController(
      text: event?.meetingLocation ??
          (event?.homeAway == HomeAway.away ? awayMeetingLocation : null),
    );
    address = TextEditingController(text: event?.address);
    mapUrl = TextEditingController(text: event?.mapUrl);
    opponent = TextEditingController(text: event?.opponent);
    selectedOpponentId = event?.matchDetails?.opponentId;
    selectedOpponentName = selectedOpponentId == null ? null : event?.opponent;
    periodCount = TextEditingController(
      text: (event?.matchDetails?.periodCount ?? initialTeam?.periodCount ?? 2)
          .toString(),
    );
    periodMinutes = TextEditingController(
      text: (event?.matchDetails?.periodMinutes ??
              initialTeam?.periodMinutes ??
              30)
          .toString(),
    );
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
    final tournamentAttachment = event?.meinTurnierplanAttachment;
    final regularAttachment = event?.attachments
        .where((item) => item != tournamentAttachment)
        .firstOrNull;
    attachmentName = TextEditingController(text: regularAttachment?.name);
    attachmentUrl = TextEditingController(text: regularAttachment?.url);
    meinTurnierplanUrl = TextEditingController(text: tournamentAttachment?.url);
    pitchConflictMessage = TextEditingController();
    customReminderMinutes = TextEditingController();
    category = event?.category ?? EventCategory.training;
    visibility = event?.visibility ?? EventVisibility.team;
    homeAway = event?.homeAway ??
        (category.isSingleMatch
            ? HomeAway.home
            : category.isTournament
                ? HomeAway.neutral
                : null);
    if (category.isSingleMatch &&
        homeAway == HomeAway.home &&
        location.text.trim().isEmpty) {
      location.text = homeMatchVenue;
      lastAutomaticLocation = homeMatchVenue;
    } else if (category.isSingleMatch && homeAway == HomeAway.away) {
      meetingLocation.text = meetingLocation.text.trim().isEmpty
          ? awayMeetingLocation
          : meetingLocation.text;
    }
    if (event?.venue != null && pitchOptions.contains(event!.venue)) {
      selectedPitch = event.venue!;
    }
    startAt =
        event?.startAt ?? DateTime.now().add(const Duration(days: 1, hours: 1));
    endAt = event?.endAt ?? startAt.add(const Duration(hours: 1, minutes: 30));
    meetingAt = event?.meetingAt;
    final savedMeetingOffset = standardMeetingOffset(startAt, meetingAt);
    meetingTimeMode = meetingAt == null || savedMeetingOffset != null
        ? _MeetingTimeMode.beforeKickoff
        : _MeetingTimeMode.exactTime;
    meetingMinutesBefore = savedMeetingOffset ?? 30;
    responseDeadline = event?.responseDeadline;
    teamIds = event == null
        ? {widget.initialTeamId}
        : (event.targetTeams.isEmpty
            ? {event.teamId}
            : event.targetTeams.map((team) => team.id).toSet());
    carpoolRequired = event?.carpoolRequired ?? false;
    final savedReminders = event?.reminderMinutes ?? const <int>[];
    reminderPushEnabled = event?.reminderPushEnabled ?? true;
    if (savedReminders.isEmpty) {
      reminderMode = 'none';
    } else {
      final saved = savedReminders.reduce((a, b) => a < b ? a : b);
      if (saved == 60 || saved == 120 || saved == 1440) {
        reminderMode = '$saved';
      } else {
        reminderMode = 'custom';
        customReminderMinutes.text = '$saved';
      }
    }
    participantPlayers = widget.repository.players();
    opponentAgeGroupId = initialTeam?.ageGroup.id ?? '';
    opponentAgeGroup = initialTeam?.ageGroup;
    _loadOpponentChoices();
    participantPlayerIds.addAll(event?.participantPlayerIds ?? const []);
    limitParticipants = participantPlayerIds.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPitchConflicts();
    });
  }

  @override
  void dispose() {
    for (final controller in [
      title,
      location,
      meetingLocation,
      address,
      mapUrl,
      opponent,
      periodCount,
      periodMinutes,
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
      meinTurnierplanUrl,
      pitchConflictMessage,
      customReminderMinutes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOpponentChoices() async {
    if (opponentAgeGroupId.isEmpty) return;
    if (mounted) setState(() => loadingOpponentChoices = true);
    try {
      final values = await Future.wait([
        widget.repository.opponentClubs(),
        widget.repository.opponents(opponentAgeGroupId),
      ]);
      if (!mounted) return;
      final clubs = values[0] as List<OpponentClubModel>;
      final teams = values[1] as List<OpponentModel>;
      final stored =
          teams.where((item) => item.id == selectedOpponentId).firstOrNull;
      final byName = stored ??
          teams
              .where((item) => item.displayName == opponent.text.trim())
              .firstOrNull;
      OpponentClubModel? legacyClub;
      String? legacyDesignation;
      if (byName == null && opponent.text.trim().isNotEmpty) {
        final matches = clubs
            .where((item) => opponent.text.trim().startsWith(item.name))
            .toList()
          ..sort((a, b) => b.name.length.compareTo(a.name.length));
        if (matches.isNotEmpty) {
          legacyClub = matches.first;
          final suffix =
              opponent.text.trim().substring(legacyClub.name.length).trim();
          legacyDesignation =
              suffix.isEmpty ? null : _canonicalOpponentDesignation(suffix);
        }
      }
      setState(() {
        availableOpponentClubs = clubs;
        availableOpponents = teams;
        if (byName != null) {
          selectedOpponentId = byName.id;
          selectedOpponentName = byName.displayName;
          selectedOpponentClubId = byName.opponentClubId;
          selectedOpponentDesignation = byName.teamDesignation;
          opponent.text = byName.displayName;
        } else if (legacyClub != null) {
          selectedOpponentClubId = legacyClub.id;
          selectedOpponentDesignation = legacyDesignation;
        }
        loadingOpponentChoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingOpponentChoices = false);
    }
  }

  String get _opponentAgePrefix {
    final source = opponentAgeGroup?.code.trim().toUpperCase() ?? '';
    return RegExp(r'[A-Z]').firstMatch(source)?.group(0) ?? 'E';
  }

  String _canonicalOpponentDesignation(String value) {
    return canonicalYouthTeamDesignation(
      value,
      ageCode: _opponentAgePrefix,
    );
  }

  List<String> get _opponentDesignationOptions {
    final values = <String>{
      for (var number = 1; number <= 9; number++) '$_opponentAgePrefix$number',
      for (final item in availableOpponents)
        _canonicalOpponentDesignation(item.teamDesignation),
    }.toList()
      ..sort((a, b) {
        final aNumber = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 99;
        final bNumber = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 99;
        return aNumber.compareTo(bNumber);
      });
    return values;
  }

  void _applyOpponentClubDefaults(String? clubId) {
    final club =
        availableOpponentClubs.where((item) => item.id == clubId).firstOrNull;
    if (club == null || homeAway != HomeAway.away) return;
    final automatic = club.venue?.trim().isNotEmpty == true
        ? club.venue!
        : (club.address ?? '');
    if (automatic.isEmpty ||
        !(location.text.trim().isEmpty ||
            location.text.trim() == homeMatchVenue ||
            location.text.trim() == lastAutomaticLocation)) {
      return;
    }
    location.text = automatic;
    lastAutomaticLocation = automatic;
    if (address.text.trim().isEmpty &&
        club.address?.trim().isNotEmpty == true) {
      address.text = club.address!;
    }
  }

  Widget _categoryInput() => DropdownButtonFormField<EventCategory>(
        initialValue: category,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Kategorie',
          prefixIcon: Icon(Icons.category_outlined),
        ),
        items: [
          for (final value in EventCategory.values)
            DropdownMenuItem(
              value: value,
              child: Text(
                value.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          setState(() {
            final wasMatch = category.isMatch;
            category = value ?? category;
            if (category.isMatch) {
              if (category.isTournament) {
                homeAway = HomeAway.neutral;
              } else {
                homeAway ??= HomeAway.home;
              }
              if (category.isSingleMatch && homeAway == HomeAway.home) {
                location.text = homeMatchVenue;
              }
              if (homeAway == HomeAway.away &&
                  meetingLocation.text.trim().isEmpty) {
                meetingLocation.text = awayMeetingLocation;
              }
              if (widget.event == null && !wasMatch && reminderMode == 'none') {
                reminderMode = '1440';
                reminderPushEnabled = true;
                reminderSetByMatchDefault = true;
              }
            } else if (reminderSetByMatchDefault) {
              reminderMode = 'none';
              reminderSetByMatchDefault = false;
            }
          });
          _refreshPitchConflicts();
        },
      );

  Widget _titleInput({required bool compact}) => TextFormField(
        controller: title,
        decoration: InputDecoration(
          labelText: 'Titel (optional)',
          hintText: category.label,
          helperText: compact
              ? null
              : 'Vorschlag wählen oder eigenen Titel eingeben. '
                  'Leer = ${category.label}.',
          prefixIcon: const Icon(Icons.title_rounded),
          suffixIcon: PopupMenuButton<String>(
            tooltip: 'Titelvorschläge',
            icon: const Icon(Icons.arrow_drop_down_rounded),
            onSelected: (value) => setState(() {
              title.text = value;
              title.selection = TextSelection.collapsed(offset: value.length);
            }),
            itemBuilder: (context) => [
              for (final suggestion in category.titleSuggestions)
                PopupMenuItem<String>(
                  value: suggestion,
                  child: Text(
                    suggestion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _dateRange({required bool compact}) {
    final begin = _DateTimeField(
      label: 'Beginn',
      value: startAt,
      compact: compact,
      onChanged: (value) {
        if (value == null) return;
        final previousStart = startAt;
        final previousEnd = endAt;
        setState(() {
          startAt = value;
          if (previousEnd != null) {
            final previousDuration = previousEnd.difference(previousStart);
            endAt = previousDuration.isNegative
                ? DateTime(
                    value.year,
                    value.month,
                    value.day,
                    value.hour,
                    value.minute,
                  )
                : value.add(previousDuration);
          }
          if (endAt != null && endAt!.isBefore(startAt)) {
            endAt = DateTime(
              startAt.year,
              startAt.month,
              startAt.day,
              startAt.hour,
              startAt.minute,
            );
          }
        });
        _refreshPitchConflicts();
      },
    );
    final end = _DateTimeField(
      label: 'Ende',
      value: endAt,
      compact: compact,
      allowClear: true,
      onChanged: (value) {
        setState(() => endAt = value);
        _refreshPitchConflicts();
      },
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          begin,
          const SizedBox(height: 9),
          end,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: begin),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 10),
          child: const SizedBox(
            height: 54,
            child: Center(child: Icon(Icons.arrow_forward_rounded, size: 18)),
          ),
        ),
        Expanded(child: end),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 8 : 14,
        vertical: mobile ? 10 : 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: mobile ? MediaQuery.sizeOf(context).height - 20 : 860,
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                mobile ? 16 : 24,
                mobile ? 12 : 22,
                mobile ? 8 : 16,
                mobile ? 6 : 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.event == null
                          ? 'Termin anlegen'
                          : 'Termin bearbeiten',
                      style: mobile
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
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
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 14 : 24,
                    mobile ? 4 : 8,
                    mobile ? 14 : 24,
                    mobile ? 16 : 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mobile) ...[
                        _categoryInput(),
                        const SizedBox(height: 9),
                        _titleInput(compact: true),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _categoryInput(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: _titleInput(compact: false),
                            ),
                          ],
                        ),
                      SizedBox(height: mobile ? 9 : 12),
                      _dateRange(compact: mobile),
                      SizedBox(height: mobile ? 9 : 12),
                      if (category.isMatch)
                        _MatchMeetingTimeField(
                          mode: meetingTimeMode,
                          minutesBefore: meetingMinutesBefore,
                          startAt: startAt,
                          exactMeetingAt: meetingAt,
                          onModeChanged: (value) => setState(() {
                            meetingTimeMode = value;
                            if (value == _MeetingTimeMode.exactTime) {
                              meetingAt ??= meetingTimeBefore(
                                startAt,
                                meetingMinutesBefore,
                              );
                            }
                          }),
                          onMinutesChanged: (value) => setState(() {
                            meetingMinutesBefore = value;
                          }),
                          onExactTimeChanged: (value) =>
                              setState(() => meetingAt = value),
                        )
                      else
                        _DateTimeField(
                          label: 'Treffpunktzeit',
                          value: meetingAt,
                          allowClear: true,
                          onChanged: (value) =>
                              setState(() => meetingAt = value),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: location,
                        decoration: InputDecoration(
                          labelText: category.isMatch ? 'Spielstätte' : 'Ort',
                          helperText: category.isMatch &&
                                  homeAway == HomeAway.home
                              ? 'Standard: Stadion am Kreutweg, Teugn · bei Bedarf änderbar'
                              : null,
                        ),
                        validator: category.isMatch && homeAway == HomeAway.away
                            ? (_) => null
                            : _required,
                      ),
                      if (category.isMatch) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: meetingLocation,
                          decoration: const InputDecoration(
                            labelText: 'Treffpunkt',
                            prefixIcon: Icon(Icons.groups_rounded),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: address,
                        decoration: const InputDecoration(
                            labelText: 'Adresse (optional)'),
                      ),
                      if (category.isTournament) ...[
                        const SizedBox(height: 12),
                        const Card(
                          color: AppColors.yellowSoft,
                          child: ListTile(
                            leading: Icon(Icons.account_tree_rounded),
                            title: Text('Turnier mit mehreren Partien'),
                            subtitle: Text(
                              'Hier wird nur der gemeinsame Turniertermin angelegt. '
                              'Gegner und einzelne Anstoßzeiten wählst du danach im '
                              'Spielbetrieb; jede Partie erhält einen eigenen Liveticker.',
                            ),
                          ),
                        ),
                      ],
                      if (category.isSingleMatch) ...[
                        const SizedBox(height: 12),
                        if (loadingOpponentChoices)
                          const LinearProgressIndicator(minHeight: 3)
                        else
                          ResponsiveFormRow(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: availableOpponentClubs.any(
                                        (item) =>
                                            item.id == selectedOpponentClubId,
                                      )
                                          ? selectedOpponentClubId
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Verein *',
                                        helperText:
                                            'Vereine sind jugendübergreifend sichtbar.',
                                      ),
                                      items: [
                                        for (final club
                                            in availableOpponentClubs)
                                          DropdownMenuItem(
                                            value: club.id,
                                            child: Row(
                                              children: [
                                                _OpponentLogo(
                                                  url: club.logoUrl,
                                                  label: club.name,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    club.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) => setState(() {
                                        selectedOpponentClubId = value;
                                        selectedOpponentDesignation = null;
                                        selectedOpponentId = null;
                                        selectedOpponentName = null;
                                        opponent.clear();
                                        _applyOpponentClubDefaults(value);
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    tooltip: 'Verein hinzufügen',
                                    onPressed: _quickAddOpponentClub,
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ],
                              ),
                              DropdownButtonFormField<String>(
                                key: ValueKey(
                                  '$selectedOpponentClubId:'
                                  '$selectedOpponentDesignation',
                                ),
                                initialValue: _opponentDesignationOptions
                                        .contains(selectedOpponentDesignation
                                            ?.toUpperCase()
                                            .replaceAll(' ', ''))
                                    ? selectedOpponentDesignation
                                        ?.toUpperCase()
                                        .replaceAll(' ', '')
                                    : null,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Jugendmannschaft *',
                                  helperText:
                                      'Nur $_opponentAgePrefix-Mannschaften '
                                      'werden in dieser Jugend verwaltet.',
                                ),
                                items: [
                                  for (final value
                                      in _opponentDesignationOptions)
                                    DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                ],
                                onChanged: selectedOpponentClubId == null
                                    ? null
                                    : (value) => setState(() {
                                          selectedOpponentDesignation = value;
                                          final selected = availableOpponents
                                              .where(
                                                (item) =>
                                                    item.opponentClubId ==
                                                        selectedOpponentClubId &&
                                                    item.teamDesignation
                                                            .toUpperCase()
                                                            .replaceAll(
                                                                ' ', '') ==
                                                        value,
                                              )
                                              .firstOrNull;
                                          selectedOpponentId = selected?.id;
                                          selectedOpponentName =
                                              selected?.displayName;
                                          if (selected != null) {
                                            opponent.text =
                                                selected.displayName;
                                          } else {
                                            final club = availableOpponentClubs
                                                .where((item) =>
                                                    item.id ==
                                                    selectedOpponentClubId)
                                                .firstOrNull;
                                            opponent.text = club == null
                                                ? ''
                                                : '${club.name} $value';
                                          }
                                        }),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<HomeAway>(
                          initialValue: homeAway,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Heim / Auswärts'),
                          items: const [
                            DropdownMenuItem(
                                value: HomeAway.home, child: Text('Heim')),
                            DropdownMenuItem(
                                value: HomeAway.away, child: Text('Auswärts')),
                            DropdownMenuItem(
                                value: HomeAway.neutral,
                                child: Text('Neutral')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              homeAway = value;
                              if (value == HomeAway.away) {
                                pitchConflicts = const [];
                                if (location.text.trim() == homeMatchVenue ||
                                    location.text.trim() ==
                                        lastAutomaticLocation) {
                                  location.clear();
                                  lastAutomaticLocation = null;
                                }
                                if (meetingLocation.text.trim().isEmpty) {
                                  meetingLocation.text = awayMeetingLocation;
                                }
                              } else if (value == HomeAway.home) {
                                if (location.text.trim().isEmpty ||
                                    location.text.trim() ==
                                        lastAutomaticLocation) {
                                  location.text = homeMatchVenue;
                                  lastAutomaticLocation = homeMatchVenue;
                                }
                              }
                            });
                            _refreshPitchConflicts();
                          },
                        ),
                        const SizedBox(height: 12),
                        ResponsiveFormRow(
                          breakpoint: 620,
                          children: [
                            TextFormField(
                              controller: periodCount,
                              keyboardType: TextInputType.number,
                              onChanged: (_) {
                                setState(() {});
                                _refreshPitchConflicts();
                              },
                              decoration: const InputDecoration(
                                labelText: 'Spielabschnitte',
                                helperText: 'z. B. 2 Halbzeiten oder 4 Viertel',
                              ),
                              validator: (value) => _matchNumber(value, 1, 8),
                            ),
                            TextFormField(
                              controller: periodMinutes,
                              keyboardType: TextInputType.number,
                              onChanged: (_) {
                                setState(() {});
                                _refreshPitchConflicts();
                              },
                              decoration: const InputDecoration(
                                labelText: 'Minuten je Abschnitt',
                                helperText: 'z. B. 15 Minuten',
                              ),
                              validator: (value) => _matchNumber(value, 1, 90),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Gesamtspielzeit: ${_matchDurationLabel()}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (_usesClubPitch) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedPitch,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Platz für diesen Termin',
                            helperText:
                                'Wird sofort mit allen regulären Trainingszeiten abgeglichen.',
                          ),
                          items: [
                            for (final pitch in pitchOptions)
                              DropdownMenuItem(
                                value: pitch,
                                child: Text(
                                  pitch,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedPitch =
                                  value ?? 'Platz noch offen / unklar';
                              venue.text = selectedPitch;
                              if (selectedPitch !=
                                      'Platz noch offen / unklar' &&
                                  location.text.trim().isEmpty) {
                                location.text = 'Sportplatz Teugn';
                              }
                            });
                            _refreshPitchConflicts();
                          },
                        ),
                        const SizedBox(height: 12),
                        _PitchConflictPanel(
                          checking: checkingPitchConflicts,
                          pitchIsOpen:
                              selectedPitch == 'Platz noch offen / unklar',
                          error: pitchConflictError,
                          conflicts: pitchConflicts,
                          requestApprovals: requestPitchConflictApprovals,
                          messageController: pitchConflictMessage,
                          onRequestApprovalsChanged: (value) => setState(
                            () => requestPitchConflictApprovals = value,
                          ),
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
                              onSelected: (selected) {
                                setState(() {
                                  selected
                                      ? teamIds.add(team.id)
                                      : teamIds.remove(team.id);
                                  if (widget.event == null &&
                                      category.isMatch &&
                                      selected &&
                                      teamIds.length == 1) {
                                    periodCount.text =
                                        team.periodCount.toString();
                                    periodMinutes.text =
                                        team.periodMinutes.toString();
                                  }
                                });
                                _refreshPitchConflicts();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Teilnehmende individuell auswählen'),
                        subtitle: const Text(
                          'Nur ausgewählte Spieler und deren Eltern erhalten die Anfrage.',
                        ),
                        value: limitParticipants,
                        onChanged: (value) => setState(() {
                          limitParticipants = value;
                          if (!value) participantPlayerIds.clear();
                        }),
                      ),
                      if (limitParticipants)
                        FutureBuilder<List<PlayerModel>>(
                          future: participantPlayers,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const LogoLoadingPanel(
                                message: 'Spieler werden geladen …',
                                compact: true,
                              );
                            }
                            if (snapshot.hasError) {
                              return const Text(
                                'Spieler konnten nicht geladen werden.',
                              );
                            }
                            final players = (snapshot.data ??
                                    const <PlayerModel>[])
                                .where(
                                    (player) => teamIds.contains(player.teamId))
                                .toList()
                              ..sort((a, b) =>
                                  a.displayName.compareTo(b.displayName));
                            if (players.isEmpty) {
                              return const Text(
                                'In den gewählten Mannschaften sind keine aktiven Spieler vorhanden.',
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${participantPlayerIds.length} ausgewählt',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        participantPlayerIds.addAll(
                                          players.map((player) => player.id),
                                        );
                                      }),
                                      child: const Text('Sichtbare auswählen'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        for (final player in players) {
                                          participantPlayerIds
                                              .remove(player.id);
                                        }
                                      }),
                                      child: const Text('Abwählen'),
                                    ),
                                  ],
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final player in players)
                                      FilterChip(
                                        avatar: CircleAvatar(
                                          child: Text(player.initials),
                                        ),
                                        label: Text(
                                          '${player.displayName} · ${player.teamCode}',
                                        ),
                                        selected: participantPlayerIds
                                            .contains(player.id),
                                        onSelected: (selected) => setState(() {
                                          selected
                                              ? participantPlayerIds
                                                  .add(player.id)
                                              : participantPlayerIds
                                                  .remove(player.id);
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      if (widget.event == null) ...[
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Beteiligte informieren',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                category.isMatch
                                    ? 'Spiele bleiben zunächst Entwurf und werden später über „Für Eltern & Spieler freigeben“ kommuniziert.'
                                    : 'Empfängerkreis: ${limitParticipants ? '${participantPlayerIds.length} ausgewählte Kinder mit ihren Sorgeberechtigten' : '${teamIds.length} ausgewählte Mannschaft(en)'}.',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              if (!category.isMatch) ...[
                                Material(
                                  color: Colors.transparent,
                                  child: RadioGroup<EventNotificationMode>(
                                    groupValue: notificationMode,
                                    onChanged: (value) => setState(
                                      () => notificationMode =
                                          value ?? EventNotificationMode.none,
                                    ),
                                    child: const Column(
                                      children: [
                                        RadioListTile<EventNotificationMode>(
                                          contentPadding: EdgeInsets.zero,
                                          value: EventNotificationMode.none,
                                          title: Text('Keine Nachricht'),
                                        ),
                                        RadioListTile<EventNotificationMode>(
                                          contentPadding: EdgeInsets.zero,
                                          value: EventNotificationMode.inApp,
                                          title: Text('In-App-Nachricht'),
                                        ),
                                        RadioListTile<EventNotificationMode>(
                                          contentPadding: EdgeInsets.zero,
                                          value: EventNotificationMode.push,
                                          title: Text('In-App + Pushnachricht'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (notificationMode !=
                                    EventNotificationMode.none)
                                  Text(
                                    'Vorschau: Neuer Termin: ${resolveEventTitle(title.text, category)} am ${startAt.day}.${startAt.month}.${startAt.year} um ${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')} Uhr${location.text.trim().isEmpty ? '' : ' in ${location.text.trim()}'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Weitere Termindaten'),
                        children: [
                          TextFormField(
                            controller: description,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                labelText: 'Beschreibung'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: mapUrl,
                            decoration:
                                const InputDecoration(labelText: 'Kartenlink'),
                          ),
                          const SizedBox(height: 12),
                          if (!_usesClubPitch)
                            TextFormField(
                              controller: venue,
                              decoration: const InputDecoration(
                                  labelText: 'Spielstätte'),
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
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.yellow.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Automatische Erinnerung',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  category.isMatch
                                      ? 'Für Spiele sind 24 Stunden standardmäßig aktiv. Die Push-Nachricht geht an die relevanten Eltern und Spieler.'
                                      : 'Die Push-Nachricht wird zuverlässig vom Server an die ausgewählten Personen gesendet.',
                                  style:
                                      const TextStyle(color: AppColors.muted),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  initialValue: reminderMode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Zeitpunkt',
                                    prefixIcon: Icon(
                                      Icons.notifications_active_outlined,
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'none',
                                      child: Text('Keine Erinnerung'),
                                    ),
                                    DropdownMenuItem(
                                      value: '60',
                                      child: Text('1 Stunde vorher'),
                                    ),
                                    DropdownMenuItem(
                                      value: '120',
                                      child: Text('2 Stunden vorher'),
                                    ),
                                    DropdownMenuItem(
                                      value: '1440',
                                      child: Text('24 Stunden vorher'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'custom',
                                      child: Text('Benutzerdefiniert'),
                                    ),
                                  ],
                                  onChanged: (value) => setState(
                                    () => reminderMode = value ?? 'none',
                                  ),
                                ),
                                if (reminderMode == 'custom') ...[
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: customReminderMinutes,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Minuten vor Terminbeginn',
                                      helperText:
                                          '1 bis 10.080 Minuten (7 Tage)',
                                    ),
                                    validator: (value) {
                                      if (reminderMode != 'custom') return null;
                                      final minutes =
                                          int.tryParse(value?.trim() ?? '');
                                      if (minutes == null ||
                                          minutes < 1 ||
                                          minutes > 10080) {
                                        return '1 bis 10.080 Minuten eingeben';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                                if (reminderMode != 'none')
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    value: reminderPushEnabled,
                                    onChanged: (value) => setState(
                                      () => reminderPushEnabled = value,
                                    ),
                                    title: const Text(
                                        'Zusätzlich als Pushnachricht senden'),
                                    subtitle: const Text(
                                        'Die In-App-Erinnerung bleibt immer aktiv.'),
                                  ),
                              ],
                            ),
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
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Sichtbarkeit'),
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
                            onChanged: (value) => setState(
                                () => visibility = value ?? visibility),
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
                          if (category == EventCategory.tournament ||
                              category == EventCategory.indoorTournament) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.yellowSoft,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.gold.withValues(alpha: .25),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Live-Turnierplan für Eltern & Trainer',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Füge den öffentlichen Link aus '
                                    'www.meinturnierplan.de ein. Zeitplan, '
                                    'Spiele und Ergebnisse bleiben dadurch '
                                    'direkt in der App aktuell.',
                                  ),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: meinTurnierplanUrl,
                                    keyboardType: TextInputType.url,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText: 'MeinTurnierplan-Link',
                                      hintText:
                                          'https://www.meinturnierplan.de/showit.php?id=…',
                                      prefixIcon:
                                          Icon(Icons.emoji_events_rounded),
                                    ),
                                    validator: (value) {
                                      final normalized = value?.trim() ?? '';
                                      if (normalized.isEmpty) return null;
                                      return isMeinTurnierplanUrl(normalized)
                                          ? null
                                          : 'Bitte einen gültigen öffentlichen '
                                              'MeinTurnierplan-Link einfügen.';
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                            isExpanded: true,
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
                          if (category == EventCategory.training)
                            _SeasonSeriesInfo(
                              seasonName: widget.seasonName,
                              seasonEnd: widget.seasonEnd,
                            )
                          else
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
                                      const [
                                        'Mo',
                                        'Di',
                                        'Mi',
                                        'Do',
                                        'Fr',
                                        'Sa',
                                        'So'
                                      ][day - 1],
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
              padding: EdgeInsets.fromLTRB(
                mobile ? 12 : 16,
                mobile ? 9 : 16,
                mobile ? 12 : 16,
                mobile ? 10 : 16,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed:
                          savingOpponent ? null : () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (mobile)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: savingOpponent ? null : _save,
                        icon: savingOpponent
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 19),
                        label: Text(savingOpponent
                            ? 'Gegner wird gespeichert …'
                            : 'Termin speichern'),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: savingOpponent ? null : _save,
                      child: Text(savingOpponent ? 'Speichert …' : 'Speichern'),
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

  String? _matchNumber(String? value, int minimum, int maximum) {
    if (!category.isSingleMatch) return null;
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < minimum || parsed > maximum) {
      return '$minimum bis $maximum eingeben';
    }
    return null;
  }

  String _matchDurationLabel() {
    final count = int.tryParse(periodCount.text.trim());
    final minutes = int.tryParse(periodMinutes.text.trim());
    if (count == null || minutes == null) return '–';
    return '$count × $minutes Minuten = ${count * minutes} Minuten';
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (savingOpponent) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (_usesClubPitch &&
        selectedPitch != 'Platz noch offen / unklar' &&
        (pitchConflictError != null || checkingPitchConflicts)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte warte auf eine erfolgreiche Platzprüfung, '
            'bevor du den Termin speicherst.',
          ),
        ),
      );
      _refreshPitchConflicts();
      return;
    }
    if (teamIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mindestens eine Mannschaft auswählen.')),
      );
      return;
    }
    if (limitParticipants && participantPlayerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens eine teilnehmende Person auswählen.'),
        ),
      );
      return;
    }
    if (endAt != null && endAt!.isBefore(startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Das Ende liegt vor dem Beginn.')),
      );
      return;
    }
    final resolvedRecurrenceUntil =
        category == EventCategory.training && recurring
            ? widget.seasonEnd
            : recurrenceUntil;
    if (recurring && resolvedRecurrenceUntil == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            category == EventCategory.training
                ? 'Für die Mannschaft ist kein Saisonende hinterlegt.'
                : 'Bitte ein Serienende auswählen.',
          ),
        ),
      );
      return;
    }
    final matchPeriodCount = int.tryParse(periodCount.text.trim()) ?? 2;
    final matchPeriodMinutes = int.tryParse(periodMinutes.text.trim()) ?? 30;
    if (category.isSingleMatch && matchPeriodCount * matchPeriodMinutes > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Die Gesamtspielzeit darf höchstens 180 Minuten betragen.'),
        ),
      );
      return;
    }
    if (category.isSingleMatch &&
        (selectedOpponentClubId == null ||
            selectedOpponentDesignation == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Verein und Jugendmannschaft auswählen.'),
        ),
      );
      return;
    }
    if (category.isSingleMatch) {
      setState(() => savingOpponent = true);
      try {
        var selected = availableOpponents
            .where(
              (item) =>
                  item.opponentClubId == selectedOpponentClubId &&
                  item.teamDesignation.toUpperCase().replaceAll(' ', '') ==
                      selectedOpponentDesignation,
            )
            .firstOrNull;
        selected ??= await widget.repository.saveOpponent(
          ageGroupId: opponentAgeGroupId,
          opponentClubId: selectedOpponentClubId,
          teamDesignation: selectedOpponentDesignation!,
        );
        selectedOpponentId = selected.id;
        selectedOpponentName = selected.displayName;
        opponent.text = selected.displayName;
      } catch (_) {
        if (!mounted) return;
        setState(() => savingOpponent = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die gegnerische Jugendmannschaft konnte nicht gespeichert '
              'werden. Bitte erneut versuchen.',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      EventWriteData(
        category: category,
        title: resolveEventTitle(title.text, category),
        startAt: startAt,
        endAt: endAt,
        meetingAt: category.isMatch &&
                meetingTimeMode == _MeetingTimeMode.beforeKickoff
            ? meetingTimeBefore(startAt, meetingMinutesBefore)
            : meetingAt,
        meetingLocation: category.isMatch &&
                homeAway == HomeAway.away &&
                meetingLocation.text.trim().isEmpty
            ? awayMeetingLocation
            : _optional(meetingLocation),
        location: location.text.trim(),
        teamIds: teamIds.toList(),
        address: _optional(address),
        mapUrl: _optional(mapUrl),
        homeAway: homeAway,
        opponent: _optional(opponent),
        opponentId: selectedOpponentId,
        periodCount: matchPeriodCount,
        periodMinutes: matchPeriodMinutes,
        venue: _usesClubPitch ? selectedPitch : _optional(venue),
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
        reminderMinutes: reminderMode == 'none'
            ? const []
            : [
                reminderMode == 'custom'
                    ? int.parse(customReminderMinutes.text.trim())
                    : int.parse(reminderMode),
              ],
        reminderPushEnabled: reminderPushEnabled,
        attachmentName: _optional(attachmentName),
        attachmentUrl: _optional(attachmentUrl),
        meinTurnierplanUrl: _optional(meinTurnierplanUrl),
        recurrence: recurring
            ? EventRecurrenceDraft(
                frequency: frequency,
                until: resolvedRecurrenceUntil!,
                interval: interval,
                weekdays: weekdays.toList(),
              )
            : null,
        requestPitchConflictApprovals: _usesClubPitch &&
            requestPitchConflictApprovals &&
            pitchConflicts.any((item) => item.headCoach != null),
        pitchConflictMessage: _optional(pitchConflictMessage),
        participantPlayerIds:
            limitParticipants ? participantPlayerIds.toList() : null,
        notificationMode:
            category.isMatch ? EventNotificationMode.none : notificationMode,
      ),
    );
  }

  bool get _usesClubPitch =>
      category != EventCategory.indoorTournament &&
      (!category.isMatch || homeAway != HomeAway.away);

  Future<void> _refreshPitchConflicts() async {
    final revision = ++pitchCheckRevision;
    if (!mounted) return;
    if (!_usesClubPitch ||
        selectedPitch == 'Platz noch offen / unklar' ||
        teamIds.isEmpty) {
      if (mounted) {
        setState(() {
          checkingPitchConflicts = false;
          pitchConflicts = const [];
          pitchConflictError = null;
        });
      }
      return;
    }
    setState(() {
      checkingPitchConflicts = true;
      pitchConflictError = null;
    });
    try {
      final conflicts = await widget.repository.checkPitchConflicts(
        startAt: startAt,
        endAt: endAt,
        pitch: selectedPitch,
        homeAway: homeAway?.name.toUpperCase() ?? 'HOME',
        teamIds: teamIds.toList(),
        periodCount: int.tryParse(periodCount.text.trim()) ?? 2,
        periodMinutes: int.tryParse(periodMinutes.text.trim()) ?? 30,
      );
      if (!mounted || revision != pitchCheckRevision) return;
      setState(() {
        pitchConflicts = conflicts;
        checkingPitchConflicts = false;
        pitchConflictError = null;
      });
    } catch (_) {
      if (!mounted || revision != pitchCheckRevision) return;
      setState(() {
        pitchConflicts = const [];
        checkingPitchConflicts = false;
        pitchConflictError =
            'Die Platzbelegung konnte gerade nicht geprüft werden. '
            'Bitte erneut versuchen, bevor du den Termin speicherst.';
      });
    }
  }

  Future<void> _quickAddOpponentClub() async {
    final club = TextEditingController();
    final venue = TextEditingController();
    final clubAddress = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verein hinzufügen'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: club,
                decoration: const InputDecoration(labelText: 'Verein *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: venue,
                decoration: const InputDecoration(
                  labelText: 'Spielstätte (optional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: clubAddress,
                decoration: const InputDecoration(
                  labelText: 'Adresse (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
    try {
      if (save != true || club.text.trim().isEmpty) {
        return;
      }
      final created = await widget.repository.saveOpponentClub(
        name: club.text.trim(),
        venue: venue.text.trim().isEmpty ? null : venue.text.trim(),
        address:
            clubAddress.text.trim().isEmpty ? null : clubAddress.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        availableOpponentClubs = [...availableOpponentClubs, created]
          ..sort((a, b) => a.name.compareTo(b.name));
        selectedOpponentClubId = created.id;
        selectedOpponentDesignation = null;
        selectedOpponentId = null;
        selectedOpponentName = null;
        opponent.clear();
      });
    } finally {
      club.dispose();
      venue.dispose();
      clubAddress.dispose();
    }
  }
}

class _OpponentLogo extends StatelessWidget {
  const _OpponentLogo({required this.url, required this.label});
  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 14,
        backgroundColor: AppColors.background,
        backgroundImage: url == null ? null : NetworkImage(url!),
        child: url == null
            ? Text(label.isEmpty ? '?' : label[0].toUpperCase())
            : null,
      );
}

class _PitchConflictPanel extends StatelessWidget {
  const _PitchConflictPanel({
    required this.checking,
    required this.pitchIsOpen,
    required this.error,
    required this.conflicts,
    required this.requestApprovals,
    required this.messageController,
    required this.onRequestApprovalsChanged,
  });

  final bool checking;
  final bool pitchIsOpen;
  final String? error;
  final List<PitchConflictPreview> conflicts;
  final bool requestApprovals;
  final TextEditingController messageController;
  final ValueChanged<bool> onRequestApprovalsChanged;

  @override
  Widget build(BuildContext context) {
    if (pitchIsOpen) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.help_outline_rounded),
          title: Text('Platz noch offen'),
          subtitle: Text(
            'Sobald Platz 1 oder Platz 2 gewählt ist, wird die '
            'Trainingsbelegung automatisch geprüft.',
          ),
        ),
      );
    }
    if (checking) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              LogoLoadingIndicator(
                size: 30,
                semanticsLabel: 'Platzbelegung wird geprüft',
              ),
              SizedBox(width: 12),
              Text('Platzbelegung wird geprüft …'),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: Icon(
            Icons.cloud_off_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Platzprüfung nicht möglich'),
          subtitle: Text(error!),
        ),
      );
    }
    if (conflicts.isEmpty) {
      return Card(
        color: Colors.green.withValues(alpha: .08),
        child: const ListTile(
          leading: Icon(Icons.check_circle_rounded, color: Colors.green),
          title: Text('Kein Trainingskonflikt'),
          subtitle: Text('Der gewählte Platz ist in diesem Zeitraum frei.'),
        ),
      );
    }
    final requestable = conflicts
        .where((item) => item.requiresApproval && item.headCoach != null)
        .length;
    final recreational =
        conflicts.where((item) => item.kind == 'RECREATIONAL').length;
    return Card(
      color:
          Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${conflicts.length} Trainingskonflikt'
                    '${conflicts.length == 1 ? '' : 'e'} erkannt',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final conflict in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.sports_soccer_rounded),
                    title: Text(
                      '${conflict.trainingTeamName}: '
                      '${conflict.weekday} ${conflict.startLabel}–${conflict.endLabel} Uhr',
                    ),
                    subtitle: Text(
                      '${conflict.pitch}\n'
                      '${conflict.kind == 'RECREATIONAL' ? 'Jugend hat Vorrang · Freizeitkicker werden nur informiert' : conflict.kind == 'SENIORS' ? 'Vereinsbelegung ohne digitale Freigabeanfrage' : conflict.headCoach == null ? 'Kein Haupttrainer hinterlegt' : 'Haupttrainer: ${conflict.headCoach!.name}'}',
                    ),
                    isThreeLine: true,
                    trailing: conflict.headCoach?.phone == null
                        ? null
                        : IconButton(
                            tooltip: 'Haupttrainer anrufen',
                            onPressed: () => launchUrl(
                              Uri(
                                scheme: 'tel',
                                path: conflict.headCoach!.phone,
                              ),
                            ),
                            icon: const Icon(Icons.phone_rounded),
                          ),
                  ),
                ),
              ),
            if (requestable > 0) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: requestApprovals,
                onChanged: onRequestApprovalsChanged,
                title: Text(
                  requestable == 1
                      ? 'Freigabe beim Haupttrainer anfragen'
                      : 'Freigaben bei den Haupttrainern anfragen',
                ),
                subtitle: const Text(
                  'Die Anfrage erscheint direkt unter Nachrichten und als Benachrichtigung.',
                ),
              ),
              if (requestApprovals)
                TextFormField(
                  controller: messageController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Nachricht zur Abstimmung (optional)',
                    hintText:
                        'z. B. Freundschaftsspiel – können wir euer Training verlegen?',
                  ),
                ),
            ],
            if (recreational > 0) ...[
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: requestable > 0 ? 12 : 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.teal.withValues(alpha: .25),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.teal),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Jugendmannschaften haben gegenüber den Freizeitkickern '
                        'immer Vorrang. Beim Speichern wird deshalb keine Anfrage '
                        'gestellt; die Freizeitkicker und die Systemadministration '
                        'erhalten automatisch eine Information zur Belegung.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (requestable == 0 && recreational == 0) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Eine direkte Anfrage ist noch nicht möglich, weil bei der '
                  'betroffenen Mannschaft kein freigegebener Haupttrainer '
                  'hinterlegt ist. Bitte die Trainerzuordnung unter '
                  '„Mitglieder & Freigaben“ ergänzen.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeasonSeriesInfo extends StatelessWidget {
  const _SeasonSeriesInfo({
    required this.seasonName,
    required this.seasonEnd,
  });

  final String? seasonName;
  final DateTime? seasonEnd;

  @override
  Widget build(BuildContext context) {
    final end = seasonEnd;
    final endLabel = end == null
        ? 'dem hinterlegten Saisonende'
        : '${end.day.toString().padLeft(2, '0')}.'
            '${end.month.toString().padLeft(2, '0')}.${end.year}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.teal.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_repeat_rounded, color: AppColors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Die Trainingsserie gilt automatisch für die Saison '
              '${seasonName ?? ''} bis $endLabel. '
              'Ein manuelles Serienende ist nicht nötig.',
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchMeetingTimeField extends StatelessWidget {
  const _MatchMeetingTimeField({
    required this.mode,
    required this.minutesBefore,
    required this.startAt,
    required this.exactMeetingAt,
    required this.onModeChanged,
    required this.onMinutesChanged,
    required this.onExactTimeChanged,
  });

  final _MeetingTimeMode mode;
  final int minutesBefore;
  final DateTime startAt;
  final DateTime? exactMeetingAt;
  final ValueChanged<_MeetingTimeMode> onModeChanged;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<DateTime?> onExactTimeChanged;

  @override
  Widget build(BuildContext context) {
    final calculatedMeetingAt = meetingTimeBefore(startAt, minutesBefore);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Treffpunkt',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<_MeetingTimeMode>(
          segments: const [
            ButtonSegment(
              value: _MeetingTimeMode.beforeKickoff,
              icon: Icon(Icons.timer_outlined),
              label: Text('Vor Spielbeginn'),
            ),
            ButtonSegment(
              value: _MeetingTimeMode.exactTime,
              icon: Icon(Icons.schedule_rounded),
              label: Text('Feste Uhrzeit'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        const SizedBox(height: 12),
        if (mode == _MeetingTimeMode.beforeKickoff)
          DropdownButtonFormField<int>(
            initialValue: minutesBefore,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Abstand vor Spielbeginn',
              helperText: 'Treffpunkt: ${_fullDate(calculatedMeetingAt)} · '
                  '${_time(calculatedMeetingAt)} Uhr',
              prefixIcon: const Icon(Icons.notifications_active_outlined),
            ),
            items: [
              for (final minutes in meetingOffsetOptions)
                DropdownMenuItem(
                  value: minutes,
                  child: Text(_meetingOffsetLabel(minutes)),
                ),
            ],
            onChanged: (value) {
              if (value != null) onMinutesChanged(value);
            },
          )
        else
          _DateTimeField(
            label: 'Treffpunktzeit',
            value: exactMeetingAt,
            allowClear: true,
            onChanged: onExactTimeChanged,
          ),
      ],
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
    this.compact = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final bool dateOnly;
  final bool compact;

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
        onChanged(
            DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: compact,
          contentPadding:
              compact ? const EdgeInsets.fromLTRB(12, 12, 6, 9) : null,
          suffixIcon: allowClear && value != null
              ? IconButton(
                  tooltip: 'Auswahl löschen',
                  onPressed: () => onChanged(null),
                  visualDensity: compact ? VisualDensity.compact : null,
                  icon: Icon(Icons.clear_rounded, size: compact ? 18 : 24),
                )
              : Icon(
                  Icons.calendar_today_rounded,
                  size: compact ? 17 : 24,
                ),
        ),
        child: Text(
          value == null
              ? 'Auswählen'
              : dateOnly
                  ? _fullDate(value!)
                  : compact
                      ? '${value!.day}.${value!.month}.'
                          '${value!.year.toString().substring(2)}\n'
                          '${_time(value!)} Uhr'
                      : '${_fullDate(value!)} · ${_time(value!)} Uhr',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: compact
              ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)
              : null,
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
              for (final value in AttendanceStatus.values.where(
                (value) =>
                    widget.event.type != EventType.match ||
                    value != AttendanceStatus.maybe,
              ))
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) => setState(() => status = value ?? status),
          ),
          if (status == AttendanceStatus.no) ...[
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Grund (optional)'),
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
    departureAt = widget.event.meetingAt ??
        widget.event.startAt.subtract(const Duration(minutes: 30));
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

class _CarpoolNeedDraft {
  const _CarpoolNeedDraft({required this.playerIds, this.note});

  final List<String> playerIds;
  final String? note;
}

class _CarpoolNeedDialog extends StatefulWidget {
  const _CarpoolNeedDialog({required this.players});

  final List<PlayerModel> players;

  @override
  State<_CarpoolNeedDialog> createState() => _CarpoolNeedDialogState();
}

class _CarpoolNeedDialogState extends State<_CarpoolNeedDialog> {
  final selected = <String>{};
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mitfahrt benötigt'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wähle alle Kinder aus, die eine Mitfahrgelegenheit brauchen.',
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final player in widget.players)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(player.id),
                      title: Text(player.fullName),
                      subtitle: Text(player.teamCode),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          selected.add(player.id);
                        } else {
                          selected.remove(player.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Hinweis (optional)',
                hintText: 'z. B. Rückfahrt wird ebenfalls benötigt',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _CarpoolNeedDraft(
                      playerIds: selected.toList(),
                      note: note.text.trim().isEmpty ? null : note.text.trim(),
                    ),
                  ),
          child: Text(
            selected.length == 1
                ? 'Bedarf melden'
                : '${selected.length} Bedarfe melden',
          ),
        ),
      ],
    );
  }
}

class _CarpoolPlayerSelectionDialog extends StatefulWidget {
  const _CarpoolPlayerSelectionDialog({
    required this.players,
    required this.maxSelections,
  });

  final List<PlayerModel> players;
  final int maxSelections;

  @override
  State<_CarpoolPlayerSelectionDialog> createState() =>
      _CarpoolPlayerSelectionDialogState();
}

class _CarpoolPlayerSelectionDialogState
    extends State<_CarpoolPlayerSelectionDialog> {
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mitfahrplätze anfragen'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wähle bis zu ${widget.maxSelections} '
              '${widget.maxSelections == 1 ? 'Kind' : 'Kinder'} aus.',
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final player in widget.players)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(player.id),
                      title: Text(player.fullName),
                      subtitle: Text(player.teamCode),
                      onChanged: !selected.contains(player.id) &&
                              selected.length >= widget.maxSelections
                          ? null
                          : (value) => setState(() {
                                if (value == true) {
                                  selected.add(player.id);
                                } else {
                                  selected.remove(player.id);
                                }
                              }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(context, selected.toList()),
          child: Text(
            selected.length == 1
                ? 'Platz anfragen'
                : '${selected.length} Plätze anfragen',
          ),
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

String _meetingOffsetLabel(int minutes) {
  if (minutes < 60) return '$minutes Minuten vor Spielbeginn';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  final hourLabel = hours == 1 ? '1 Stunde' : '$hours Stunden';
  return remainingMinutes == 0
      ? '$hourLabel vor Spielbeginn'
      : '$hourLabel $remainingMinutes Minuten vor Spielbeginn';
}

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
      CalendarView.month ||
      CalendarView.agenda =>
        '${_month(value.month)} ${value.year}',
      CalendarView.year => '${value.year}',
    };

String _calendarViewLabel(CalendarView view) => switch (view) {
      CalendarView.day => 'Tag',
      CalendarView.week => 'Woche',
      CalendarView.month => 'Monat',
      CalendarView.year => 'Jahr',
      CalendarView.agenda => 'Agenda',
    };

String _apiErrorMessage(DioException error, String fallback) {
  final data = error.response?.data;
  if (data is Map<String, dynamic>) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) return message;
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout) {
    return 'Keine Verbindung zum Terminserver. Bitte Internetverbindung prüfen und erneut versuchen.';
  }
  if (error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout) {
    return 'Der Terminserver hat nicht rechtzeitig geantwortet. '
        'Bitte den Kalender neu laden, bevor der Termin erneut angelegt wird.';
  }
  return fallback;
}

Color _categoryColor(EventCategory category) {
  if (category == EventCategory.training) return AppColors.teal;
  if (category.isMatch) return AppColors.blue;
  if (category == EventCategory.parentsMeeting ||
      category == EventCategory.teamMeeting) {
    return const Color(0xFF7C4DFF);
  }
  return AppColors.orange;
}

String _categoryEmoji(EventCategory category) => switch (category) {
      EventCategory.training => '🏃',
      EventCategory.leagueMatch => '⚽',
      EventCategory.friendlyMatch => '🤝',
      EventCategory.cupMatch => '🏆',
      EventCategory.tournament => '🥇',
      EventCategory.indoorTournament => '🏟️',
      EventCategory.footballFestival => '🎉',
      EventCategory.teamMeeting => '🗣️',
      EventCategory.parentsMeeting => '👨‍👩‍👧',
      EventCategory.christmasParty => '🎄',
      EventCategory.seasonClosing => '🏁',
      EventCategory.clubEvent => '🎪',
      EventCategory.trip => '🚌',
      EventCategory.photoSession => '📸',
      EventCategory.specialEvent => '📌',
    };

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
