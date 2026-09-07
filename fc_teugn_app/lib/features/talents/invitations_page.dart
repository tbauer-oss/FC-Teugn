import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../auth/auth_controller.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

const invitationRoles = {
  'PARENT': 'Elternteil',
  'PLAYER': 'Spieler',
  'COACH': 'Trainer',
  'ASSISTANT_COACH': 'Co-Trainer',
  'TEAM_MANAGER': 'Mannschaftsbetreuung'
};

class InvitationsPage extends ConsumerStatefulWidget {
  const InvitationsPage({super.key, required this.options});
  final Json options;
  @override
  ConsumerState<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends ConsumerState<InvitationsPage> {
  late Future<dynamic> _data;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref.read(talentsRepositoryProvider).get('/invitations');
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  Future<void> _create() async {
    final teams = objects(widget.options['teams']);
    Json? created;
    final saved = await talentsForm(context,
        title: 'Zur Mannschaft einladen',
        initial: {
          'teamId': teams.firstOrNull?['id'],
          'role': 'PARENT',
          'days': '7'
        },
        fields: (v, set) => [
              choiceInput(v, set, 'teamId', 'Mannschaft', {
                for (final t in teams) t['id'] as String: t['name'] as String
              }),
              choiceInput(v, set, 'role', 'Vorgesehene Rolle', invitationRoles),
              choiceInput(v, set, 'days', 'Gültigkeit', {
                '1': 'Ein Tag',
                '7': 'Eine Woche',
                '14': 'Zwei Wochen',
                '30': '30 Tage'
              }),
              const Text(
                  'Der Zugang wird nach Annahme geprüft. Kinderzuordnungen werden weiterhin gesondert freigegeben.')
            ],
        saveLabel: 'Einladung erstellen',
        save: (v) async {
          created = Map<String, dynamic>.from(await ref
              .read(talentsRepositoryProvider)
              .save('/invitations',
                  {...v, 'days': int.parse(v['days'] as String)}) as Map);
        });
    if (!saved || !mounted || created == null) return;
    _refresh();
    final url = created!['url'] as String;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Einladung teilen'),
                scrollable: true,
                content: SizedBox(
                    width: 350,
                    child: Column(children: [
                      Semantics(
                          label: 'QR-Code für die Mannschaftseinladung',
                          child: QrImageView(
                              data: url,
                              size: 230,
                              backgroundColor: Colors.white)),
                      Text('Gültig bis ${showDate(created!['expiresAt'])}'),
                      const SizedBox(height: 12),
                      SelectableText(url),
                      const SizedBox(height: 12),
                      const Text(
                          'Bewahre den Link jetzt auf. Er wird später aus Sicherheitsgründen nicht erneut angezeigt.'),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Einladungslink kopiert.')));
                        }
                      },
                      child: const Text('Link kopieren')),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fertig'))
                ]));
  }

  Future<void> _action(
      String path, Json body, String label, String explanation) async {
    if (await talentsForm(context,
        title: label,
        initial: {},
        fields: (_, __) => [Text(explanation)],
        saveLabel: label,
        save: (_) async {
          await ref.read(talentsRepositoryProvider).save(path, body);
        })) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Einladung erstellen')),
        const SizedBox(height: 12),
        TalentsAsync(
            future: _data,
            onRetry: _refresh,
            builder: (data) => Column(children: [
                  for (final p in objects(data['pending']))
                    TalentsCard(
                        title: '${p['user']['name']} · ${p['team']['name']}',
                        subtitle:
                            'Zugang angefragt · ${invitationRoles[p['role']] ?? p['role']}',
                        children: [
                          if (p['user']['status'] != 'APPROVED')
                            const Text(
                                'Zuerst den App-Zugang in der Mitgliederverwaltung freigeben.'),
                          Wrap(spacing: 8, children: [
                            if (p['user']['status'] == 'APPROVED')
                              TextButton(
                                  onPressed: () => _action(
                                      '/invitations/claims/${p['id']}/review',
                                      {'status': 'APPROVED'},
                                      'Zugang freigeben',
                                      'Die geprüfte Person erhält die angefragte Mannschaftsrolle.'),
                                  child: const Text('Freigeben')),
                            TextButton(
                                onPressed: () => _action(
                                    '/invitations/claims/${p['id']}/review',
                                    {'status': 'REJECTED'},
                                    'Anfrage ablehnen',
                                    'Die Person erhält keinen Zugang zu dieser Mannschaft.'),
                                child: const Text('Ablehnen')),
                          ]),
                        ]),
                  for (final i in objects(data['invitations']))
                    TalentsCard(
                        title:
                            '${i['team']['name']} · ${invitationRoles[i['role']] ?? i['role']}',
                        subtitle:
                            '${i['revokedAt'] != null ? 'Widerrufen' : 'Gültig bis ${showDate(i['expiresAt'])}'} · ${objects(i['claims']).length} angenommen',
                        children: [
                          if (i['revokedAt'] == null &&
                              DateTime.parse(i['expiresAt'] as String)
                                  .isAfter(DateTime.now()))
                            Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                    onPressed: () => _action(
                                        '/invitations/${i['id']}/revoke',
                                        {},
                                        'Einladung widerrufen',
                                        'Der Link wird ungültig. Bereits freigegebene Zugänge bleiben erhalten.'),
                                    child: const Text('Widerrufen'))),
                        ]),
                  if (objects(data['invitations']).isEmpty)
                    const TalentsEmpty(
                        text: 'Noch keine Einladungen erstellt.'),
                ])),
      ]);
}

