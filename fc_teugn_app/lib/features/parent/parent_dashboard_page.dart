import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import 'family_assistant_model.dart';
import 'parent_home_models.dart';
import 'parent_home_providers.dart';
import 'parent_home_widgets.dart';

class ParentDashboardPage extends ConsumerStatefulWidget {
  const ParentDashboardPage({super.key});
  @override
  ConsumerState<ParentDashboardPage> createState() =>
      _ParentDashboardPageState();
}

class _ParentDashboardPageState extends ConsumerState<ParentDashboardPage> {
  String? _selectedChild;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final summaryAsync = ref.watch(parentDashboardSummaryProvider);
    final responsesAsync = ref.watch(personalResponsesProvider);
    final matchesAsync = ref.watch(parentMatchdaysProvider);
    final consents =
        ref.watch(parentConsentAttentionProvider).valueOrNull ?? [];
    final pushReady = ref.watch(currentDevicePushReadyProvider).valueOrNull;
    final contacts = ref.watch(parentContactPreviewProvider).valueOrNull ?? [];
    final summary = summaryAsync.valueOrNull;
    final players = summary?.players ?? const <PlayerModel>[];
    final selected =
        players.any((p) => p.id == _selectedChild) ? _selectedChild : null;
    final visiblePlayers =
        players.where((p) => selected == null || p.id == selected).toList();
    final visits = buildParentVisits(
        players: visiblePlayers,
        events: summary?.events ?? [],
        responses: responsesAsync.valueOrNull ?? [],
        now: DateTime.now());
    final open = visits.where((v) => v.response?.isOpen == true).toList();
    final training = nextParentVisits(visits, match: false);
    final match = nextParentVisits(visits, match: true);
    final unread =
        (summary?.notifications ?? []).where((n) => !n.isRead).toList();
    final loading = (summaryAsync.isLoading && !summaryAsync.hasValue) ||
        (responsesAsync.isLoading && !responsesAsync.hasValue);
    final failed = summaryAsync.hasError && !summaryAsync.hasValue;
    final firstName = user?.name.trim().split(RegExp(r'\s+')).firstOrNull;
    return ParentPageFrame(
      title: firstName == null || firstName.isEmpty
          ? 'Hallo Fußballfamilie!'
          : 'Hallo $firstName!',
      subtitle: 'Alles für deine Fußballwoche',
      children: [
        if (loading)
          const LinearProgressIndicator(
              key: ValueKey('parent-dashboard-initial-loading'), minHeight: 2),
        if (players.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ChildFilter(
                label: 'Alle Kinder',
                selected: selected == null,
                id: 'all',
                onTap: () => setState(() => _selectedChild = null)),
            for (final player in players)
              _ChildFilter(
                  label: '${player.displayName} · ${player.teamCode}',
                  selected: selected == player.id,
                  id: player.id,
                  onTap: () => setState(() => _selectedChild = player.id)),
          ]),
          const SizedBox(height: 18),
        ],
        if (failed)
          ParentLinkRow(
              icon: Icons.refresh,
              title: 'Übersicht konnte nicht geladen werden',
              subtitle: 'Antippen und erneut versuchen',
              onTap: () => ref.invalidate(parentDashboardSummaryProvider)),
        if (responsesAsync.hasError)
          ParentLinkRow(
              icon: Icons.refresh,
              title: 'Rückmeldungen erneut laden',
              onTap: () => ref.invalidate(personalResponsesProvider)),
        if (open.isNotEmpty)
          ParentLinkRow(
              key: const ValueKey('parent-open-responses'),
              icon: Icons.circle,
              title:
                  '${open.length} ${open.length == 1 ? 'Rückmeldung' : 'Rückmeldungen'} offen',
              iconColor: const Color(0xFFF0A020),
              iconSize: 10,
              onTap: () => context.go(Uri(
                      path: '/parent/responses',
                      queryParameters: {
                        'open': '1',
                        if (selected != null) 'playerId': selected
                      }).toString())),
        for (final live
            in (matchesAsync.valueOrNull ?? []).where(isActiveFamilyTicker))
          if (selected == null || visits.any((v) => v.item.eventId == live.id))
            ParentLinkRow(
                icon: Icons.sensors,
                title: 'Jetzt live · ${live.title}',
                subtitle: 'Liveticker öffnen',
                onTap: () => context.go(
                    '/parent/matches/${Uri.encodeComponent(live.id)}?tab=live')),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(
              child: Text('Als Nächstes',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          TextButton(
              onPressed: () => context.go('/parent/events'),
              style: TextButton.styleFrom(
                  foregroundColor: parentMatchColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4)),
              child:
                  const Text('Alle Termine', style: TextStyle(fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final cards = <Widget>[
            if (training.isNotEmpty) ParentEventCard(visits: training),
            if (match.isNotEmpty) ParentEventCard(visits: match),
          ];
          if (constraints.maxWidth >= 720 && cards.length == 2) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 16),
              Expanded(child: cards[1])
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
        }),
        if (!loading && !failed && training.isEmpty && match.isEmpty)
          ParentLinkRow(
              icon: Icons.event_available_outlined,
              title: 'Aktuell keine nächsten Trainings oder Spiele',
              subtitle: 'Alle Termine im Kalender ansehen',
              onTap: () => context.go('/parent/events')),
        if (!loading && training.isNotEmpty && match.isEmpty)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Noch kein nächstes Spiel geplant.',
                  style: TextStyle(
                      fontSize: 13, color: context.appColors.textMuted))),
        if (!loading && match.isNotEmpty && training.isEmpty)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Noch kein nächstes Training geplant.',
                  style: TextStyle(
                      fontSize: 13, color: context.appColors.textMuted))),
        ParentLinkRow(
            key: const ValueKey('parent-inbox-preview'),
            icon: Icons.mail_outline,
            title: contacts.isNotEmpty
                ? (contacts.first.senderIsStaff
                    ? 'Neue Nachricht vom Trainer'
                    : 'Neue Nachricht im Postfach')
                : unread.isNotEmpty
                    ? 'Neue Mitteilung im Postfach'
                    : 'Postfach öffnen',
            attention: contacts.isNotEmpty || unread.isNotEmpty,
            onTap: () => context.go(contacts.isNotEmpty
                ? '/parent/messages?section=contact'
                : unread.isNotEmpty
                    ? '/parent/messages?section=notifications'
                    : '/parent/messages')),
        for (final consent in consents
            .where((c) => visiblePlayers.any((p) => p.id == c.playerId)))
          ParentLinkRow(
              icon: Icons.verified_user_outlined,
              title: 'Einwilligung für ${consent.playerName} prüfen',
              onTap: () => context.go(
                  '/parent/players/${Uri.encodeComponent(consent.playerId)}?consents=1')),
        if (!loading && !failed && players.isEmpty)
          ParentLinkRow(
              icon: Icons.person_add_alt,
              title: 'Noch kein Kind zugeordnet',
              subtitle: 'Das Trainerteam hilft bei der Zuordnung.',
              onTap: () => context.go('/parent/messages?section=contact')),
        if (pushReady == false)
          ParentLinkRow(
              icon: Icons.notifications_none,
              title: 'Push einstellen',
              subtitle: 'Wichtige Änderungen direkt erfahren',
              onTap: () => context.go('/parent/messages?section=settings')),
      ],
    );
  }
}

class _ChildFilter extends StatelessWidget {
  const _ChildFilter(
      {required this.label,
      required this.selected,
      required this.id,
      required this.onTap});
  final String label;
  final bool selected;
  final String id;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? AppColors.yellow
            : context.isDarkMode
                ? context.appColors.surfaceRaised
                : const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
            key: ValueKey('parent-child-filter-$id'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? Colors.black
                            : context.appColors.text)))),
      ));
}
