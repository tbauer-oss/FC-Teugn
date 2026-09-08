import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers.dart';
import '../../core/push/push_action_route.dart';
import 'report_dialog.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

final matchReadinessProvider =
    FutureProvider.autoDispose.family<Json, String>((ref, id) {
  ref.watch(manualDataRefreshProvider);
  return ref.watch(talentsRepositoryProvider).object('/matches/$id/readiness');
});

class MatchReadinessCard extends ConsumerWidget {
  const MatchReadinessCard({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(matchReadinessProvider(eventId)).when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: const Text('Organisation nicht geladen'),
              trailing: IconButton(
                  tooltip: 'Organisation erneut laden',
                  onPressed: () =>
                      ref.invalidate(matchReadinessProvider(eventId)),
                  icon: const Icon(Icons.refresh))),
          data: (data) {
            final checks = objects(data['checks']);
            final open = checks.where((c) => c['ready'] != true).length;
            final ordered = [
              ...checks.where((c) => c['ready'] != true),
              ...checks.where((c) => c['ready'] == true),
            ];
            return Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                  key: PageStorageKey('match-organisation-$eventId'),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  leading: Icon(
                      open == 0 ? Icons.check_circle_outline : Icons.checklist),
                  title: const Text('Organisation',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      checks.isEmpty
                          ? 'Checklisten & Übersicht'
                          : open == 0
                              ? 'Alles geklärt'
                              : '$open offen',
                      style: const TextStyle(fontSize: 13)),
                  children: [
                    for (final c in ordered)
                      ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(c['ready'] == true
                              ? Icons.check_circle_outline
                              : Icons.pending_actions),
                          title: Text(c['title'] as String),
                          subtitle: Text(c['detail'] as String),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go((c['route'] as String)
                                  .startsWith('/operations')
                              ? '/trainer${c['route']}'
                              : roleCorrectPushActionRoute(c['route'] as String,
                                  isTrainer: true))),
                    if (objects(data['minutes']).isNotEmpty)
                      ExpansionTile(
                        key: PageStorageKey('match-minutes-$eventId'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Einsatzzeiten vergleichen'),
                        children: [
                          const Text(
                              'Geplante Minuten sind ein Vorschlag. Erfasste Minuten stammen aus der Spielstatistik.'),
                          for (final m in objects(data['minutes']))
                            ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(m['name'] as String),
                                subtitle: Text(
                                    'Geplant: ${m['planned'] ?? 'offen'} Min. · Erfasst: ${m['actual'] ?? 'noch nicht erfasst'}${m['actual'] == null ? '' : ' Min.'}')),
                        ],
                      ),
                    if (data['canCreateChecklist'] == true)
                      OutlinedButton.icon(
                          icon: const Icon(Icons.checklist),
                          label: const Text('Checkliste anlegen'),
                          onPressed: () async {
                            if (await talentsForm(context,
                                title: 'Spieltagscheckliste',
                                initial: {},
                                fields: (_, __) => [
                                      const Text(
                                          'Die Vorlage wird passend für Heimspiel, Auswärtsspiel oder Turnier angelegt. Du kannst sie unter Teamaufgaben weiterverwenden und bearbeiten.')
                                    ],
                                save: (_) async {
                                  await ref
                                      .read(talentsRepositoryProvider)
                                      .save('/matches/$eventId/checklist', {});
                                })) {
                              ref.invalidate(matchReadinessProvider(eventId));
                            }
                          }),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Spieltagsübersicht'),
                          onPressed: () => showTalentsReport(
                              context,
                              ref.read(talentsRepositoryProvider),
                              'Spieltagsübersicht',
                              data['briefing'] as String)),
                      TextButton(
                          onPressed: () => context.go(
                              '/trainer/operations?teamId=${data['teamId']}'),
                          child: const Text('Checklisten & Dienste')),
                      TextButton(
                          onPressed: () => context.go('/spielplus-browser'),
                          child: const Text('SpielPLUS öffnen')),
                      if (Uri.tryParse(data['sourceUrl']?.toString() ?? '')
                              ?.scheme ==
                          'https')
                        TextButton(
                            onPressed: () => launchUrl(
                                Uri.parse(data['sourceUrl'] as String),
                                mode: LaunchMode.externalApplication),
                            child: const Text('BFV-Quelle')),
                    ]),
                  ]),
            );
          });
}
