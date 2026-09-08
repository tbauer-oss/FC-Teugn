import 'package:flutter/material.dart';
import 'report_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'goal_development_view.dart';
import '../auth/auth_controller.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key, required this.options});
  final Json options;
  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  late Future<dynamic> _data;
  bool _history = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref.read(talentsRepositoryProvider).get('/goals');
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  Future<void> _edit([Json? goal]) async {
    final players = objects(widget.options['players']);
    if (players.isEmpty) return;
    if (await talentsForm(context,
        title: goal == null ? 'Neues Lernziel' : 'Lernziel bearbeiten',
        initial: {
          'playerId': players.first['id'],
          'responsibleUserId': ref.read(authProvider).user?.id,
          'startsOn': dateString(DateTime.now()),
          'endsOn': dateString(DateTime.now().add(const Duration(days: 42))),
          'visibility': 'STAFF_ONLY',
          'status': 'ACTIVE',
          'exerciseIds': <String>[],
          'trainingPlanIds': <String>[],
          ...?goal,
        }, fields: (v, set) {
      final team =
          players.where((p) => p['id'] == v['playerId']).firstOrNull?['teamId'];
      final members = objects(widget.options['members']).where((m) =>
          [
            'SUPER_ADMIN',
            'CLUB_ADMIN',
            'YOUTH_DIRECTOR',
            'TRAINER_ADMIN',
            'COACH',
            'TRAINER',
            'ASSISTANT_COACH'
          ].contains(m['role']) &&
          (m['teamId'] == team ||
              objects(m['memberships']).any((a) => a['teamId'] == team)));
      return [
        if (goal == null)
          choiceInput(v, (key, value) {
            set(key, value);
            set('exerciseIds', <String>[]);
            set('trainingPlanIds', <String>[]);
          }, 'playerId', 'Spieler',
              {for (final p in players) p['id'] as String: personName(p)}),
        textInput(v, set, 'title', 'Was möchten wir erreichen?'),
        textInput(v, set, 'description', 'Woran erkennen wir den Fortschritt?',
            lines: 3),
        choiceInput(v, set, 'responsibleUserId', 'Verantwortlicher Trainer',
            {for (final m in members) m['id'] as String: personName(m)}),
        dayInput(context, v, set, 'startsOn', 'Beginn'),
        dayInput(context, v, set, 'endsOn', 'Zieltermin'),
        choiceInput(v, set, 'visibility', 'Sichtbarkeit',
            {'STAFF_ONLY': 'Trainerteam', 'FAMILY': 'Trainerteam und Familie'}),
        choiceInput(v, set, 'status', 'Stand', {
          'ACTIVE': 'Aktiv',
          'COMPLETED': 'Abgeschlossen',
          'ARCHIVED': 'Archiviert'
        }),
        multipleInput(v, set, 'exerciseIds', 'Passende Übungen', {
          for (final e in objects(widget.options['exercises'])
              .where((e) => e['teamId'] == team))
            e['id'] as String: e['title'] as String
        }),
        multipleInput(v, set, 'trainingPlanIds', 'Trainingspläne', {
          for (final p in objects(widget.options['plans'])
              .where((p) => p['event']['teamId'] == team))
            p['id'] as String:
                '${p['event']['title']} · ${showDate(p['event']['startAt'])}'
        }),
      ];
    }, save: (v) async {
      await ref.read(talentsRepositoryProvider).save(
          '/goals${goal == null ? '' : '/${goal['id']}'}', v,
          method: goal == null ? 'POST' : 'PUT');
    })) {
      _refresh();
    }
  }

  Future<void> _observe(Json goal) async {
    if (await talentsForm(context,
        title: 'Beobachtung festhalten',
        initial: {
          'progress':
              objects(goal['observations']).firstOrNull?['progress'] ?? 0
        },
        fields: (v, set) => [
              Text(goal['title'] as String),
              textInput(v, set, 'note', 'Konkrete Beobachtung', lines: 3),
              Text('Fortschritt: ${v['progress']} %'),
              Slider(
                  value: (v['progress'] as num).toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${v['progress']} %',
                  onChanged: (value) => set('progress', value.round()))
            ],
        save: (v) async {
          await ref
              .read(talentsRepositoryProvider)
              .save('/goals/${goal['id']}/observations', v);
        })) {
      _refresh();
    }
  }

  Future<void> _review(List<Json> goals) async {
    final report = goals
        .map((g) =>
            '${personName(g['player'] as Json)} – ${g['title']}\n${showDate(g['startsOn'])} bis ${showDate(g['endsOn'])}\n${g['description']}\n${objects(g['observations']).map((o) => '${showDate(o['createdAt'])}: ${o['note']} (${o['progress']} %)').join('\n')}')
        .join('\n\n');
    if (mounted) {
      await showTalentsReport(context, ref.read(talentsRepositoryProvider),
          'Zielübersicht', report);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.options['capabilities']['goals'] == true)
          FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Lernziel anlegen')),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Abgeschlossene Ziele anzeigen'),
            value: _history,
            onChanged: (v) => setState(() => _history = v)),
        TalentsAsync(
            future: _data,
            onRetry: _refresh,
            builder: (data) {
              final goals = objects(data)
                  .where((g) => _history || g['status'] == 'ACTIVE')
                  .toList();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (goals.isEmpty)
                      const TalentsEmpty(
                          text:
                              'Hier erscheinen die für dich freigegebenen Lernziele. Ein bis drei konkrete Ziele helfen, Fortschritt sichtbar zu machen.'),
                    if (goals.isNotEmpty)
                      OutlinedButton.icon(
                          onPressed: () => _review(goals),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Zielübersicht')),
                    for (final g in goals)
                      TalentsCard(
                          title:
                              '${personName(g['player'] as Json)} · ${g['title']}',
                          subtitle:
                              '${showDate(g['startsOn'])} – ${showDate(g['endsOn'])} · ${g['visibility'] == 'FAMILY' ? 'Mit Familie geteilt' : 'Nur Trainerteam'}${g['status'] == 'ACTIVE' ? '' : ' · Abgeschlossen'}',
                          children: [
                            Text(g['description'] as String),
                            const SizedBox(height: 12),
                            for (final o in objects(g['observations']))
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(o['note'] as String),
                                  subtitle: Text(
                                      '${showDate(o['createdAt'])} · ${o['progress']} %')),
                            Wrap(spacing: 8, children: [
                              if (g['canManage'] == true) ...[
                                TextButton(
                                    onPressed: () => _edit(g),
                                    child: const Text('Bearbeiten')),
                                if (g['status'] == 'ACTIVE')
                                  TextButton(
                                      onPressed: () => _observe(g),
                                      child: const Text('Beobachtung'))
                              ],
                              TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => GoalDevelopmentView(
                                              goalId: g['id'] as String))),
                                  child: const Text('Verlauf & Statistik')),
                            ]),
                          ]),
                  ]);
            }),
      ]);
}
