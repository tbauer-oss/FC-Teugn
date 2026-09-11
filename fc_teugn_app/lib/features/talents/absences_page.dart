import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

class AbsencesPage extends ConsumerStatefulWidget {
  const AbsencesPage({super.key, required this.options});
  final Json options;
  @override
  ConsumerState<AbsencesPage> createState() => _AbsencesPageState();
}

class _AbsencesPageState extends ConsumerState<AbsencesPage> {
  late Future<dynamic> _data;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref.read(talentsRepositoryProvider).get('/absences');
  }

  void _refresh() {
    if (!mounted) return;
    setState(_load);
    ref.read(manualDataRefreshProvider.notifier).state++;
  }

  Future<void> _edit([Json? absence]) async {
    final players = objects(widget.options['players']);
    final now = dateString(DateTime.now());
    if (await talentsForm(context,
        title: absence == null
            ? 'Abwesenheit eintragen'
            : 'Abwesenheit bearbeiten',
        initial: {
          'playerId': players.firstOrNull?['id'],
          'startsOn': now,
          'endsOn': now,
          'eventTypes': ['TRAINING', 'MATCH'],
          'teamIds': <String>[],
          'weekdays': <String>[],
          ...?absence,
          if (absence != null)
            'weekdays': (absence['weekdays'] as List).map((v) => '$v').toList()
        },
        fields: (v, set) => [
              const Text(
                  'Wichtig: Bereits geschlossene Spielkader bleiben unverändert. Bitte für diese Spiele das Trainerteam direkt kontaktieren.'),
              if (absence == null)
                choiceInput(v, (key, value) {
                  set(key, value);
                  set('teamIds', <String>[]);
                }, 'playerId', 'Kind / Spieler', {
                  for (final p in players) p['id'] as String: personName(p)
                }),
              dayInput(context, v, set, 'startsOn', 'Von'),
              dayInput(context, v, set, 'endsOn', 'Bis einschließlich'),
              multipleInput(v, set, 'eventTypes', 'Gilt für',
                  {'TRAINING': 'Training', 'MATCH': 'Spiele'}),
              multipleInput(v, set, 'weekdays',
                  'Wiederholung · ohne Auswahl an allen Tagen', {
                '1': 'Mo',
                '2': 'Di',
                '3': 'Mi',
                '4': 'Do',
                '5': 'Fr',
                '6': 'Sa',
                '0': 'So'
              }),
              multipleInput(v, set, 'teamIds',
                  'Mannschaften · ohne Auswahl alle Zuordnungen des Kindes', {
                for (final t in objects(widget.options['teams']).where((t) {
                  final p = players
                      .where((p) => p['id'] == v['playerId'])
                      .firstOrNull;
                  return p?['teamId'] == t['id'] ||
                      objects(p?['seasonAssignments'])
                          .any((a) => a['teamId'] == t['id']);
                }))
                  t['id'] as String: t['name'] as String
              }),
              textInput(
                  v, set, 'reason', 'Grund (optional, nur für Berechtigte)',
                  required: false, lines: 2),
              const Text(
                  'Eine spätere bewusste Einzelrückmeldung gilt als Ausnahme. Neue Termine werden automatisch berücksichtigt.'),
            ],
        save: (v) async {
          await ref.read(talentsRepositoryProvider).save(
              absence == null ? '/absences' : '/absences/${absence['id']}',
              {
                ...v,
                'weekdays':
                    (v['weekdays'] as List).map((d) => int.parse('$d')).toList()
              },
              method: absence == null ? 'POST' : 'PUT');
        })) {
      _refresh();
    }
  }

  Future<void> _end(Json absence) async {
    if (await talentsForm(context,
        title: 'Abwesenheit jetzt beenden',
        initial: {},
        fields: (_, __) => [
              const Text(
                  'Künftige automatische Absagen dieser Abwesenheit werden aufgehoben. Frühere Rückmeldungen und bereits geschlossene Spielkader bleiben erhalten. Änderungen daran bitte mit dem Trainerteam klären.')
            ],
        saveLabel: 'Abwesenheit beenden',
        save: (_) async {
          await ref
              .read(talentsRepositoryProvider)
              .save('/absences/${absence['id']}/end', {});
        })) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
            onPressed: objects(widget.options['players']).isEmpty
                ? null
                : () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Abwesenheit eintragen')),
        const SizedBox(height: 16),
        TalentsAsync(
            future: _data,
            onRetry: _refresh,
            builder: (data) {
              final players = objects(data['players']);
              final entries = players
                  .expand((p) => objects(p['absences'])
                      .map((a) => {...a, 'playerName': personName(p)}))
                  .toList();
              if (entries.isEmpty) {
                return const TalentsEmpty(
                    text:
                        'Noch keine Abwesenheiten. Urlaub oder regelmäßig freie Tage lassen sich hier einmalig für alle passenden Termine eintragen.');
              }
              return Column(
                  children: entries
                      .map((a) => TalentsCard(
                              title: a['playerName'] as String,
                              subtitle:
                                  '${showDate(a['startsOn'])} – ${showDate(a['endsOn'])}${a['endedAt'] == null ? '' : ' · beendet'}',
                              children: [
                                Text((a['eventTypes'] as List)
                                            .contains('TRAINING') &&
                                        (a['eventTypes'] as List)
                                            .contains('MATCH')
                                    ? 'Training und Spiele'
                                    : (a['eventTypes'] as List)
                                            .contains('MATCH')
                                        ? 'Spiele'
                                        : 'Training'),
                                if ((a['weekdays'] as List).isNotEmpty)
                                  Text(
                                      'Wöchentlich: ${(a['weekdays'] as List).map((d) => [
                                            'So',
                                            'Mo',
                                            'Di',
                                            'Mi',
                                            'Do',
                                            'Fr',
                                            'Sa'
                                          ][d as int]).join(', ')}'),
                                if (a['reason'] != null)
                                  Text(a['reason'] as String),
                                if (a['endedAt'] == null)
                                  Wrap(spacing: 8, children: [
                                    TextButton.icon(
                                        onPressed: () => _edit(a),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Bearbeiten')),
                                    TextButton(
                                        onPressed: () => _end(a),
                                        child: const Text('Vorzeitig beenden')),
                                  ]),
                              ]))
                      .toList());
            }),
      ]);
}
