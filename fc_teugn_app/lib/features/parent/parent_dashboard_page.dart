import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/communication.dart';
import '../../core/models/dashboard_summary.dart';
import '../../core/models/event.dart';
import '../../core/models/matchday.dart';
import '../../core/models/personal_response.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../shared/dashboard_event_navigation.dart';
import '../shared/dashboard_notifications.dart';
import '../shared/family_responses.dart';
import '../shared/page_scaffold.dart';
import 'family_assistant_model.dart';

class ParentDashboardPage extends ConsumerWidget {
  const ParentDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final sectionGap = compact ? 8.0 : 10.0;
    final user = ref.watch(authProvider).user;
    final summaryAsync = ref.watch(parentDashboardSummaryProvider);
    final responsesAsync = ref.watch(personalResponsesProvider);
    final matchesAsync = ref.watch(parentMatchdaysProvider);
    final consentAsync = ref.watch(parentConsentAttentionProvider);
    final pushReadyAsync = ref.watch(currentDevicePushReadyProvider);
    final summary = summaryAsync.valueOrNull;
    final players = summary?.players ?? const <PlayerModel>[];
    final responses =
        responsesAsync.valueOrNull ?? const <PersonalResponseModel>[];
    final events = summary?.events ?? const <EventModel>[];
    final matches = matchesAsync.valueOrNull ?? const <MatchdayModel>[];
    final consents =
        consentAsync.valueOrNull ?? const <ParentConsentAttention>[];
    final notifications =
        summary?.notifications ?? const <AppNotificationModel>[];
    final pushReady = pushReadyAsync.valueOrNull ??
        (user?.registrationRequest?.pushOptIn == true ? true : null);
    final isInitialDataLoading =
        (summaryAsync.isLoading && !summaryAsync.hasValue) ||
            (responsesAsync.isLoading && !responsesAsync.hasValue);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final timeline = buildFamilyTimeline(
      events: events,
      responses: responses,
      from: dayStart,
      until: dayStart.add(const Duration(days: 8)),
    );
    final openResponses = responses.where((item) => item.isOpen).toList()
      ..sort((a, b) {
        if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
        return a.startAt.compareTo(b.startAt);
      });
    final liveMatches = matches.where(isActiveFamilyTicker).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final childIds = players.map((player) => player.id).toSet();
    final carpoolEvents = events.where((event) {
      return event.startAt.isAfter(now) &&
          event.startAt.isBefore(now.add(const Duration(days: 8))) &&
          hasRelevantCarpool(event, childIds);
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final changes = notifications.where((item) {
      return !item.isRead &&
          isScheduleChangeNotification(item) &&
          item.createdAt.isAfter(now.subtract(const Duration(days: 14)));
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return PageScaffold(
      title: 'Hallo ${_firstName(user?.name)}!',
      subtitle: 'Dein Familien-Assistent – nur das, was jetzt wichtig ist.',
      denseMobileHeader: true,
      headerAction: DashboardNotificationBell(
        notifications: notifications,
        isTrainer: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isInitialDataLoading) ...[
            const LinearProgressIndicator(
              key: ValueKey('parent-dashboard-initial-loading'),
              minHeight: 3,
            ),
            const SizedBox(height: 8),
          ],
          for (final match in liveMatches) ...[
            _LiveTickerCard(match: match),
            SizedBox(height: sectionGap),
          ],
          _TodayImportantCard(
            openResponses: openResponses,
            scheduleChanges: changes,
            carpoolEvents: carpoolEvents,
            matches: matches,
            players: players,
            consents: consents,
            notifications: notifications,
          ),
          SizedBox(height: sectionGap),
          if (_needsSetup(players, pushReady)) ...[
            _FamilySetupCard(
              players: players,
              pushDone: pushReady == true,
            ),
            SizedBox(height: sectionGap),
          ],
          _WeekTimelineCard(items: timeline),
          SizedBox(height: sectionGap),
          _ChildrenSection(
            players: players,
            responses: responses,
            matches: matches,
            consents: consents,
          ),
          SizedBox(height: sectionGap),
          const _TrainerContactCard(),
        ],
      ),
    );
  }

  static bool _needsSetup(List<PlayerModel> players, bool? pushReady) =>
      players.isEmpty ||
      !players.any((player) => player.teamId?.isNotEmpty == true) ||
      pushReady == false;

  static String _firstName(String? name) => name == null || name.trim().isEmpty
      ? 'Fußballfamilie'
      : name.trim().split(RegExp(r'\s+')).first;
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.trailing});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AppColors.yellowSoft,
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 19, color: AppColors.black),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      );
}

