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
          error: (e, _) => TalentsEmpty(
              text: talentsError(e),
              action: TextButton(
                  onPressed: () =>
                      ref.invalidate(matchReadinessProvider(eventId)),
                  child: const Text('Organisation erneut laden'))),
          data: (data) => TalentsCard(
                  title: 'Bereit für den Spieltag?',
                  subtitle:
                      'Sportlicher Plan und Organisation gehören zusammen.',
                  children: [
                    for (final c in objects(data['checks']))
                      ListTile(
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
                    const Text(
                        'Der Autopilot berücksichtigt Verfügbarkeit, Positionen und bisherige Einsatzzeiten. Die geplanten Minuten sind ein Vorschlag; tatsächliche Minuten stammen aus den erfassten Spielstatistiken.'),
                    for (final m in objects(data['minutes']))
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(m['name'] as String),
                          subtitle: Text(
                              'Geplant: ${m['planned'] ?? 'offen'} Min. · Tatsächlich: ${m['actual'] ?? 'noch nicht erfasst'}${m['actual'] == null ? '' : ' Min.'}')),
                    if (data['canCreateChecklist'] == true)
                      OutlinedButton.icon(
                          icon: const Icon(Icons.checklist),
                          label: const Text(
                              'Passende Spieltagscheckliste anlegen'),
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
                  ]));
}
