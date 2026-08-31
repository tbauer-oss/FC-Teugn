import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/models/personal_response.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import 'page_scaffold.dart';

class PersonalResponsesCard extends ConsumerWidget {
  const PersonalResponsesCard({
    super.key,
    required this.isTrainer,
    this.previewCount = 3,
  });

  final bool isTrainer;
  final int previewCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responses = ref.watch(personalResponsesProvider);
    return responses.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: LinearProgressIndicator(),
        ),
      ),
      error: (_, __) => Card(
        child: ListTile(
          leading: const Icon(Icons.sync_problem_rounded),
          title: const Text(
              'Persönliche Rückmeldungen konnten nicht geladen werden.'),
          trailing: IconButton(
            tooltip: 'Erneut laden',
            onPressed: () => ref.invalidate(personalResponsesProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      ),
      data: (items) {
        final open = items.where((item) => item.isOpen).toList()
          ..sort(_compareByUrgency);
        if (open.isEmpty) return const SizedBox.shrink();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: context.appWarning.withValues(alpha: .16),
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: context.appWarning,
                      foregroundColor: context.appColors.text,
                      child: const Icon(Icons.how_to_reg_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${open.length} ${open.length == 1 ? 'Rückmeldung ist' : 'Rückmeldungen sind'} offen',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: context.appColors.text,
                            ),
                          ),
                          const Text(
                              'Für deine zugeordneten Kinder – unabhängig von deiner Vereinsrolle.'),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go(
                        isTrainer ? '/trainer/family' : '/parent/family',
                      ),
                      child: const Text('Alle'),
                    ),
                  ],
                ),
              ),
              for (final item in open.take(previewCount))
                _ResponseTile(item: item),
            ],
          ),
        );
      },
    );
  }
}

class FamilyResponsesPage extends ConsumerStatefulWidget {
  const FamilyResponsesPage({
    super.key,
    required this.isTrainer,
    this.highlightedEventId,
    this.highlightedPlayerId,
  });
  final bool isTrainer;
  final String? highlightedEventId;
  final String? highlightedPlayerId;

  @override
  ConsumerState<FamilyResponsesPage> createState() =>
      _FamilyResponsesPageState();
}

class _FamilyResponsesPageState extends ConsumerState<FamilyResponsesPage> {
  @override
  void initState() {
    super.initState();
    if (widget.highlightedEventId != null) {
      Future.microtask(() {
        if (mounted) {
          ref.read(personalResponsePeriodProvider.notifier).state =
              PersonalResponsePeriod.allUpcoming;
        }
      });
    }
  }

  bool _isHighlighted(PersonalResponseModel item) =>
      item.eventId == widget.highlightedEventId &&
      (widget.highlightedPlayerId == null ||
          item.playerId == widget.highlightedPlayerId);

