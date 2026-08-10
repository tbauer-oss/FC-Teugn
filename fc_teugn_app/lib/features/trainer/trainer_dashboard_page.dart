import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/models/player.dart';
import '../../core/models/organization.dart';
import '../../core/models/team_operations.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/regular_training_schedule.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import '../shared/dashboard_notifications.dart';
import '../shared/family_responses.dart';

class TrainerDashboardPage extends ConsumerWidget {
  const TrainerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final user = ref.watch(authProvider).user;
    final players = ref.watch(playersProvider);
    final events = ref.watch(eventsProvider);
    final approvals = ref.watch(pendingUsersProvider);
    final organization = ref.watch(organizationProvider).valueOrNull;
    final notifications =
        ref.watch(liveNotificationsProvider).valueOrNull ?? const [];
    final team = organization?.currentTeam;
    final teamId = team?.id;
    final contextTeamIds = organization?.workingContext.teamIds.toSet() ??
        {if (teamId != null) teamId};
    final teamOperations = teamId == null
        ? null
        : ref.watch(teamOperationsProvider(teamId)).valueOrNull;

    final teamPlayers = (players.valueOrNull ?? const <PlayerModel>[])
        .where((player) =>
            contextTeamIds.isEmpty || contextTeamIds.contains(player.teamId))
        .toList();
    final activePlayers = teamPlayers
        .where((player) => player.status == PlayerStatus.active)
        .length;
    final injuredPlayers = teamPlayers
        .where((player) => player.status == PlayerStatus.injured)
        .length;

    final eventItems = _dashboardEvents(
      events.valueOrNull ?? const <EventModel>[],
      organization,
      now,
      contextTeamIds,
    );
    final upcoming = eventItems
        .where(
          (event) =>
              !event.isCancelled &&
              event.startAt.isAfter(now) &&
              _belongsToTeams(event, contextTeamIds),
        )
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final nextEvent = upcoming.firstOrNull;
    final nextEvents = upcoming.take(4).toList();
    final openResponses = _openResponses(nextEvent);
    final approvalCount = approvals.valueOrNull?.length ?? 0;
    final overdueTasks =
        teamOperations?.tasks.where((task) => task.isOverdue).toList() ??
            const <TeamTaskModel>[];
    final openTasks =
        teamOperations?.tasks.where((task) => !task.isDone).toList() ??
            const <TeamTaskModel>[];
    final totalOpen = openResponses + approvalCount + openTasks.length;
    final priorities = _priorities(
      nextEvent: nextEvent,
      openResponses: openResponses,
      approvals: approvalCount,
      overdueTasks: overdueTasks,
      openTasks: openTasks,
      now: now,
    );

    return PageScaffold(
      title: '${_greeting(now)}, ${_firstName(user?.name)}',
      subtitle:
          '${_germanDate(now)} · ${team?.displayName ?? 'Meine Mannschaft'}',
      denseMobileHeader: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardNotifications(
            notifications: notifications,
            isTrainer: true,
          ),
          if (user?.role == UserRole.superAdmin) ...[
            AdminMemberRequestsCard(
              pending: approvals,
              onOpen: () => context.go('/trainer/approvals'),
              onRefresh: () => ref.invalidate(pendingUsersProvider),
            ),
            const SizedBox(height: 12),
          ],
          if (user?.parentPlayers.isNotEmpty == true) ...[
            const PersonalResponsesCard(isTrainer: true),
            const SizedBox(height: 12),
          ],
          _NextEventHero(event: nextEvent, now: now),
          const SizedBox(height: 12),
          _StatusGrid(
            playersLoading: players.isLoading,
            playersError: players.hasError,
            activePlayers: activePlayers,
            injuredPlayers: injuredPlayers,
            nextEvent: nextEvent,
            totalOpen: totalOpen,
            onRetryPlayers: () => ref.invalidate(playersProvider),
          ),
          if (players.hasError) ...[
            const SizedBox(height: 10),
            _PlayerLoadFailure(
              onRetry: () => ref.invalidate(playersProvider),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final priorityCard = _PriorityCard(items: priorities);
              final agendaCard =
                  _AgendaCard(events: nextEvents.skip(1).toList());
              if (constraints.maxWidth < 780) {
                return Column(
                  children: [
                    priorityCard,
                    const SizedBox(height: 12),
                    agendaCard,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: priorityCard),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: agendaCard),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const _QuickActions(),
        ],
      ),
    );
  }

