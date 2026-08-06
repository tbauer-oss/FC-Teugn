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
      subtitle: 'Zu- und Absagen für alle dir zugeordneten Kinder.',
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SummaryChip(
                    label: 'Offen',
                    count: sorted.where((item) => item.isOpen).length,
                    color: AppColors.orange,
                  ),
                  _SummaryChip(
                    label: 'Zugesagt',
                    count: sorted
                        .where((item) =>
                            item.responseStatus == AttendanceStatus.yes)
                        .length,
                    color: AppColors.teal,
                  ),
                  _SummaryChip(
                    label: 'Abgesagt',
                    count: sorted
                        .where((item) =>
                            item.responseStatus == AttendanceStatus.no)
                        .length,
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
  bool _saving = false;

  Future<void> _answer(AttendanceStatus status) async {
    String? reason;
    if (status == AttendanceStatus.no) {
      final controller = TextEditingController();
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
      await Future.wait<void>([
        ref.read(personalResponsesProvider.future).then<void>((_) {}),
        ref.read(eventsProvider.future).then<void>((_) {}),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == AttendanceStatus.yes
                  ? 'Zusage für ${widget.item.playerName} gespeichert.'
                  : 'Absage für ${widget.item.playerName} gespeichert.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Rückmeldung konnte nicht gespeichert werden: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final date = item.startAt;
    final details = [
      '${date.day}.${date.month}.${date.year}',
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} Uhr',
      if (item.meetingLocation?.isNotEmpty == true)
        'Treffpunkt: ${item.meetingLocation}'
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
              : '/parent/events');
    }

    return Container(
      padding: const EdgeInsets.all(16),
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
                backgroundColor: AppColors.navy.withValues(alpha: .08),
                child: const Icon(Icons.event_available_rounded,
                    color: AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(item.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
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
                    Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
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
                  ],
                ),
              ),
            ],
          );
          final actions = item.canRespond
              ? Row(
                  mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (narrow)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _answer(AttendanceStatus.yes),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Zusagen'),
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _answer(AttendanceStatus.yes),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Zusagen'),
                      ),
                    const SizedBox(width: 8),
                    if (narrow)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _answer(AttendanceStatus.no),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Absagen'),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed:
                            _saving ? null : () => _answer(AttendanceStatus.no),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Absagen'),
                      ),
                  ],
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
                const SizedBox(height: 12),
                actions,
                TextButton.icon(
                  onPressed: openDetails,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Details'),
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

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(
      {required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text('$count'),
        ),
        label: Text(label),
      );
}