class _LiveTickerCard extends StatelessWidget {
  const _LiveTickerCard({required this.match});
  final MatchdayModel match;

  @override
  Widget build(BuildContext context) {
    final ticker = match.ticker!;
    final opponent = match.details?.opponent ?? 'Gegner';
    return Semantics(
      button: true,
      label:
          'Liveticker ${match.title}, ${ticker.ourGoals} zu ${ticker.theirGoals}',
      child: InkWell(
        onTap: () => context.go('/parent/matches/${match.id}?tab=live'),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.black, Color(0xFF4B4200)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.sensors_rounded, color: AppColors.black),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      _PulseDot(),
                      SizedBox(width: 6),
                      Text('JETZT LIVE',
                          style: TextStyle(
                              color: AppColors.yellow,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .6)),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      '${match.ownTeamName} ${ticker.ourGoals} : '
                      '${ticker.theirGoals} $opponent',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                  ]),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: Colors.redAccent, shape: BoxShape.circle),
      );
}

class _FamilyDashboardPanel extends StatelessWidget {
  const _FamilyDashboardPanel({
    required this.child,
    required this.accent,
  });

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .075),
              Colors.white,
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: .18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );
}

class _TodayImportantCard extends StatelessWidget {
  const _TodayImportantCard({
    required this.openResponses,
    required this.scheduleChanges,
    required this.carpoolEvents,
    required this.matches,
    required this.players,
    required this.consents,
    required this.notifications,
  });
  final List<PersonalResponseModel> openResponses;
  final List<AppNotificationModel> scheduleChanges;
  final List<EventModel> carpoolEvents;
  final List<MatchdayModel> matches;
  final List<PlayerModel> players;
  final List<ParentConsentAttention> consents;
  final List<AppNotificationModel> notifications;

  @override
  Widget build(BuildContext context) {
    final nominations = _nominations(matches, players, notifications);
    final itemCount = openResponses.length +
        scheduleChanges.length +
        carpoolEvents.length +
        nominations.length +
        consents.length;
    return _FamilyDashboardPanel(
      accent: itemCount == 0 ? AppColors.success : AppColors.gold,
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 10 : 12,
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _SectionHeading(
            icon: itemCount == 0
                ? Icons.task_alt_rounded
                : Icons.notifications_active_rounded,
            title: itemCount == 0 ? 'Alles erledigt' : 'Heute wichtig',
            subtitle: itemCount == 0
                ? 'Für deine Familie ist gerade keine Aktion notwendig.'
                : '$itemCount ${itemCount == 1 ? 'Punkt braucht' : 'Punkte brauchen'} deine Aufmerksamkeit.',
          ),
          if (itemCount > 0) const Divider(height: 18),
          for (final response in openResponses.take(3)) ...[
            _ImportantResponse(item: response),
            const SizedBox(height: 7),
          ],
          if (openResponses.length > 3)
            _CompactLink(
              icon: Icons.how_to_reg_rounded,
              title: '${openResponses.length - 3} weitere Rückmeldungen',
              subtitle: 'Alle offenen Antworten anzeigen',
              onTap: () => context.go('/parent/family'),
            ),
          for (final notification in scheduleChanges.take(2)) ...[
            _CompactLink(
              icon: Icons.update_rounded,
              title: 'Terminänderung',
              subtitle: scheduleChangeSummary(notification),
              onTap: () => _openNotification(context, notification),
            ),
            const SizedBox(height: 7),
          ],
          for (final nomination in nominations.take(2)) ...[
            _CompactLink(
              icon: Icons.verified_rounded,
              title: 'Neue Nominierung · ${nomination.playerName}',
              subtitle:
                  '${nomination.match.title} · ${_shortDate(nomination.match.startAt)}',
              color: AppColors.success,
              onTap: () => context.go('/parent/matches/${nomination.match.id}'),
            ),
            const SizedBox(height: 7),
          ],
          for (final event in carpoolEvents.take(2)) ...[
            _CompactLink(
              icon: Icons.directions_car_filled_rounded,
              title: 'Mitfahrt verfügbar oder gesucht',
              subtitle: '${event.title} · ${_shortDate(event.startAt)}',
              color: AppColors.success,
              onTap: () => context.go(Uri(
                  path: '/parent/events',
                  queryParameters: {'eventId': event.id}).toString()),
            ),
            const SizedBox(height: 7),
          ],
          for (final consent in consents.take(1))
            _CompactLink(
              icon: Icons.privacy_tip_outlined,
              title: 'Einwilligung prüfen · ${consent.playerName}',
              subtitle:
                  '${consent.openCount} ${consent.openCount == 1 ? 'Entscheidung ist' : 'Entscheidungen sind'} offen',
              onTap: () =>
                  context.go('/parent/players/${consent.playerId}?consents=1'),
            ),
        ]),
      ),
    );
  }

  static List<_Nomination> _nominations(
    List<MatchdayModel> matches,
    List<PlayerModel> players,
    List<AppNotificationModel> notifications,
  ) {
    final now = DateTime.now();
    final notifiedMatchIds = notifications
        .where(
          (item) =>
              !item.isRead && item.category == NotificationCategory.nomination,
        )
        .map((item) =>
            Uri.tryParse(item.actionUrl ?? '')?.pathSegments.lastOrNull)
        .whereType<String>()
        .toSet();
    final playerById = {for (final player in players) player.id: player};
    final result = <_Nomination>[];
    for (final match in matches) {
      if (match.startAt.isBefore(now) || match.familyReleasedAt == null) {
        continue;
      }
      final publishedAt = match.squadPublishedAt?.toLocal();
      final recentlyPublished = publishedAt != null &&
          publishedAt.isAfter(now.subtract(const Duration(days: 7)));
      if (!recentlyPublished && !notifiedMatchIds.contains(match.id)) {
        continue;
      }
      for (final player in players) {
        final status = match.nominationForPlayer(player.id);
        if (playerById[player.id] != null &&
            status != null &&
            status != NominationStatus.declined) {
          result.add(_Nomination(match: match, playerName: player.displayName));
        }
      }
    }
    result.sort((a, b) => a.match.startAt.compareTo(b.match.startAt));
    return result;
  }
}