  bool _belongsToTeams(EventModel event, Set<String> teamIds) {
    if (teamIds.isEmpty) return true;
    return teamIds.contains(event.teamId) ||
        event.targetTeams.any((target) => teamIds.contains(target.id));
  }

  int _openResponses(EventModel? event) {
    if (event == null) return 0;
    if (event.missingAttendance.isNotEmpty) {
      return event.missingAttendance.length;
    }
    return event.attendanceSummary.unknown;
  }

  List<_DashboardPriority> _priorities({
    required EventModel? nextEvent,
    required int openResponses,
    required int approvals,
    required List<TeamTaskModel> overdueTasks,
    required List<TeamTaskModel> openTasks,
    required DateTime now,
  }) {
    final items = <_DashboardPriority>[];
    if (openResponses > 0 && nextEvent != null) {
      items.add(
        _DashboardPriority(
          icon: Icons.how_to_reg_rounded,
          color: AppColors.gold,
          title: '$openResponses Rückmeldungen fehlen',
          subtitle: 'Für „${nextEvent.title}“ Zu- und Absagen prüfen',
          route: _eventRoute(nextEvent),
        ),
      );
    }
    if (overdueTasks.isNotEmpty) {
      items.add(
        _DashboardPriority(
          icon: Icons.assignment_late_rounded,
          color: const Color(0xFFB54736),
          title: '${overdueTasks.length} Aufgaben überfällig',
          subtitle: overdueTasks.first.title,
          route: '/trainer/operations',
        ),
      );
    }
    if (approvals > 0) {
      items.add(
        _DashboardPriority(
          icon: Icons.person_add_alt_1_rounded,
          color: AppColors.success,
          title: '$approvals Mitglieder warten auf Freigabe',
          subtitle: 'Rolle und Mannschaft kontrollieren',
          route: '/trainer/approvals',
        ),
      );
    }
    final nextMatch = nextEvent?.type == EventType.match ? nextEvent : null;
    if (nextMatch != null &&
        nextMatch.startAt.difference(now) <= const Duration(days: 7)) {
      items.add(
        _DashboardPriority(
          icon: Icons.auto_awesome_rounded,
          color: AppColors.gold,
          title: 'Spieltag vorbereiten',
          subtitle: '${nextMatch.title} · Kader und Aufstellung prüfen',
          route: _eventRoute(nextMatch),
        ),
      );
    }
    if (items.length < 3 && openTasks.isNotEmpty) {
      items.add(
        _DashboardPriority(
          icon: Icons.task_alt_rounded,
          color: AppColors.blue,
          title: '${openTasks.length} offene Teamaufgaben',
          subtitle: openTasks.first.title,
          route: '/trainer/operations',
        ),
      );
    }
    return items.take(3).toList();
  }

  String _firstName(String? name) {
    if (name == null || name.trim().isEmpty) return 'Trainerteam';
    return name.trim().split(RegExp(r'\s+')).first;
  }

  String _greeting(DateTime now) => switch (now.hour) {
        < 11 => 'Guten Morgen',
        < 18 => 'Guten Tag',
        _ => 'Guten Abend',
      };
}

class AdminMemberRequestsCard extends StatelessWidget {
  const AdminMemberRequestsCard({
    super.key,
    required this.pending,
    required this.onOpen,
    required this.onRefresh,
  });

  final AsyncValue<List<AppUser>> pending;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final users = pending.valueOrNull;
    final count = users?.length ?? 0;
    final hasRequests = count > 0;
    final failed = pending.hasError;
    final loading = pending.isLoading && users == null;
    final color = failed
        ? Theme.of(context).colorScheme.error
        : hasRequests
            ? AppColors.gold
            : AppColors.success;
    final title = failed
        ? 'Mitgliedsanfragen konnten nicht geladen werden'
        : loading
            ? 'Mitgliedsanfragen werden geprüft …'
            : hasRequests
                ? '$count offene Mitgliedsanfrage${count == 1 ? '' : 'n'}'
                : 'Keine offenen Mitgliedsanfragen';
    final subtitle = failed
        ? 'Status erneut abrufen'
        : loading
            ? 'Der aktuelle Freigabestatus wird geladen.'
            : hasRequests
                ? 'Neue Registrierungen warten auf Prüfung und Freigabe.'
                : 'Aktuell ist keine Freigabe erforderlich.';