  @override
  Widget build(BuildContext context) {
    final responses = ref.watch(personalResponsesProvider);
    final period = ref.watch(personalResponsePeriodProvider);
    return PageScaffold(
      title: 'Rückmeldungen für meine Kinder',
      subtitle: 'Rückmeldungen für alle dir zugeordneten Kinder.',
      denseMobileHeader: true,
      child: responses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline_rounded),
            title: const Text('Rückmeldungen konnten nicht geladen werden.'),
            subtitle: Text('$error'),
            trailing: FilledButton.tonal(
              onPressed: () => ref.invalidate(personalResponsesProvider),
              child: const Text('Erneut laden'),
            ),
          ),
        ),
        data: (items) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final periodEnd = period.endFrom(today);
          final visible = items.where((item) {
            if (_isHighlighted(item)) return true;
            if (item.startAt.isBefore(today)) return false;
            return periodEnd == null || item.startAt.isBefore(periodEnd);
          }).toList();
          final sorted = [...visible]..sort((a, b) {
              final aHighlighted = _isHighlighted(a);
              final bHighlighted = _isHighlighted(b);
              if (aHighlighted != bHighlighted) return aHighlighted ? -1 : 1;
              if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
              return a.startAt.compareTo(b.startAt);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ResponsePeriodPicker(
                value: period,
                visibleCount: sorted.length,
                onChanged: (value) => ref
                    .read(personalResponsePeriodProvider.notifier)
                    .state = value,
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                key: const ValueKey('family-response-summary-scroll'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ResponseSummaryPill(
                      label: 'Offen',
                      count: sorted.where((item) => item.isOpen).length,
                      color: context.appWarning,
                      dense: true,
                    ),
                    const SizedBox(width: 6),
                    ResponseSummaryPill(
                      label: 'Zugesagt',
                      count: sorted
                          .where((item) =>
                              item.responseStatus == AttendanceStatus.yes)
                          .length,
                      color: context.appSuccess,
                      dense: true,
                    ),
                    const SizedBox(width: 6),
                    ResponseSummaryPill(
                      label: 'Abgesagt',
                      count: sorted
                          .where((item) =>
                              item.responseStatus == AttendanceStatus.no)
                          .length,
                      color: Colors.redAccent,
                      dense: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (sorted.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        const Icon(Icons.event_available_rounded, size: 42),
                        const SizedBox(height: 9),
                        Text(
                          'Keine Rückmeldungen in diesem Zeitraum',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          period == PersonalResponsePeriod.allUpcoming
                              ? 'Aktuell sind keine kommenden persönlichen Rückmeldungen vorhanden.'
                              : 'Wähle bei Bedarf einen längeren Zeitraum aus.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.appColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final item in sorted)
                        _ResponseTile(
                          item: item,
                          highlighted: _isHighlighted(item),
                        )
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

extension on PersonalResponsePeriod {
  String get label => switch (this) {
        PersonalResponsePeriod.oneWeek => '1 Woche',
        PersonalResponsePeriod.twoWeeks => '2 Wochen',
        PersonalResponsePeriod.fourWeeks => '4 Wochen',
        PersonalResponsePeriod.allUpcoming => 'Alle kommenden',
      };

  DateTime? endFrom(DateTime start) => switch (this) {
        PersonalResponsePeriod.oneWeek => start.add(const Duration(days: 7)),
        PersonalResponsePeriod.twoWeeks => start.add(const Duration(days: 14)),
        PersonalResponsePeriod.fourWeeks => start.add(const Duration(days: 28)),
        PersonalResponsePeriod.allUpcoming => null,
      };
}

class _ResponsePeriodPicker extends StatelessWidget {
  const _ResponsePeriodPicker({
    required this.value,
    required this.visibleCount,
    required this.onChanged,
  });

  final PersonalResponsePeriod value;
  final int visibleCount;
  final ValueChanged<PersonalResponsePeriod> onChanged;

  Widget _dropdown({bool expanded = false}) => DropdownButtonHideUnderline(
        child: DropdownButton<PersonalResponsePeriod>(
          value: value,
          borderRadius: BorderRadius.circular(14),
          isDense: true,
          isExpanded: expanded,
          items: [
            for (final period in PersonalResponsePeriod.values)
              DropdownMenuItem(
                value: period,
                child: Text(
                  period.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (period) {
            if (period != null) onChanged(period);
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Zeitraum der Rückmeldungen: ${value.label}',
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
            decoration: BoxDecoration(
              color: context.appColors.brandSoft,
              border: Border.all(color: context.appColors.outline),
              borderRadius: BorderRadius.circular(15),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 390;
                return Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: context.appColors.surface,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.date_range_rounded, size: 19),
                    ),
                    const SizedBox(width: 7),
                    if (compact) ...[
                      Expanded(child: _dropdown(expanded: true)),
                    ] else ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Zeitraum',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.appColors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$visibleCount ${visibleCount == 1 ? 'Termin' : 'Termine'} angezeigt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown(),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );
}

class _ResponseTile extends ConsumerStatefulWidget {
  const _ResponseTile({required this.item, this.highlighted = false});
  final PersonalResponseModel item;
  final bool highlighted;

  @override
  ConsumerState<_ResponseTile> createState() => _ResponseTileState();
}

class _ResponseTileState extends ConsumerState<_ResponseTile> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final date = item.startAt;
    final details = [
      '${date.day}.${date.month}.${date.year}',
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} Uhr',
      if (item.meetingAt != null && item.meetingLocation?.isNotEmpty == true)
        'Treffpunkt: ${item.meetingAt!.hour.toString().padLeft(2, '0')}:${item.meetingAt!.minute.toString().padLeft(2, '0')} Uhr · ${item.meetingLocation}'
      else if (item.meetingAt != null)
        'Treffpunkt: ${item.meetingAt!.hour.toString().padLeft(2, '0')}:${item.meetingAt!.minute.toString().padLeft(2, '0')} Uhr'
      else if (item.meetingLocation?.isNotEmpty == true)
        'Treffpunktort: ${item.meetingLocation}'
      else if (item.location.isNotEmpty)
        item.location,
    ].join(' · ');
    final deadline = item.responseDeadline;
    final statusLabel = switch (item.responseStatus) {
      AttendanceStatus.yes => 'Zugesagt',
      AttendanceStatus.no => 'Abgesagt',
      AttendanceStatus.maybe => 'Offen',
      AttendanceStatus.unknown => 'Offen',
    };
    final statusColor = switch (item.responseStatus) {
      AttendanceStatus.yes => context.appSuccess,
      AttendanceStatus.no => Colors.redAccent,
      AttendanceStatus.maybe => context.appColors.textMuted,
      AttendanceStatus.unknown => context.appColors.textMuted,
    };
    void openDetails() {
      final trainer = ref.read(authProvider).user?.isTrainer ?? false;
      final match = item.category.contains('MATCH') ||
          item.category.contains('TOURNAMENT') ||
          item.category == 'FOOTBALL_FESTIVAL';
      context.go(match
          ? '${trainer ? '/trainer' : '/parent'}/matches/${item.eventId}'
          : trainer
              ? '/trainer/events'
              : Uri(
                  path: '/parent/events',
                  queryParameters: {'eventId': item.eventId},
                ).toString());
    }

    final narrowPage = MediaQuery.sizeOf(context).width < 660;
    return Container(
      padding: EdgeInsets.all(narrowPage ? 8 : 14),
      decoration: BoxDecoration(
        color: widget.highlighted
            ? context.appWarning.withValues(alpha: .10)
            : null,
        border: Border(
          left: widget.highlighted
              ? BorderSide(color: context.appWarning, width: 4)
              : BorderSide.none,
          bottom: BorderSide(color: context.appColors.outline),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 660;
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: narrow ? 15 : 20,
                backgroundColor: context.appInfo.withValues(alpha: .12),
                child: Icon(
                  Icons.event_available_rounded,
                  color: context.appInfo,
                  size: narrow ? 16 : 24,
                ),
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: narrow ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label:
                              Text('${item.playerName} · ${item.ageGroupCode}'),
                        ),
                        if (!item.canRespond)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: CircleAvatar(backgroundColor: statusColor),
                            label: Text(statusLabel),
                          ),
                      ],
                    ),
                    Text(
                      details,
                      maxLines: narrow ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          narrow ? Theme.of(context).textTheme.bodySmall : null,
                    ),
                    if (item.isOverdue)
                      const Text(
                        'Rückmeldefrist abgelaufen',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700),
                      ),
                    if (!item.isOverdue && deadline != null)
                      Text(
                        'Bitte bis ${deadline.day}.${deadline.month}.${deadline.year}, '
                        '${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')} Uhr antworten',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if (item.responseStatus == AttendanceStatus.no &&
                        item.reason?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Grund: ${item.reason!.trim()}',
                          style: TextStyle(
                            color: context.appColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
          final actions = item.canRespond
              ? PersonalResponseQuickActions(
                  item: item,
                  expanded: narrow,
                )
              : Chip(
                  avatar: Icon(
                    item.responseStatus == AttendanceStatus.yes
                        ? Icons.check_circle_rounded
                        : item.responseStatus == AttendanceStatus.no
                            ? Icons.cancel_rounded
                            : Icons.schedule_rounded,
                    size: 17,
                  ),
                  label: Text(switch (item.responseStatus) {
                    AttendanceStatus.yes => 'Zugesagt',
                    AttendanceStatus.no => 'Abgesagt',
                    AttendanceStatus.maybe => 'Offen',
                    AttendanceStatus.unknown => 'Offen',
                  }),
                );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(child: actions),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: openDetails,
                      tooltip: 'Details öffnen',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.open_in_new_rounded, size: 19),
                    ),
                  ],
                ),
                if (item.isRegularTraining && item.canRespond) ...[
                  const SizedBox(height: 5),
                  _RegularTrainingSeriesAction(item: item, expanded: true),
                ],
              ],
            );
          }
          return Row(children: [
            Expanded(child: info),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                actions,
                if (item.isRegularTraining && item.canRespond) ...[
                  const SizedBox(height: 5),
                  _RegularTrainingSeriesAction(item: item),
                ],
                TextButton.icon(
                  onPressed: openDetails,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Details'),
                ),
              ],
            ),
          ]);
        },
      ),
    );
  }
}

