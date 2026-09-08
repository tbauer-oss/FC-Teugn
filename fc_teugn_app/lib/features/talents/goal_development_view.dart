import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import 'report_dialog.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

final goalDevelopmentProvider =
    FutureProvider.autoDispose.family<Json, String>((ref, id) {
  ref.watch(manualDataRefreshProvider);
  ref.watch(talentsDataVersionProvider);
  return ref.watch(talentsRepositoryProvider).object('/goals/$id/development');
});

String developmentSource(String? kind) => switch (kind) {
      'GOAL' => 'Lernziel',
      'NOTE' => 'Entwicklungsnotiz',
      'MATCH' => 'Spielstatistik',
      'TRAINING' => 'Training',
      _ => 'Beobachtung',
    };

String developmentStatistics(Json? stats) {
  if (stats == null) return 'Statistik für diesen Zugriff nicht freigegeben.';
  if (stats['recordedMatches'] == 0 && stats['recordedTrainings'] == 0) {
    return 'Für diesen Zeitraum sind noch keine abgeschlossenen Spiele oder Trainingsanwesenheiten erfasst.';
  }
  return '${stats['appearances']} ${stats['appearances'] == 1 ? 'Einsatz' : 'Einsätze'} · ${stats['minutes']} Minuten · '
      '${stats['goals']} ${stats['goals'] == 1 ? 'Tor' : 'Tore'} · ${stats['assists']} ${stats['assists'] == 1 ? 'Vorlage' : 'Vorlagen'}\n'
      'Training: ${stats['attendedTrainings']} von ${stats['recordedTrainings']} ${stats['recordedTrainings'] == 1 ? 'erfasstem Termin' : 'erfassten Terminen'} teilgenommen';
}

String goalDevelopmentReport(Json data) {
  final goal = data['goal'] as Json;
  return [
    '${personName(goal['player'] as Json)} · ${goal['title']}',
    '${showDate(data['from'])} bis ${showDate(data['to'])}',
    goal['description'] as String,
    '',
    developmentStatistics(data['statistics'] as Json?),
    'Statistiken und Entwicklungsnotizen beziehen sich auf den Zielzeitraum. Zielbeobachtungen zeigen den gesamten Zielverlauf.',
    '',
    for (final item in objects(data['timeline']))
      '${showDate(item['at'])} · ${developmentSource(item['kind'] as String?)}'
          '${item['progress'] == null ? '' : ' · ${item['progress']} %'}'
          '${item['visibility'] == 'STAFF_ONLY' ? ' · Nur Trainerteam' : ''}\n'
          '${item['title']}\n${item['text']}',
  ].join('\n');
}

class GoalDevelopmentView extends ConsumerWidget {
  const GoalDevelopmentView({super.key, required this.goalId});
  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Verlauf & Statistik')),
        body: ref.watch(goalDevelopmentProvider(goalId)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => TalentsEmpty(
                  text: talentsError(e),
                  action: TextButton(
                      onPressed: () =>
                          ref.invalidate(goalDevelopmentProvider(goalId)),
                      child: const Text('Erneut laden'))),
              data: (data) {
                final goal = data['goal'] as Json;
                final timeline = objects(data['timeline']);
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(goalDevelopmentProvider(goalId));
                    await ref.read(goalDevelopmentProvider(goalId).future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                          '${personName(goal['player'] as Json)} · ${goal['title']}',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                          '${showDate(data['from'])} – ${showDate(data['to'])}'),
                      const SizedBox(height: 8),
                      Text(goal['description'] as String),
                      const SizedBox(height: 16),
                      TalentsCard(title: 'Im Zielzeitraum', children: [
                        Text(
                            developmentStatistics(data['statistics'] as Json?)),
                        const SizedBox(height: 8),
                        const Text(
                            'Abgeschlossene Spiele und erfasste Anwesenheiten geben Kontext. Sie bewerten das Lernziel nicht automatisch.'),
                      ]),
                      OutlinedButton.icon(
                          icon: const Icon(Icons.description_outlined),
                          label:
                              const Text('Entwicklungsrückblick exportieren'),
                          onPressed: () => showTalentsReport(
                              context,
                              ref.read(talentsRepositoryProvider),
                              'Entwicklungsrückblick',
                              goalDevelopmentReport(data))),
                      const SizedBox(height: 16),
                      Text('Gemeinsamer Verlauf',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Text(
                          'Bestehende Notizen und Statistiken im Zielzeitraum sowie alle Beobachtungen zu diesem Ziel.'),
                      if (timeline.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                                'Noch keine freigegebenen Einträge vorhanden.')),
                      for (final item in timeline)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TalentsCard(
                              title: item['title'] as String,
                              subtitle:
                                  '${showDate(item['at'])} · ${developmentSource(item['kind'] as String?)}'
                                  '${item['progress'] == null ? '' : ' · ${item['progress']} %'}'
                                  '${item['visibility'] == 'STAFF_ONLY' ? ' · Nur Trainerteam' : ''}',
                              children: [Text(item['text'] as String)],
                            )),
                    ],
                  ),
                );
              },
            ),
      );
}