    return Material(
      key: const ValueKey('admin-member-requests-card'),
      color: color.withValues(alpha: hasRequests ? .13 : .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: .32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: failed ? onRefresh : onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: color,
                        ),
                      )
                    : Icon(
                        failed
                            ? Icons.sync_problem_rounded
                            : hasRequests
                                ? Icons.person_add_alt_1_rounded
                                : Icons.verified_user_outlined,
                        color: color,
                        size: 21,
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: failed ? 'Erneut laden' : 'Anfragen prüfen',
                visualDensity: VisualDensity.compact,
                onPressed: failed ? onRefresh : onOpen,
                icon: Icon(
                  failed ? Icons.refresh_rounded : Icons.arrow_forward_rounded,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextEventHero extends StatelessWidget {
  const _NextEventHero({required this.event, required this.now});

  final EventModel? event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final current = event;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (current == null) {
            context.go('/trainer/events');
          } else {
            context.push(_eventRoute(current));
          }
        },
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 16 : 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF171918), Color(0xFF554B00)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: current == null
              ? _EmptyNextEvent(compact: compact)
              : _NextEventContent(event: current, now: now, compact: compact),
        ),
      ),
    );
  }
}

class _NextEventContent extends StatelessWidget {
  const _NextEventContent({
    required this.event,
    required this.now,
    required this.compact,
  });

  final EventModel event;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final details = [
      '${_shortDate(event.startAt)} · ${_time(event.startAt)} Uhr',
      if (event.meetingAt != null) 'Treffen ${_time(event.meetingAt!)} Uhr',
      if (event.meetingLocation?.trim().isNotEmpty == true)
        event.meetingLocation!.trim(),
      if (event.location.trim().isNotEmpty) event.location.trim(),
    ];
    final openResponses = event.missingAttendance.isNotEmpty
        ? event.missingAttendance.length
        : event.attendanceSummary.unknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.yellow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                event.type == EventType.match
                    ? Icons.sports_soccer_rounded
                    : event.type == EventType.training
                        ? Icons.sports_rounded
                        : Icons.event_rounded,
                color: AppColors.black,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'NÄCHSTER TERMIN',
                style: TextStyle(
                  color: AppColors.yellow,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: .7,
                ),
              ),
            ),
            _CountdownChip(label: _countdown(event.startAt, now)),
          ],
        ),
        SizedBox(height: compact ? 12 : 16),
        Text(
          event.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            height: 1.08,
            fontSize: compact ? 23 : 28,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final detail in details) _HeroDetail(label: detail),
            if (openResponses > 0)
              _HeroDetail(label: '$openResponses Rückmeldungen offen'),
          ],
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Text(
              event.type == EventType.match
                  ? 'Spieltag öffnen'
                  : event.type == EventType.training
                      ? 'Training öffnen'
                      : 'Termin öffnen',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.arrow_forward_rounded,
                color: AppColors.yellow, size: 19),
          ],
        ),
      ],
    );
  }
}

class _EmptyNextEvent extends StatelessWidget {
  const _EmptyNextEvent({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: compact ? 44 : 50,
            height: compact ? 44 : 50,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.event_available_rounded),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Noch kein nächster Termin',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Training, Spiel oder Teamtermin planen',
                  style: TextStyle(color: Color(0xFFD9D8CF)),
                ),
              ],
            ),
          ),
          const Icon(Icons.add_circle_rounded, color: AppColors.yellow),
        ],
      );
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .15)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
}

