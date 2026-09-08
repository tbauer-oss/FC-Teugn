import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';
import '../../core/push/push_action_route.dart';
import '../auth/auth_controller.dart';
import '../parent/family_assistant_model.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

final familyTaskListProvider =
    FutureProvider.autoDispose<List<Json>>((ref) async {
  ref.watch(manualDataRefreshProvider);
  ref.watch(talentsDataVersionProvider);
  final responsesFuture = ref.watch(personalResponsesProvider.future);
  final consentFuture = ref.watch(parentConsentAttentionProvider.future);
  final summaryFuture = ref.watch(parentDashboardSummaryProvider.future);
  final repository = ref.watch(talentsRepositoryProvider);
  final user = ref.watch(authProvider).user!;
  final results = await Future.wait<dynamic>([
    responsesFuture,
    consentFuture,
    summaryFuture,
    repository.get('/assistant'),
    repository.get('/polls')
  ]);
  final responses = await responsesFuture;
  final consents = await consentFuture;
  final summary = await summaryFuture;
  final base = user.isTrainer ? '/trainer' : '/parent';
  final own = summary.players.map((p) => p.id).toSet();
  final now = DateTime.now();
  final tasks = <Json>[
    ...objects(results[3]).map((t) => {
          ...t,
          'route': (t['route'] as String).startsWith('/operations')
              ? '$base${t['route']}'
              : roleCorrectPushActionRoute(t['route'] as String,
                  isTrainer: user.isTrainer)
        }),
    for (final r in responses
        .where((r) => r.isOpen && r.canRespond && r.startAt.isAfter(now)))
      {
        'id': 'response:${r.eventId}:${r.playerId}',
        'title': 'Rückmeldung: ${r.title}',
        'detail': '${r.playerName}${r.reason == null ? '' : ' · ${r.reason}'}',
        'playerId': r.playerId,
        'dueAt': (r.responseDeadline ?? r.startAt).toIso8601String(),
        'route': '$base/family?eventId=${r.eventId}&playerId=${r.playerId}',
      },
    for (final c in consents.where((c) => c.openCount > 0))
      {
        'id': 'consent:${c.playerId}',
        'title':
            '${c.openCount} Einwilligung${c.openCount == 1 ? '' : 'en'} prüfen',
        'detail': c.playerName,
        'playerId': c.playerId,
        'route': '$base/players/${c.playerId}?consents=1'
      },
    for (final p in objects(results[4])
        .where((p) => p['closed'] != true && p['archivedAt'] == null))
      for (final u
          in objects(p['myUnits']).where((u) => u['respondedAt'] == null))
        {
          'id': 'poll:${u['id']}',
          'title': p['question'],
          'detail': 'Umfrage · ${u['label']}',
          'dueAt': p['endsAt'],
          'route': '$base/talents/polls'
        },
  ];
  for (final e in summary.events
      .where((e) => !e.isCancelled && e.startAt.isAfter(now))) {
    for (final need in e.carpoolNeeds.where((n) =>
        n.status == CarpoolNeedStatus.open &&
        (own.contains(n.playerId) || n.passengerUserId == user.id))) {
      tasks.add({
        'id': 'carpool:${need.id}',
        'title': 'Mitfahrt organisieren',
        'detail': '${need.playerName} · ${e.title}',
        'playerId': need.playerId,
        'dueAt': e.startAt.toIso8601String(),
        'route': '$base/events?eventId=${e.id}'
      });
    }
    for (final offer in e.carpoolOffers.where((o) => o.driverId == user.id)) {
      final requested = offer.passengers
          .where((p) => p.status == CarpoolRequestStatus.requested)
          .length;
      if (requested > 0) {
        tasks.add({
          'id': 'passengers:${offer.id}',
          'title':
              '$requested Mitfahranfrage${requested == 1 ? '' : 'n'} prüfen',
          'detail': e.title,
          'dueAt': offer.departureAt.toIso8601String(),
          'route': '$base/events?eventId=${e.id}'
        });
      }
    }
  }
  tasks.sort((a, b) => (DateTime.tryParse(a['dueAt']?.toString() ?? '') ??
          DateTime(2100))
      .compareTo(
          DateTime.tryParse(b['dueAt']?.toString() ?? '') ?? DateTime(2100)));
  return tasks;
});

class AssistantPage extends ConsumerWidget {
  const AssistantPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(familyTaskListProvider);
    final summary = ref.watch(parentDashboardSummaryProvider).valueOrNull;
    final responses = ref.watch(personalResponsesProvider).valueOrNull ?? [];
    final user = ref.watch(authProvider).user!;
    final conflicts = <String>{};
    final attending = responses
        .where((r) =>
            r.responseStatus == AttendanceStatus.yes &&
            r.startAt.isAfter(DateTime.now()))
        .toList();
    for (var i = 0; i < attending.length; i++) {
      for (var j = i + 1; j < attending.length; j++) {
        final a = attending[i], b = attending[j];
        if (a.eventId == b.eventId) continue;
        final endA =
            summary?.events.where((e) => e.id == a.eventId).firstOrNull?.endAt;
        final endB =
            summary?.events.where((e) => e.id == b.eventId).firstOrNull?.endAt;
        if (endA != null &&
            endB != null &&
            a.startAt.isBefore(endB) &&
            b.startAt.isBefore(endA)) {
          conflicts.add(
              '${a.playerName}: ${a.title} und ${b.playerName}: ${b.title} am ${showDate(a.startAt)} überschneiden sich.');
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => TalentsEmpty(
              text: talentsError(e),
              action: OutlinedButton(
                  onPressed: () => ref.invalidate(familyTaskListProvider),
                  child: const Text('Erneut laden'))),
          data: (items) => items.isEmpty
              ? const TalentsEmpty(
                  text:
                      'Alles erledigt! Aktuell gibt es keine offenen Aufgaben für deine Familie.')
              : Column(children: [
                  for (final t in items)
                    Card(
                        child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Icon(t['dueAt'] != null &&
                                    DateTime.parse(t['dueAt'] as String)
                                        .isBefore(DateTime.now())
                                ? Icons.priority_high
                                : Icons.task_alt),
                            title: Text(t['title'] as String),
                            subtitle: Text(
                                '${t['detail'] ?? ''}${t['dueAt'] == null ? '' : '\nBis ${showDate(t['dueAt'])}'}'),
                            isThreeLine: t['dueAt'] != null,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(t['route'] as String))),
                ])),
      if (conflicts.isNotEmpty)
        TalentsCard(title: 'Termine überschneiden sich', children: [
          for (final c in conflicts)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(c))
        ]),
      for (final n in (summary?.notifications ?? [])
          .where((n) => !n.isRead && isScheduleChangeNotification(n)))
        TalentsCard(title: n.title, subtitle: showDate(n.createdAt), children: [
          Text(n.body),
          TextButton(
              onPressed: () => context.go(roleCorrectPushActionRoute(
                  n.actionUrl ?? '/messages',
                  isTrainer: user.isTrainer)),
              child: const Text('Änderung ansehen'))
        ]),
    ]);
  }
}