class _Nomination {
  const _Nomination({required this.match, required this.playerName});
  final MatchdayModel match;
  final String playerName;
}

class _ImportantResponse extends StatelessWidget {
  const _ImportantResponse({required this.item});
  final PersonalResponseModel item;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: item.isOverdue
              ? Colors.red.withValues(alpha: .06)
              : AppColors.yellowSoft.withValues(alpha: .46),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(
                item.isMatch
                    ? Icons.sports_soccer_rounded
                    : Icons.sports_rounded,
                size: 19),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${item.title} · ${item.playerName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(_shortDate(item.startAt),
                style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 7),
          if (item.canRespond)
            PersonalResponseQuickActions(item: item, expanded: true)
          else
            OutlinedButton.icon(
              onPressed: () => _openResponse(context, item),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Rückmeldung ansehen'),
            ),
        ]),
      );
}

class _CompactLink extends StatelessWidget {
  const _CompactLink(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.color = AppColors.gold});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ])),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ]),
        ),
      );
}

class _FamilySetupCard extends StatelessWidget {
  const _FamilySetupCard({required this.players, required this.pushDone});
  final List<PlayerModel> players;
  final bool pushDone;

  @override
  Widget build(BuildContext context) {
    final childDone = players.isNotEmpty;
    final teamDone = players.any((player) => player.teamId?.isNotEmpty == true);
    final done = [childDone, teamDone, pushDone].where((value) => value).length;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 10 : 12,
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _SectionHeading(
              icon: Icons.rocket_launch_outlined,
              title: 'Ruhig startklar werden',
              subtitle: '$done von 3 Schritten erledigt'),
          const SizedBox(height: 9),
          LinearProgressIndicator(value: done / 3, minHeight: 6),
          const SizedBox(height: 7),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _SetupChip(
                done: childDone,
                label: 'Kinder prüfen',
                onTap: () => context.go('/parent/players')),
            _SetupChip(
                done: teamDone,
                label: 'Mannschaft prüfen',
                onTap: () => context.go('/parent/players')),
            _SetupChip(
                done: pushDone,
                label: 'Push einstellen',
                onTap: () => context.go('/parent/messages?section=settings')),
          ]),
        ]),
      ),
    );
  }
}