class _HeroDetail extends StatelessWidget {
  const _HeroDetail({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE8E7E0),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({
    required this.playersLoading,
    required this.playersError,
    required this.activePlayers,
    required this.injuredPlayers,
    required this.nextEvent,
    required this.totalOpen,
    required this.onRetryPlayers,
  });

  final bool playersLoading;
  final bool playersError;
  final int activePlayers;
  final int injuredPlayers;
  final EventModel? nextEvent;
  final int totalOpen;
  final VoidCallback onRetryPlayers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 4 : 2;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          final response = nextEvent?.attendanceSummary;
          final responseValue = response == null || response.total == 0
              ? '–'
              : '${response.yes}/${response.total}';
          final items = [
            _StatusItem(
              label: 'Aktiver Kader',
              value: playersError
                  ? '!'
                  : playersLoading
                      ? '–'
                      : '$activePlayers',
              icon: Icons.groups_rounded,
              color: AppColors.blue,
              onTap: playersError
                  ? onRetryPlayers
                  : () => context.go('/trainer/players'),
            ),
            _StatusItem(
              label: 'Verletzt',
              value: playersError || playersLoading ? '–' : '$injuredPlayers',
              icon: Icons.healing_rounded,
              color: const Color(0xFFB54736),
              onTap: () => context.go('/trainer/players'),
            ),
            _StatusItem(
              label: 'Zusagen',
              value: responseValue,
              icon: Icons.how_to_reg_rounded,
              color: AppColors.success,
              onTap: nextEvent == null
                  ? () => context.go('/trainer/events')
                  : () => context.push(_eventRoute(nextEvent!)),
            ),
            _StatusItem(
              label: 'Jetzt offen',
              value: '$totalOpen',
              icon: Icons.notification_important_rounded,
              color: AppColors.gold,
              onTap: () => context.go('/trainer/operations'),
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(width: width, height: 78, child: item),
            ],
          );
        },
      );
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        style: const TextStyle(
                          color: AppColors.black,
                          fontSize: 20,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DashboardPriority {
  const _DashboardPriority({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.items});

  final List<_DashboardPriority> items;

  @override
  Widget build(BuildContext context) => _DashboardSection(
        title: 'Jetzt wichtig',
        trailing: items.isEmpty ? 'Alles erledigt' : '${items.length} Hinweise',
        child: items.isEmpty
            ? const _AllDoneState()
            : Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _PriorityRow(item: items[index]),
                    if (index < items.length - 1)
                      const Divider(height: 1, indent: 47),
                  ],
                ],
              ),
      );
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.item});

  final _DashboardPriority item;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(item.icon, color: item.color, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.black,
                      ),
                    ),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.muted, size: 20),
            ],
          ),
        ),
      );
}

class _AllDoneState extends StatelessWidget {
  const _AllDoneState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 34),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alles im grünen Bereich',
                    style: TextStyle(
                      color: AppColors.black,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Aktuell gibt es nichts Dringendes zu erledigen.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({required this.events});

  final List<EventModel> events;

  @override
  Widget build(BuildContext context) => _DashboardSection(
        title: 'Nächste Termine',
        trailing: 'Kalender',
        onTrailingTap: () => context.go('/trainer/events'),
        child: events.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    'Keine weiteren Termine geplant',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              )
            : Column(
                children: [
                  for (var index = 0; index < events.length; index++) ...[
                    _AgendaRow(event: events[index]),
                    if (index < events.length - 1)
                      const Divider(height: 1, indent: 45),
                  ],
                ],
              ),
      );
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push(_eventRoute(event)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.yellowSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      _month(event.startAt.month),
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${event.startAt.day}',
                      style: const TextStyle(
                        color: AppColors.black,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_weekdayShort(event.startAt.weekday)} · ${_time(event.startAt)} Uhr',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                event.type == EventType.match
                    ? Icons.sports_soccer_rounded
                    : event.type == EventType.training
                        ? Icons.sports_rounded
                        : Icons.event_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      );
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.trailing,
    required this.child,
    this.onTrailingTap,
  });

  final String title;
  final String trailing;
  final Widget child;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (onTrailingTap == null)
                    Text(
                      trailing,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: onTrailingTap,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(trailing),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              child,
            ],
          ),
        ),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final columns = compact ? 2 : 4;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          const actions = [
            ('Termin', Icons.add_rounded, '/trainer/events'),
            ('Training', Icons.sports_rounded, '/trainer/training'),
            ('Spiel', Icons.sports_soccer_rounded, '/trainer/matches'),
            (
              'Nachricht',
              Icons.chat_bubble_outline_rounded,
              '/trainer/messages'
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Schnellzugriff',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: width,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go(action.$3),
                        icon: Icon(action.$2, size: 19),
                        label: AdaptiveButtonLabel(action.$1),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      );
}

