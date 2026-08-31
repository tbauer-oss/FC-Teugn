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
          _FamilyCockpitBanner(
            childCount: players.length,
            weekCount: timeline.length,
            openCount: openResponses.length,
          ),
          SizedBox(height: sectionGap),
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
          const _ParentQuickActions(),
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

class _FamilyCockpitBanner extends StatelessWidget {
  const _FamilyCockpitBanner({
    required this.childCount,
    required this.weekCount,
    required this.openCount,
  });

  final int childCount;
  final int weekCount;
  final int openCount;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF111410), Color(0xFF423B00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.yellow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.family_restroom_rounded,
                color: AppColors.black,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'JETZT WICHTIG',
                    style: TextStyle(
                      color: AppColors.yellow,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    openCount == 0
                        ? 'Alles im grünen Bereich'
                        : '$openCount ${openCount == 1 ? 'Rückmeldung' : 'Rückmeldungen'} offen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$childCount ${childCount == 1 ? 'Kind' : 'Kinder'} · '
                    '$weekCount ${weekCount == 1 ? 'Termin' : 'Termine'} in den nächsten Tagen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              openCount == 0
                  ? Icons.check_circle_rounded
                  : Icons.arrow_forward_rounded,
              color:
                  openCount == 0 ? const Color(0xFF6EE7B7) : AppColors.yellow,
              size: 21,
            ),
          ],
        ),
      );
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
  Widget build(BuildContext context) {
    final surfaces = context.appColors;
    final base = surfaces.surfaceRaised;
    final tint = Color.alphaBlend(
      accent.withValues(alpha: context.isDarkMode ? .13 : .075),
      base,
    );
    return Container(
      key: const ValueKey('family-dashboard-adaptive-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint,
            base,
            surfaces.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
            color: surfaces.shadow.withValues(
              alpha: context.isDarkMode ? .24 : .035,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
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
    if (itemCount == 0) return const SizedBox.shrink();
    return _FamilyDashboardPanel(
      accent: AppColors.gold,
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
            title: 'Heute wichtig',
            subtitle:
                '$itemCount ${itemCount == 1 ? 'Punkt braucht' : 'Punkte brauchen'} deine Aufmerksamkeit.',
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
              color: context.appSuccess,
              onTap: () => context.go('/parent/matches/${nomination.match.id}'),
            ),
            const SizedBox(height: 7),
          ],
          for (final event in carpoolEvents.take(2)) ...[
            _CompactLink(
              icon: Icons.directions_car_filled_rounded,
              title: 'Mitfahrt verfügbar oder gesucht',
              subtitle: '${event.title} · ${_shortDate(event.startAt)}',
              color: context.appSuccess,
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
              : context.appColors.brandSoft,
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
                style: TextStyle(
                    color: context.appColors.textMuted,
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
            color: done ? context.appSuccess : context.appWarning),
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
              title: 'Als Nächstes',
              subtitle: items.isEmpty
                  ? 'Keine Termine in den nächsten sieben Tagen.'
                  : '${items.length} ${items.length == 1 ? 'Termin' : 'Termine'} in den nächsten sieben Tagen',
              trailing: TextButton(
                  onPressed: () => context.go('/parent/events'),
                  child: const Text('Alle')),
            ),
            if (items.isNotEmpty) ...[
              const Divider(height: 17),
              for (final item in items.take(3)) _TimelineRow(item: item),
              if (items.length > 3)
                TextButton(
                    onPressed: () => context.go('/parent/events'),
                    child: Text('${items.length - 3} weitere Termine')),
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
                    ? context.appColors.brandSoft
                    : context.appSuccess.withValues(alpha: .10),
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
        accent: context.appSuccess,
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
    final nextItem = upcoming.firstOrNull;
    final open = upcoming.where((item) => item.isOpen).length +
        (consent?.openCount ?? 0);
    return InkWell(
      onTap: () => context.go('/parent/players/${player.id}'),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: context.appColors.surfaceMuted,
            border: Border.all(color: context.appColors.outline),
            borderRadius: BorderRadius.circular(15)),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
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
          const SizedBox(width: 7),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: open > 0
                    ? context.appColors.brandSoft
                    : context.appSuccess.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                open > 0 ? '$open offen' : _squadStatus(player.id, matches),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: open > 0 ? context.appWarning : context.appSuccess,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (nextItem != null)
            Flexible(
              flex: 2,
              child: Text(
                '${nextItem.isMatch ? 'Spiel' : 'Training'} · '
                '${_shortDate(nextItem.startAt)} · ${_clock(nextItem.startAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const Icon(Icons.chevron_right_rounded, size: 20),
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

class _ParentQuickActions extends StatelessWidget {
  const _ParentQuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = [
      ('Kalender', Icons.calendar_month_rounded, '/parent/events'),
      ('Kinder', Icons.family_restroom_rounded, '/parent/players'),
      ('Spiele', Icons.sports_soccer_rounded, '/parent/matches'),
      ('Trainerteam', Icons.forum_rounded, '/parent/messages?section=contact'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schnellzugriff',
          style: TextStyle(
            color: context.appColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 4 : 2;
            const gap = 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: width,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(action.$3),
                      icon: Icon(action.$2, size: 18),
                      label: Text(
                        action.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
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