class JoinTeamPage extends ConsumerStatefulWidget {
  const JoinTeamPage({super.key, required this.token});
  final String token;
  @override
  ConsumerState<JoinTeamPage> createState() => _JoinTeamPageState();
}

class _JoinTeamPageState extends ConsumerState<JoinTeamPage> {
  late Future<dynamic> _data;
  String? _status;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref
        .read(talentsRepositoryProvider)
        .get('/invitation-preview', {'token': widget.token});
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
        appBar: AppBar(title: const Text('Deine Mannschaftseinladung')),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: TalentsAsync(
                            future: _data,
                            onRetry: () => setState(_load),
                            builder: (data) => TalentsCard(
                                    title: 'Willkommen bei ${data['teamName']}',
                                    subtitle:
                                        '${invitationRoles[data['role']] ?? data['role']} · Gültig bis ${showDate(data['expiresAt'])}',
                                    children: [
                                      if (_status != null) ...[
                                        Text(_status == 'APPROVED'
                                            ? 'Du hast bereits Zugang zu dieser Mannschaft.'
                                            : 'Deine Anfrage wurde gespeichert. Das Trainerteam prüft deinen Zugang und die Kinderzuordnung.'),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                            onPressed: () => context.go(
                                                user!.isTrainer
                                                    ? '/trainer'
                                                    : '/parent'),
                                            child: const Text('Zur App')),
                                      ] else if (user == null) ...[
                                        const Text(
                                            'Du hast schon ein Konto? Melde dich damit an. So bleiben alle Kinder und Mannschaften in einem Zugang.'),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                            onPressed: () => context.go(
                                                '/login?invite=${widget.token}'),
                                            child: const Text(
                                                'Mit bestehendem Konto anmelden')),
                                        TextButton(
                                            onPressed: () => context.go(
                                                '/register?invite=${widget.token}'),
                                            child: const Text(
                                                'App-Zugang beantragen')),
                                      ] else ...[
                                        Text(
                                            'Angemeldet als ${user.name}. Die Mannschaftsrolle wird nach deiner Annahme geprüft.'),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                            onPressed: () async {
                                              if (await talentsForm(context,
                                                  title: 'Einladung annehmen',
                                                  initial: {},
                                                  fields: (_, __) => [
                                                        Text(
                                                            'Zugang zu ${data['teamName']} anfragen.')
                                                      ],
                                                  saveLabel: 'Zugang anfragen',
                                                  save: (_) async {
                                                    final result = await ref
                                                        .read(
                                                            talentsRepositoryProvider)
                                                        .save(
                                                            '/invitations/claim',
                                                            {
                                                          'token': widget.token
                                                        });
                                                    if (mounted) {
                                                      setState(() => _status =
                                                          result['status']
                                                              as String);
                                                    }
                                                  })) {}
                                            },
                                            child: const Text(
                                                'Einladung annehmen')),
                                      ],
                                      TextButton(
                                          onPressed: () => context.push(
                                              '/install?invite=${widget.token}'),
                                          child: const Text(
                                              'App installieren · Hilfe')),
                                    ])))))));
  }
}