class _SetupChip extends StatelessWidget {
  const _SetupChip(
      {required this.done, required this.label, required this.onTap});
  final bool done;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        avatar: Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: done ? AppColors.success : AppColors.gold),
        label: Text(label),
      );
}

class _WeekTimelineCard extends StatelessWidget {
  const _WeekTimelineCard({required this.items});
  final List<FamilyTimelineItem> items;

  @override
  Widget build(BuildContext context) => _FamilyDashboardPanel(
        accent: AppColors.gold,
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 10 : 12,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _SectionHeading(
              icon: Icons.view_timeline_rounded,
              title: 'Diese Woche',
              subtitle: items.isEmpty
                  ? 'Keine Termine in den nächsten sieben Tagen.'
                  : '${items.length} ${items.length == 1 ? 'Termin' : 'Termine'} – ohne doppelte Einträge',
              trailing: TextButton(
                  onPressed: () => context.go('/parent/events'),
                  child: const Text('Kalender')),
            ),
            if (items.isNotEmpty) ...[
              const Divider(height: 17),
              for (final item in items.take(7)) _TimelineRow(item: item),
              if (items.length > 7)
                TextButton(
                    onPressed: () => context.go('/parent/events'),
                    child: Text('${items.length - 7} weitere Termine')),
            ],
          ]),
        ),
      );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item});
  final FamilyTimelineItem item;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _openTimelineItem(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: item.isMatch
                    ? AppColors.yellowSoft
                    : AppColors.success.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Column(children: [
                Text(_weekday(item.startAt),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900)),
                Text('${item.startAt.day}.${item.startAt.month}.',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    '${_clock(item.startAt)} Uhr${item.location.trim().isEmpty ? '' : ' · ${item.location}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ])),
            if (item.response?.isOpen == true)
              const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.schedule_rounded, size: 15),
                  label: Text('Antworten'))
            else
              const Icon(Icons.chevron_right_rounded, size: 20),
          ]),
        ),
      );
}

class _ChildrenSection extends StatelessWidget {
  const _ChildrenSection(
      {required this.players,
      required this.responses,
      required this.matches,
      required this.consents});
  final List<PlayerModel> players;
  final List<PersonalResponseModel> responses;
  final List<MatchdayModel> matches;
  final List<ParentConsentAttention> consents;

  @override
  Widget build(BuildContext context) => _FamilyDashboardPanel(
        accent: AppColors.success,
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 10 : 12,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _SectionHeading(
              icon: Icons.family_restroom_rounded,
              title: 'Deine Kinder',
              subtitle: players.isEmpty
                  ? 'Noch kein Kind zugeordnet.'
                  : 'Nächste Termine, Kaderstatus und offene Aufgaben.',
              trailing: IconButton(
                  onPressed: () => context.go('/parent/players'),
                  tooltip: 'Alle Kinder',
                  icon: const Icon(Icons.arrow_forward_rounded)),
            ),
            if (players.isNotEmpty) ...[
              const SizedBox(height: 9),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 2 : 1;
                const gap = 8.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final player in players)
                    SizedBox(
                      width: width,
                      child: _ChildCard(
                        player: player,
                        responses: responses
                            .where((item) => item.playerId == player.id)
                            .toList(),
                        matches: matches,
                        consent: consents
                            .where((item) => item.playerId == player.id)
                            .firstOrNull,
                      ),
                    ),
                ]);
              }),
            ],
          ]),
        ),
      );
}

class _ChildCard extends StatelessWidget {
  const _ChildCard(
      {required this.player,
      required this.responses,
      required this.matches,
      this.consent});
  final PlayerModel player;
  final List<PersonalResponseModel> responses;
  final List<MatchdayModel> matches;
  final ParentConsentAttention? consent;

