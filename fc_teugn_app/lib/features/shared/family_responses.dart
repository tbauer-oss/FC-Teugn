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
                color: AppColors.orange.withValues(alpha: .16),
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.orange,
                      foregroundColor: AppColors.navy,
                      child: Icon(Icons.how_to_reg_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${open.length} ${open.length == 1 ? 'Rückmeldung ist' : 'Rückmeldungen sind'} offen',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: AppColors.navy,
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

class FamilyResponsesPage extends ConsumerWidget {
  const FamilyResponsesPage({
    super.key,
    required this.isTrainer,
    this.highlightedEventId,
    this.highlightedPlayerId,
  });
  final bool isTrainer;
  final String? highlightedEventId;
  final String? highlightedPlayerId;

  bool _isHighlighted(PersonalResponseModel item) =>
      item.eventId == highlightedEventId &&
      (highlightedPlayerId == null || item.playerId == highlightedPlayerId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responses = ref.watch(personalResponsesProvider);
    return PageScaffold(
      title: 'Meine Kinder & Rückmeldungen',
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
          final sorted = [...items]..sort((a, b) {
              final aHighlighted = _isHighlighted(a);
              final bHighlighted = _isHighlighted(b);
              if (aHighlighted != bHighlighted) return aHighlighted ? -1 : 1;
              if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
              return a.startAt.compareTo(b.startAt);
            });
          if (sorted.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.family_restroom_rounded, size: 46),
                    SizedBox(height: 12),
                    Text(
                        'Aktuell sind keine persönlichen Rückmeldungen vorhanden.'),
                  ],
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                key: const ValueKey('family-response-summary-scroll'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ResponseSummaryPill(
                      label: 'Offen',
                      count: sorted.where((item) => item.isOpen).length,
                      color: AppColors.orange,
                      dense: true,
                    ),
                    const SizedBox(width: 6),
                    ResponseSummaryPill(
                      label: 'Zugesagt',
                      count: sorted
                          .where((item) =>
                              item.responseStatus == AttendanceStatus.yes)
                          .length,
                      color: AppColors.teal,
                      dense: true,
                    ),
                    const SizedBox(width: 6),
                    ResponseSummaryPill(
                      label: 'Vielleicht',
                      count: sorted
                          .where((item) =>
                              item.responseStatus == AttendanceStatus.maybe)
                          .length,
                      color: AppColors.orange,
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
              const SizedBox(height: 8),
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
      AttendanceStatus.maybe => 'Vielleicht',
      AttendanceStatus.unknown => 'Offen',
    };
    final statusColor = switch (item.responseStatus) {
      AttendanceStatus.yes => AppColors.teal,
      AttendanceStatus.no => Colors.redAccent,
      AttendanceStatus.maybe => AppColors.orange,
      AttendanceStatus.unknown => AppColors.muted,
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
      padding: EdgeInsets.all(narrowPage ? 10 : 16),
      decoration: BoxDecoration(
        color:
            widget.highlighted ? AppColors.orange.withValues(alpha: .10) : null,
        border: Border(
          left: widget.highlighted
              ? const BorderSide(color: AppColors.orange, width: 4)
              : BorderSide.none,
          bottom: const BorderSide(color: AppColors.line),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 660;
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: narrow ? 17 : 20,
                backgroundColor: AppColors.navy.withValues(alpha: .08),
                child: Icon(
                  Icons.event_available_rounded,
                  color: AppColors.navy,
                  size: narrow ? 18 : 24,
                ),
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
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
                          style: const TextStyle(
                            color: AppColors.muted,
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
                    AttendanceStatus.maybe => 'Vielleicht',
                    AttendanceStatus.unknown => 'Offen',
                  }),
                );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 7),
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
      await Future.wait<void>([
        ref.read(personalResponsesProvider.future).then<void>((_) {}),
        ref.read(eventsProvider.future).then<void>((_) {}),
      ]);
      widget.onSaved?.call();
      if (mounted) {
        final result = switch (status) {
          AttendanceStatus.yes => 'Zusage',
          AttendanceStatus.maybe => '„Vielleicht“',
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
        allowMaybe: !widget.item.isMatch,
        onAnswer: _answer,
      );
}

class _AttendanceResponseActions extends StatelessWidget {
  const _AttendanceResponseActions({
    required this.expanded,
    required this.saving,
    required this.allowMaybe,
    required this.onAnswer,
  });

  final bool expanded;
  final bool saving;
  final bool allowMaybe;
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
      if (allowMaybe)
        FilledButton.tonalIcon(
          style: expanded ? compactStyle : null,
          onPressed: saving ? null : () => onAnswer(AttendanceStatus.maybe),
          icon: Icon(Icons.help_outline_rounded, size: expanded ? 15 : 18),
          label: const Text('Vielleicht'),
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
            color: Colors.white,
            border: Border.all(color: AppColors.line),
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
