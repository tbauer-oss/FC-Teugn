import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../talents/assistant_page.dart';
import 'parent_home_models.dart';
import 'parent_home_widgets.dart';

class ParentFamilyPage extends ConsumerWidget {
  const ParentFamilyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(parentDashboardSummaryProvider);
    final responses = ref.watch(personalResponsesProvider);
    final consents =
        ref.watch(parentConsentAttentionProvider).valueOrNull ?? [];
    final tasks = ref.watch(authProvider).user == null
        ? null
        : ref.watch(familyTaskListProvider).valueOrNull;
    final players = summary.valueOrNull?.players ?? <PlayerModel>[];
    final visits = buildParentVisits(
        players: players,
        events: summary.valueOrNull?.events ?? [],
        responses: responses.valueOrNull ?? [],
        now: DateTime.now());
    return ParentPageFrame(
        title: 'Deine Familie',
        subtitle: 'Wer muss wann wohin?',
        children: [
          if ((summary.isLoading && !summary.hasValue) ||
              (responses.isLoading && !responses.hasValue))
            const LinearProgressIndicator(minHeight: 2),
          if (summary.hasError)
            ParentLinkRow(
                icon: Icons.refresh,
                title: 'Familienübersicht erneut laden',
                onTap: () => ref.invalidate(parentDashboardSummaryProvider)),
          if (responses.hasError)
            ParentLinkRow(
                icon: Icons.refresh,
                title: 'Rückmeldungen erneut laden',
                onTap: () => ref.invalidate(personalResponsesProvider)),
          for (var index = 0; index < players.length; index++) ...[
            _ChildAgenda(
                player: players[index],
                color: index.isEven ? parentTrainingColor : parentMatchColor,
                visits: visits
                    .where((v) => v.player.id == players[index].id)
                    .toList()),
            const SizedBox(height: 22),
          ],
          if (!summary.isLoading && players.isEmpty && !summary.hasError)
            const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Text(
                    'Noch kein Kind zugeordnet. Bitte kontaktiere das Trainerteam.')),
          ParentLinkRow(
              key: const ValueKey('family-absence-action'),
              icon: Icons.event_busy_outlined,
              title: 'Abwesenheit eintragen',
              onTap: () => context.go('/parent/talents/absences')),
          ParentLinkRow(
              key: const ValueKey('family-contact-action'),
              icon: Icons.mail_outline,
              title: 'Trainer kontaktieren',
              onTap: () => context.go('/parent/messages?section=contact')),
          for (final consent in consents)
            ParentLinkRow(
                icon: Icons.verified_user_outlined,
                title: 'Einwilligung für ${consent.playerName} prüfen',
                onTap: () => context.go(
                    '/parent/players/${Uri.encodeComponent(consent.playerId)}?consents=1')),
          if (tasks != null && tasks.isNotEmpty)
            ParentLinkRow(
                icon: Icons.task_alt,
                title:
                    '${tasks.length} offene ${tasks.length == 1 ? 'Aufgabe' : 'Aufgaben'}',
                onTap: () => context.go('/parent/talents/assistant')),
          const SizedBox(height: 8),
          ExpansionTile(
              key: const ValueKey('family-more-functions'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Weitere Familienfunktionen',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              children: [
                for (final item in const [
                  (
                    'Alle Rückmeldungen & Regeltrainings',
                    '/parent/responses',
                    Icons.checklist
                  ),
                  (
                    'Kinderprofile & Dokumente',
                    '/parent/players',
                    Icons.person_outline
                  ),
                  (
                    'Aufgaben & Dienste',
                    '/parent/talents/assistant',
                    Icons.task_alt
                  ),
                  (
                    'Teamaufgaben & Ausrüstung',
                    '/parent/operations',
                    Icons.inventory_2_outlined
                  ),
                  ('Umfragen', '/parent/talents/polls', Icons.poll_outlined),
                  ('Lernziele', '/parent/talents/goals', Icons.flag_outlined),
                  (
                    'Entwicklung & Statistiken',
                    '/parent/statistics',
                    Icons.query_stats
                  ),
                  (
                    'Tabelle & Ergebnisse',
                    '/parent/bfv',
                    Icons.emoji_events_outlined
                  ),
                  (
                    'Vergangene Spiele',
                    '/parent/matches/history',
                    Icons.history
                  ),
                  (
                    'Datenschutz & Einwilligungen',
                    '/parent/privacy',
                    Icons.shield_outlined
                  ),
                  ('Hilfe & Anleitungen', '/parent/help', Icons.help_outline),
                  (
                    'Technischer Support',
                    '/parent/support',
                    Icons.support_agent
                  ),
                ])
                  ParentLinkRow(
                      icon: item.$3,
                      title: item.$1,
                      onTap: () => context.go(item.$2)),
              ]),
        ]);
  }
}

class _ChildAgenda extends StatelessWidget {
  const _ChildAgenda(
      {required this.player, required this.visits, required this.color});
  final PlayerModel player;
  final List<ParentVisit> visits;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final open = visits.where((v) => v.response?.isOpen == true).length;
    final next = [
      ...nextParentVisits(visits, match: false),
      ...nextParentVisits(visits, match: true)
    ];
    void profile() =>
        context.go('/parent/players/${Uri.encodeComponent(player.id)}');
    return Column(
        key: ValueKey('family-child-${player.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: .14),
                foregroundColor: color,
                child: Text(player.displayName.characters.firstOrNull ?? '?',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700))),
            const SizedBox(width: 10),
            Expanded(
                child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                  InkWell(
                      onTap: profile,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                              '${player.displayName} · ${player.teamCode}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)))),
                  if (open > 0)
                    InkWell(
                        onTap: () => context.go(Uri(
                                path: '/parent/responses',
                                queryParameters: {
                                  'playerId': player.id,
                                  'open': '1'
                                }).toString()),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                                '● $open ${open == 1 ? 'Antwort' : 'Antworten'} offen',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFFB77700))))),
                ])),
            IconButton(
                onPressed: profile,
                tooltip: '${player.displayName}: Profil öffnen',
                icon: const Icon(Icons.chevron_right, size: 20)),
          ]),
          const SizedBox(height: 10),
          for (final visit in next) ParentFamilyEventRow(visit: visit),
          if (next.isEmpty)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Aktuell keine nächsten Trainings oder Spiele.',
                    style: TextStyle(
                        fontSize: 14, color: context.appColors.textMuted))),
        ]);
  }
}