  @override
  Widget build(BuildContext context) {
    final upcoming = responses
        .where((item) => item.startAt.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final nextTraining = upcoming.where((item) => !item.isMatch).firstOrNull;
    final nextMatch = upcoming.where((item) => item.isMatch).firstOrNull;
    final open = upcoming.where((item) => item.isOpen).length +
        (consent?.openCount ?? 0);
    return InkWell(
      onTap: () => context.go('/parent/players/${player.id}'),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(15)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: AppColors.yellowSoft,
              foregroundColor: AppColors.black,
              child: Text(player.initials,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(player.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(player.teamCode,
                      style: Theme.of(context).textTheme.bodySmall),
                ])),
            if (open > 0)
              Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.schedule_rounded, size: 15),
                  label: Text('$open offen'))
            else
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
          ]),
          const SizedBox(height: 7),
          _ChildFact(
            icon: Icons.sports_rounded,
            label: 'Training',
            value: nextTraining == null
                ? 'Kein Termin'
                : '${_shortDate(nextTraining.startAt)} · ${_clock(nextTraining.startAt)}',
            onTap: nextTraining == null
                ? null
                : () => _openResponse(context, nextTraining),
          ),
          _ChildFact(
            icon: Icons.sports_soccer_rounded,
            label: 'Spiel',
            value: nextMatch == null
                ? 'Kein Termin'
                : '${_shortDate(nextMatch.startAt)} · ${nextMatch.title}',
            onTap: nextMatch == null
                ? null
                : () => _openResponse(context, nextMatch),
          ),
          _ChildFact(
              icon: Icons.verified_user_outlined,
              label: 'Kader',
              value: _squadStatus(player.id, matches)),
        ]),
      ),
    );
  }

  static String _squadStatus(String playerId, List<MatchdayModel> matches) {
    final upcoming = matches.where((match) {
      if (match.startAt.isBefore(DateTime.now()) ||
          match.familyReleasedAt == null) {
        return false;
      }
      return match.eligiblePlayers.any((player) => player.id == playerId) ||
          match.nominationForPlayer(playerId) != null;
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final match = upcoming.firstOrNull;
    if (match == null) return 'Noch keine Freigabe';
    final status = match.nominationForPlayer(playerId);
    if (!match.hasSquad) return 'Noch offen';
    if (status == null) return 'Nicht nominiert';
    return switch (status) {
      NominationStatus.nominated => 'Nominiert',
      NominationStatus.onCall => 'Auf Abruf',
      NominationStatus.declined => 'Nicht dabei',
    };
  }
}

class _ChildFact extends StatelessWidget {
  const _ChildFact(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(icon, size: 17, color: AppColors.gold),
            const SizedBox(width: 7),
            SizedBox(
                width: 62,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800))),
            Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted))),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 17),
          ]),
        ),
      );
}

class _TrainerContactCard extends StatelessWidget {
  const _TrainerContactCard();

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: () => context.go('/parent/messages?section=contact'),
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: _SectionHeading(
              icon: Icons.forum_rounded,
              title: 'Trainerteam kontaktieren',
              subtitle:
                  'Kurze organisatorische Nachricht · Löschung nach 30 Tagen',
              trailing: Icon(Icons.chevron_right_rounded),
            ),
          ),
        ),
      );
}

void _openResponse(BuildContext context, PersonalResponseModel response) {
  context.go(Uri(path: '/parent/family', queryParameters: {
    'eventId': response.eventId,
    'playerId': response.playerId
  }).toString());
}

void _openTimelineItem(BuildContext context, FamilyTimelineItem item) {
  if (item.response != null) {
    _openResponse(context, item.response!);
  } else if (item.event != null) {
    context.go(dashboardEventRoute(event: item.event!, isTrainer: false));
  } else {
    context.go('/parent/events');
  }
}

void _openNotification(
    BuildContext context, AppNotificationModel notification) {
  final id =
      Uri.tryParse(notification.actionUrl ?? '')?.pathSegments.lastOrNull;
  if ((notification.category == NotificationCategory.event ||
          notification.category == NotificationCategory.eventReminder) &&
      id != null &&
      id != 'events') {
    context.go(Uri(path: '/parent/events', queryParameters: {'eventId': id})
        .toString());
    return;
  }
  context.go('/parent/messages?section=notifications');
}

String _clock(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _shortDate(DateTime date) => '${date.day}.${date.month}.${date.year}';
String _weekday(DateTime date) => switch (date.weekday) {
      DateTime.monday => 'MO',
      DateTime.tuesday => 'DI',
      DateTime.wednesday => 'MI',
      DateTime.thursday => 'DO',
      DateTime.friday => 'FR',
      DateTime.saturday => 'SA',
      _ => 'SO',
    };