class _RegularTrainingSeriesAction extends ConsumerWidget {
  const _RegularTrainingSeriesAction(
      {required this.item, this.expanded = false});

  final PersonalResponseModel item;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = OutlinedButton.icon(
      key: ValueKey('regular-training-series-${item.eventId}-${item.playerId}'),
      onPressed: () async {
        final result = await showModalBottomSheet<
            ({
              DateTime validUntil,
              int preservedDeclines,
            })>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _RegularTrainingSeriesSheet(item: item),
        );
        if (result == null || !context.mounted) return;
        final until = result.validUntil;
        final exceptionText = result.preservedDeclines > 0
            ? ' Bereits eingetragene Absagen bleiben erhalten.'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Regeltraining bis ${until.day}.${until.month}.${until.year} zugesagt.$exceptionText',
            ),
          ),
        );
      },
      icon: const Icon(Icons.event_repeat_rounded, size: 18),
      label: const Text('Mehrere Trainings zusagen'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        visualDensity: VisualDensity.compact,
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _RegularTrainingSeriesSheet extends ConsumerStatefulWidget {
  const _RegularTrainingSeriesSheet({required this.item});

  final PersonalResponseModel item;

  @override
  ConsumerState<_RegularTrainingSeriesSheet> createState() =>
      _RegularTrainingSeriesSheetState();
}

class _RegularTrainingSeriesSheetState
    extends ConsumerState<_RegularTrainingSeriesSheet> {
  int? _savingMonths;
  bool _savingSeason = false;

  Future<void> _save(int? months) async {
    setState(() {
      _savingMonths = months;
      _savingSeason = months == null;
    });
    try {
      final result =
          await ref.read(repositoryProvider).confirmRegularTrainingSeries(
                eventId: widget.item.eventId,
                playerId: widget.item.playerId,
                periodMonths: months,
              );
      ref.invalidate(personalResponsesProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(calendarEventsProvider);
      ref.invalidate(parentDashboardEventsProvider);
      ref.invalidate(parentMatchdaysProvider);
      ref.invalidate(parentDashboardSummaryProvider);
      ref.invalidate(trainerDashboardSummaryProvider);
      if (mounted) {
        Navigator.pop(context, (
          validUntil: result.validUntil,
          preservedDeclines: result.preservedDeclines,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die Serienzusage konnte nicht gespeichert werden. Bitte erneut versuchen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingMonths = null;
          _savingSeason = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _savingMonths != null || _savingSeason;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.appColors.brandSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.event_repeat_rounded),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Regeltraining gesammelt zusagen',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${widget.item.playerName} · ${widget.item.teamName}',
                        style: TextStyle(
                          color: context.appColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: context.appSuccess.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.appSuccess.withValues(alpha: .22),
                ),
              ),
              child: const Text(
                'Die Zusage gilt ab diesem Termin. Wenn dein Kind einmal nicht kann, kannst du den einzelnen Termin weiterhin absagen. Bereits eingetragene Absagen bleiben bestehen.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final oneColumn = constraints.maxWidth < 340;
                final width = oneColumn
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final months in const [1, 3, 6])
                      SizedBox(
                        width: width,
                        child: _SeriesPeriodButton(
                          label: months == 1 ? '1 Monat' : '$months Monate',
                          subtitle: 'ab diesem Training',
                          selected: _savingMonths == months,
                          onPressed: busy ? null : () => _save(months),
                        ),
                      ),
                    SizedBox(
                      width: width,
                      child: _SeriesPeriodButton(
                        label: 'Bis Saisonende',
                        subtitle: 'alle Regeltrainings',
                        selected: _savingSeason,
                        emphasized: true,
                        onPressed: busy ? null : () => _save(null),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesPeriodButton extends StatelessWidget {
  const _SeriesPeriodButton({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Material(
        color: emphasized
            ? context.appColors.brandSoft
            : context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color:
                    emphasized ? context.appWarning : context.appColors.outline,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (selected)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  Icon(
                    emphasized
                        ? Icons.flag_rounded
                        : Icons.calendar_month_rounded,
                    color: context.appWarning,
                    size: 21,
                  ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
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

/// Gemeinsame, kompakte Rückmeldeaktion für Familienseite und Dashboard.
/// Damit verwenden beide Oberflächen exakt denselben Speicherweg und dieselbe
/// Spielregel (bei Spielen nur Zu- oder Absage).
class PersonalResponseQuickActions extends ConsumerStatefulWidget {
  const PersonalResponseQuickActions({
    super.key,
    required this.item,
    this.expanded = false,
    this.onSaved,
  });

  final PersonalResponseModel item;
  final bool expanded;
  final VoidCallback? onSaved;

  @override
  ConsumerState<PersonalResponseQuickActions> createState() =>
      _PersonalResponseQuickActionsState();
}

class _PersonalResponseQuickActionsState
    extends ConsumerState<PersonalResponseQuickActions> {
  bool _saving = false;

  Future<void> _answer(AttendanceStatus status) async {
    String? reason;
    if (status == AttendanceStatus.no) {
      final controller = TextEditingController(
        text: widget.item.responseStatus == AttendanceStatus.no
            ? widget.item.reason ?? ''
            : '',
      );
      reason = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${widget.item.playerName} absagen?'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Grund (optional)',
              hintText: 'z. B. krank oder verhindert',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Absagen'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).setAttendance(
            eventId: widget.item.eventId,
            playerId: widget.item.playerId,
            status: status,
            reason: reason,
            personalResponse: true,
          );
      ref.invalidate(personalResponsesProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(parentMatchdaysProvider);
      ref.invalidate(parentDashboardSummaryProvider);
      ref.invalidate(trainerDashboardSummaryProvider);
      await ref.read(personalResponsesProvider.future);
      widget.onSaved?.call();
      if (mounted) {
        final result = switch (status) {
          AttendanceStatus.yes => 'Zusage',
          AttendanceStatus.maybe => 'Rückmeldung',
          AttendanceStatus.no => 'Absage',
          AttendanceStatus.unknown => 'Rückmeldung',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erfolgreich gespeichert: $result für ${widget.item.playerName}.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die Rückmeldung konnte nicht gespeichert werden. Bitte Verbindung prüfen und erneut versuchen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AttendanceResponseActions(
        expanded: widget.expanded,
        saving: _saving,
        onAnswer: _answer,
      );
}

class _AttendanceResponseActions extends StatelessWidget {
  const _AttendanceResponseActions({
    required this.expanded,
    required this.saving,
    required this.onAnswer,
  });

  final bool expanded;
  final bool saving;
  final ValueChanged<AttendanceStatus> onAnswer;

  @override
  Widget build(BuildContext context) {
    final compactStyle = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(0, 36)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      ),
      visualDensity: VisualDensity.compact,
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
    final buttons = <Widget>[
      FilledButton.icon(
        style: expanded ? compactStyle : null,
        onPressed: saving ? null : () => onAnswer(AttendanceStatus.yes),
        icon: Icon(Icons.check_rounded, size: expanded ? 15 : 18),
        label: const Text('Zusagen'),
      ),
      OutlinedButton.icon(
        style: expanded ? compactStyle : null,
        onPressed: saving ? null : () => onAnswer(AttendanceStatus.no),
        icon: Icon(Icons.close_rounded, size: expanded ? 15 : 18),
        label: const Text('Absagen'),
      ),
    ];

    if (expanded) {
      return Row(
        children: [
          for (var index = 0; index < buttons.length; index++) ...[
            Expanded(
              child: ButtonTheme(
                alignedDropdown: true,
                child: buttons[index],
              ),
            ),
            if (index != buttons.length - 1) const SizedBox(width: 4),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: buttons,
    );
  }
}

int _compareByUrgency(PersonalResponseModel a, PersonalResponseModel b) {
  if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
  final aDeadline = a.responseDeadline;
  final bDeadline = b.responseDeadline;
  if (aDeadline != null && bDeadline != null) {
    final deadlineOrder = aDeadline.compareTo(bDeadline);
    if (deadlineOrder != 0) return deadlineOrder;
  } else if (aDeadline != null || bDeadline != null) {
    return aDeadline != null ? -1 : 1;
  }
  return a.startAt.compareTo(b.startAt);
}

class ResponseSummaryPill extends StatelessWidget {
  const ResponseSummaryPill({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    this.dense = false,
  });
  final String label;
  final int count;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $count',
        child: Container(
          constraints: BoxConstraints(minHeight: dense ? 32 : 38),
          padding: EdgeInsets.fromLTRB(
            dense ? 4 : 6,
            dense ? 3 : 5,
            dense ? 9 : 12,
            dense ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border.all(color: context.appColors.outline),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(
                  minWidth: dense ? 24 : 28,
                  minHeight: dense ? 24 : 28,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: dense ? 12 : 14,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(width: dense ? 6 : 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: dense ? 12 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
