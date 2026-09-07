import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

class PollsPage extends ConsumerStatefulWidget {
  const PollsPage({super.key, required this.options});
  final Json options;
  @override
  ConsumerState<PollsPage> createState() => _PollsPageState();
}

class _PollsPageState extends ConsumerState<PollsPage> {
  late Future<dynamic> _data;
  bool _archive = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref.read(talentsRepositoryProvider).get('/polls');
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  Future<void> _create() async {
    final teams = objects(widget.options['teams']);
    if (await talentsForm(context,
        title: 'Neue Umfrage',
        initial: {
          'teamIds': teams.isEmpty ? <String>[] : [teams.first['id']],
          'unitType': 'FAMILY',
          'resultsVisibility': 'AFTER_CLOSE',
          'multiple': false,
          'endsOn': dateString(DateTime.now().add(const Duration(days: 7))),
        },
        fields: (v, set) => [
              textInput(v, set, 'question', 'Frage'),
              textInput(
                  v, set, 'answers', 'Antworten · eine Möglichkeit je Zeile',
                  lines: 4),
              multipleInput(v, set, 'teamIds', 'Mannschaften', {
                for (final t in teams) t['id'] as String: t['name'] as String
              }),
              choiceInput(v, set, 'unitType', 'Eine Stimme je',
                  {'FAMILY': 'Familie', 'CHILD': 'Kind', 'PERSON': 'Person'}),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mehrere Antworten auswählbar'),
                  value: v['multiple'] == true,
                  onChanged: (b) => set('multiple', b)),
              dayInput(context, v, set, 'endsOn', 'Frist bis 23:59 Uhr'),
              choiceInput(
                  v, set, 'resultsVisibility', 'Ergebnisse für Teilnehmende', {
                'AFTER_CLOSE': 'Nach Ende der Abstimmung',
                'ALWAYS': 'Während der Abstimmung'
              }),
            ],
        save: (v) async {
          final day = DateTime.parse(v['endsOn'] as String);
          await ref.read(talentsRepositoryProvider).save('/polls', {
            ...v,
            'options': (v['answers'] as String)
                .split('\n')
                .map((a) => a.trim())
                .where((a) => a.isNotEmpty)
                .toList(),
            'endsAt': DateTime(day.year, day.month, day.day, 23, 59)
                .toUtc()
                .toIso8601String()
          });
        })) {
      _refresh();
    }
  }

  Future<void> _vote(Json poll, Json unit) async {
    final options = List<String>.from(poll['options'] as List);
    final multiple = poll['multiple'] == true;
    if (await talentsForm(context,
        title: poll['question'] as String,
        initial: {
          'choices': (unit['choices'] as List).map((i) => '$i').toList(),
          'choice': (unit['choices'] as List).isEmpty
              ? null
              : '${(unit['choices'] as List).first}',
        },
        fields: (v, set) => [
              Text('Stimme für: ${unit['label']}'),
              multiple
                  ? multipleInput(v, set, 'choices', 'Antworten auswählen', {
                      for (var i = 0; i < options.length; i++) '$i': options[i]
                    })
                  : choiceInput(v, set, 'choice', 'Deine Antwort', {
                      for (var i = 0; i < options.length; i++) '$i': options[i]
                    }),
            ],
        saveLabel: 'Antwort speichern',
        save: (v) async {
          await ref.read(talentsRepositoryProvider).save(
              '/polls/${poll['id']}/vote',
              {
                'unitId': unit['id'],
                'choices': multiple
                    ? (v['choices'] as List)
                        .map((i) => int.parse('$i'))
                        .toList()
                    : [int.parse(v['choice'] as String)]
              },
              method: 'PUT');
        })) {
      _refresh();
    }
  }

  Future<void> _manage(Json poll, String action, String label) async {
    if (await talentsForm(context,
        title: label,
        initial: {},
        fields: (_, __) => [
              Text(poll['question'] as String),
              Text(action == 'REMIND'
                  ? 'Nur Teilnehmende ohne Antwort erhalten eine Erinnerung.'
                  : 'Die bisherigen Antworten bleiben gespeichert.')
            ],
        saveLabel: label,
        save: (_) async {
          await ref
              .read(talentsRepositoryProvider)
              .save('/polls/${poll['id']}/manage', {'action': action});
        })) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.options['capabilities']['polls'] == true)
          FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Neue Umfrage')),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Archiv anzeigen'),
            value: _archive,
            onChanged: (value) => setState(() => _archive = value)),
        TalentsAsync(
            future: _data,
            onRetry: _refresh,
            builder: (data) {
              final polls = objects(data)
                  .where((p) => _archive || p['archivedAt'] == null)
                  .toList();
              if (polls.isEmpty) {
                return const TalentsEmpty(
                    text: 'Aktuell gibt es keine Umfragen.');
              }
              return Column(
                  children: polls.map((p) {
                final options = List<String>.from(p['options'] as List);
                final results = p['results'] as List?;
                return TalentsCard(
                    title: p['question'] as String,
                    subtitle:
                        '${p['closed'] == true ? 'Abgeschlossen' : 'Antworten bis ${showDate(p['endsAt'])}'} · ${p['responseCount']} von ${p['totalUnits']} Antworten',
                    children: [
                      if (results != null)
                        for (var i = 0; i < options.length; i++)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${options[i]} · ${results[i]} Stimmen'),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                        value: (p['responseCount'] as num) == 0
                                            ? 0
                                            : ((results[i] as num) /
                                                    (p['responseCount'] as num))
                                                .clamp(0, 1)
                                                .toDouble(),
                                        minHeight: 6),
                                  ]))
                      else
                        const Text(
                            'Die Ergebnisse werden nach Abschluss sichtbar.'),
                      for (final unit in objects(p['myUnits']))
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(unit['label'] as String),
                            subtitle: Text((unit['choices'] as List).isEmpty
                                ? 'Deine Antwort ist noch offen'
                                : (unit['choices'] as List)
                                    .map((i) => options[i as int])
                                    .join(', ')),
                            trailing: p['closed'] == true
                                ? null
                                : const Icon(Icons.edit_outlined),
                            onTap: p['closed'] == true
                                ? null
                                : () => _vote(p, unit)),
                      if (p['canManage'] == true)
                        Wrap(spacing: 8, children: [
                          if (p['closed'] != true) ...[
                            TextButton(
                                onPressed: () => _manage(
                                    p, 'REMIND', 'Offene Antworten erinnern'),
                                child: const Text('Erinnern')),
                            TextButton(
                                onPressed: () =>
                                    _manage(p, 'CLOSE', 'Umfrage abschließen'),
                                child: const Text('Abschließen')),
                          ],
                          if (p['archivedAt'] == null)
                            TextButton(
                                onPressed: () => _manage(
                                    p, 'ARCHIVE', 'Umfrage archivieren'),
                                child: const Text('Archivieren')),
                        ]),
                    ]);
              }).toList());
            }),
      ]);
}