class _PlayerLoadFailure extends StatelessWidget {
  const _PlayerLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.yellowSoft.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.yellow),
        ),
        child: Row(
          children: [
            const Icon(Icons.sync_problem_rounded,
                color: AppColors.gold, size: 20),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Spieler konnten nicht geladen werden.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Erneut laden'),
            ),
          ],
        ),
      );
}

String _eventRoute(EventModel event) => switch (event.type) {
      EventType.match => '/trainer/matches/${event.id}',
      EventType.training => event.id.startsWith('training-plan:')
          ? '/trainer/events'
          : '/trainer/training/${event.id}',
      EventType.event => '/trainer/events',
    };

List<EventModel> _dashboardEvents(
  List<EventModel> stored,
  OrganizationContext? organization,
  DateTime now,
  Set<String> contextTeamIds,
) {
  if (organization == null) return stored;
  final result = [...stored];
  for (final team in organization.teams.where(
    (team) => contextTeamIds.isEmpty || contextTeamIds.contains(team.id),
  )) {
    final candidates = <(DateTime, DateTime, String)>[];
    void collect(
      List<String> values,
      String? fallbackLocation,
      DateTime start,
      DateTime end,
    ) {
      if (end.isBefore(now)) return;
      for (final value in values) {
        final slot = RegularTrainingSlot.tryParse(
          value,
          fallbackLocation: fallbackLocation,
        );
        if (slot == null) continue;
        for (final occurrence in slot.occurrences(start, end)) {
          if (occurrence.$1.isAfter(now)) {
            candidates.add((occurrence.$1, occurrence.$2, slot.location));
          }
        }
      }
    }

    final seasonStart = team.seasonStartDate ?? organization.season.startDate;
    final seasonEnd = team.seasonEndDate ?? organization.season.endDate;
    collect(
      team.trainingTimes,
      team.trainingLocation,
      seasonStart,
      seasonEnd,
    );
    if (team.indoorSeasonStartDate != null &&
        team.indoorSeasonEndDate != null) {
      collect(
        team.indoorTrainingTimes,
        team.indoorTrainingLocation,
        team.indoorSeasonStartDate!,
        team.indoorSeasonEndDate!,
      );
    }
    candidates.sort((a, b) => a.$1.compareTo(b.$1));
    final next = candidates.firstOrNull;
    if (next == null ||
        stored.any(
          (event) =>
              event.category == EventCategory.training &&
              (event.teamId == team.id ||
                  event.targetTeams.any((target) => target.id == team.id)) &&
              event.startAt.difference(next.$1).abs() <
                  const Duration(minutes: 5),
        )) {
      continue;
    }
    result.add(
      EventModel(
        id: 'training-plan:${team.id}:${next.$1.millisecondsSinceEpoch}',
        teamId: team.id,
        type: EventType.training,
        category: EventCategory.training,
        status: EventStatus.scheduled,
        visibility: EventVisibility.team,
        title: 'Training · ${team.displayName}',
        startAt: next.$1,
        endAt: next.$2,
        location: next.$3,
        attendanceFinalized: false,
        targetTeams: [
          EventTeam(
            id: team.id,
            name: team.name,
            ageGroupCode: team.ageGroup.code,
          ),
        ],
        attachments: const [],
        attendance: const [],
        attendanceSummary: const AttendanceSummary(),
        missingAttendance: const [],
        carpoolOffers: const [],
        capabilities: const EventCapabilities(),
        reminderMinutes: const [60],
      ),
    );
  }
  return result;
}

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _shortDate(DateTime value) =>
    '${_weekdayShort(value.weekday)}, ${value.day}. ${_monthLong(value.month)}';

String _germanDate(DateTime value) =>
    '${_weekdayLong(value.weekday)}, ${value.day}. ${_monthLong(value.month)}';

String _countdown(DateTime value, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final days = date.difference(today).inDays;
  if (days == 0) return 'Heute';
  if (days == 1) return 'Morgen';
  return 'In $days Tagen';
}

String _weekdayShort(int value) => const [
      'Mo',
      'Di',
      'Mi',
      'Do',
      'Fr',
      'Sa',
      'So',
    ][value - 1];

String _weekdayLong(int value) => const [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ][value - 1];

String _month(int value) => const [
      'JAN',
      'FEB',
      'MÄR',
      'APR',
      'MAI',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OKT',
      'NOV',
      'DEZ',
    ][value - 1];

String _monthLong(int value) => const [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ][value - 1];
