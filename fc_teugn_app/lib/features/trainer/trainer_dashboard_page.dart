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
import '../shared/attendance_reminder_action.dart';
import '../shared/page_scaffold.dart';
import '../shared/dashboard_notifications.dart';
import '../shared/dashboard_event_navigation.dart';
import '../shared/family_responses.dart';

class TrainerDashboardPage extends ConsumerWidget {
  const TrainerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final user = ref.watch(authProvider).user;
    final dashboard = ref.watch(trainerDashboardSummaryProvider);
    final approvals = visiblePendingUsers(
      ref.watch(pendingUsersProvider),
      ref.watch(dismissedPendingRegistrationIdsProvider),
    );
    final organization = ref.watch(organizationProvider).valueOrNull;
    final notifications = dashboard.valueOrNull?.notifications ?? const [];
    final personalResponseEventIds = ref
            .watch(personalResponsesProvider)
            .valueOrNull
            ?.map((response) => response.eventId)
            .toSet() ??
        const <String>{};
    String eventRoute(EventModel event) => dashboardEventRoute(
          event: event,
          isTrainer: true,
          personalResponseEventIds: personalResponseEventIds,
        );
    final team = organization?.currentTeam;
    final teamId = team?.id;
    final contextTeamIds = organization?.workingContext.teamIds.toSet() ??
        {if (teamId != null) teamId};
    final teamOperations = teamId == null
        ? null
        : ref.watch(teamOperationsProvider(teamId)).valueOrNull;

    final teamPlayers = (dashboard.valueOrNull?.players ??
            const <PlayerModel>[])
        .where((player) =>
            contextTeamIds.isEmpty || contextTeamIds.contains(player.teamId))
        .toList();
    final activePlayers = teamPlayers
        .where((player) => player.status == PlayerStatus.active)
        .length;
    final injuredPlayers = teamPlayers
        .where((player) => player.status == PlayerStatus.injured)
        .length;

    final eventItems = dashboardEventsForContext(
      dashboard.valueOrNull?.events ?? const <EventModel>[],
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
    final todayTrainings = todaysTrainingsForDashboard(
      eventItems,
      contextTeamIds,
      now,
    );
    final todayTrainingIds = todayTrainings.map((event) => event.id).toSet();
    final upcomingAfterToday = upcoming
        .where((event) => !todayTrainingIds.contains(event.id))
        .toList();
    final nextEvent = upcomingAfterToday.firstOrNull;
    final nextTrainings = nextTrainingsByTeamForDashboard(
      upcomingAfterToday,
      contextTeamIds,
    );
    final nextTrainingIds = nextTrainings.map((event) => event.id).toSet();
    final nextEventHero =
        nextEvent != null && !nextTrainingIds.contains(nextEvent.id)
            ? nextEvent
            : null;
    final nextEvents = upcomingAfterToday
        .where(
          (event) =>
              !nextTrainingIds.contains(event.id) &&
              event.id != nextEventHero?.id,
        )
        .take(4)
        .toList();
    final nextMatch =
        upcoming.where((event) => event.type == EventType.match).firstOrNull;
    final approvalCount = approvals.valueOrNull?.length ?? 0;
    final overdueTasks =
        teamOperations?.tasks.where((task) => task.isOverdue).toList() ??
            const <TeamTaskModel>[];
    final openTasks =
        teamOperations?.tasks.where((task) => !task.isDone).toList() ??
            const <TeamTaskModel>[];
    final priorities = _priorities(
      nextEvent: nextEvent,
      approvals: approvalCount,
      overdueTasks: overdueTasks,
      openTasks: openTasks,
      now: now,
      eventRoute: eventRoute,
    );
    final compactDashboard = MediaQuery.sizeOf(context).width < 600;
    final sectionGap = compactDashboard ? 8.0 : 12.0;

    return PageScaffold(
      title: '${_greeting(now)}, ${_firstName(user?.name)}',
      subtitle: '${_germanDate(now)} · '
          '${organization?.workingContext.includeAllTeams == true ? '${team?.ageGroup.name ?? 'Jugend'} · Alle Mannschaften' : team?.displayName ?? 'Meine Mannschaft'}',
      denseMobileHeader: true,
      headerAction: DashboardNotificationBell(
        notifications: notifications,
        isTrainer: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrainerCockpitBanner(
            teamLabel: organization?.workingContext.includeAllTeams == true
                ? '${team?.ageGroup.name ?? 'Jugend'} · Alle Mannschaften'
                : team?.displayName ?? 'Trainerteam',
            activePlayers: activePlayers,
            trainingCount: todayTrainings.length + nextTrainings.length,
            hasUpcomingMatch: nextMatch != null,
          ),
          SizedBox(height: sectionGap),
          if (organization?.can('MANAGE_MEMBERS') == true) ...[
            AdminMemberRequestsCard(
              pending: approvals,
              onOpen: () => context.go('/trainer/approvals'),
              onRefresh: () => ref.invalidate(pendingUsersProvider),
            ),
            SizedBox(height: sectionGap),
          ],
          if (user?.canUsePersonalResponses == true) ...[
            const PersonalResponsesCard(isTrainer: true),
            SizedBox(height: sectionGap),
          ],
          if (todayTrainings.isNotEmpty) ...[
            _TodayTrainingsStrip(
              events: todayTrainings,
              players: teamPlayers,
              teamLabel: (event) => _eventTeamLabel(event, organization),
              onOpen: () => _showCombinedTrainingResponses(
                context,
                todayTrainings,
                teamPlayers,
              ),
            ),
            SizedBox(height: sectionGap),
          ],
          if (nextTrainings.isNotEmpty) ...[
            _NextTrainingsOverview(
              events: nextTrainings,
              players: teamPlayers,
              teamLabel: (event) => _eventTeamLabel(event, organization),
              onPlan: (event) => context.push(eventRoute(event)),
            ),
            SizedBox(height: sectionGap),
          ],
          if (nextEventHero != null) ...[
            _NextEventHero(
              event: nextEventHero,
              now: now,
              eventRoute: eventRoute,
            ),
            SizedBox(height: sectionGap),
          ],
          _StatusGrid(
            playersLoading: dashboard.isLoading,
            playersError: dashboard.hasError,
            activePlayers: activePlayers,
            injuredPlayers: injuredPlayers,
            nextTrainings: nextTrainings,
            players: teamPlayers,
            nextMatch: nextMatch,
            onOpenResponses: nextTrainings.isEmpty
                ? () => context.go('/trainer/events')
                : () => _showCombinedTrainingResponses(
                      context,
                      nextTrainings,
                      teamPlayers,
                    ),
            onOpenNextMatch: nextMatch == null
                ? () => context.go('/trainer/matches')
                : () => context.push(eventRoute(nextMatch)),
            onRetryPlayers: () =>
                ref.invalidate(trainerDashboardSummaryProvider),
          ),
          if (dashboard.hasError) ...[
            const SizedBox(height: 10),
            _PlayerLoadFailure(
              onRetry: () => ref.invalidate(trainerDashboardSummaryProvider),
            ),
          ],
          SizedBox(height: sectionGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final priorityCard = _PriorityCard(items: priorities);
              final agendaCard = _AgendaCard(
                events: nextEvents,
                eventRoute: eventRoute,
              );
              if (constraints.maxWidth < 780) {
                return Column(
                  children: [
                    priorityCard,
                    SizedBox(height: sectionGap),
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
          SizedBox(height: sectionGap),
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

  String _eventTeamLabel(
    EventModel event,
    OrganizationContext? organization,
  ) {
    final eventTeamIds = {
      event.teamId,
      ...event.targetTeams.map((team) => team.id),
    };
    final organizationLabels = organization?.teams
            .where((team) => eventTeamIds.contains(team.id))
            .map((team) => team.displayName)
            .toSet()
            .toList() ??
        const <String>[];
    if (organizationLabels.isNotEmpty) {
      return organizationLabels.join(' · ');
    }
    final targetLabels = event.targetTeams
        .map(
          (team) => team.ageGroupCode.isEmpty
              ? team.name
              : '${team.ageGroupCode}-Jugend',
        )
        .toSet()
        .toList();
    return targetLabels.isEmpty ? 'Mannschaft' : targetLabels.join(' · ');
  }

  List<_DashboardPriority> _priorities({
    required EventModel? nextEvent,
    required int approvals,
    required List<TeamTaskModel> overdueTasks,
    required List<TeamTaskModel> openTasks,
    required DateTime now,
    required String Function(EventModel event) eventRoute,
  }) {
    final items = <_DashboardPriority>[];
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
          route: eventRoute(nextMatch),
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
    return items;
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

class _TrainerCockpitBanner extends StatelessWidget {
  const _TrainerCockpitBanner({
    required this.teamLabel,
    required this.activePlayers,
    required this.trainingCount,
    required this.hasUpcomingMatch,
  });

  final String teamLabel;
  final int activePlayers;
  final int trainingCount;
  final bool hasUpcomingMatch;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF111410), Color(0xFF423B00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.yellow,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.dashboard_customize_rounded,
                color: AppColors.black,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TRAINER-COCKPIT',
                    style: TextStyle(
                      color: AppColors.yellow,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    teamLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _CockpitChip(
                        icon: Icons.groups_rounded,
                        label: 'Spieler: $activePlayers',
                      ),
                      _CockpitChip(
                        icon: Icons.sports_rounded,
                        label: 'Trainings: $trainingCount',
                      ),
                      if (hasUpcomingMatch)
                        const _CockpitChip(
                          icon: Icons.sports_soccer_rounded,
                          label: 'Spiel bereit',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CockpitChip extends StatelessWidget {
  const _CockpitChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.yellow),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
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

class _TodayTrainingsStrip extends StatelessWidget {
  const _TodayTrainingsStrip({
    required this.events,
    required this.players,
    required this.teamLabel,
    required this.onOpen,
  });

  final List<EventModel> events;
  final List<PlayerModel> players;
  final String Function(EventModel event) teamLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final counts = combinedTrainingDashboardCounts(events, players);
    final labels = events.map(teamLabel).toSet().toList();
    final times = events
        .map((event) =>
            '${event.startAt.hour.toString().padLeft(2, '0')}:${event.startAt.minute.toString().padLeft(2, '0')} Uhr')
        .toSet()
        .join(' + ');
    return Material(
      key: const ValueKey('today-training-summary'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.success.withValues(alpha: .10),
                AppColors.yellowSoft.withValues(alpha: .30),
              ],
            ),
            border: Border.all(
              color: AppColors.success.withValues(alpha: .24),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .84),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.today_rounded,
                  color: AppColors.success,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Heute · ${labels.join(' + ')} · $times',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        _InlineTodayCount(
                          icon: Icons.check_circle_rounded,
                          count: counts.yes,
                          label: 'zu',
                          color: AppColors.success,
                        ),
                        _InlineTodayCount(
                          icon: Icons.cancel_rounded,
                          count: counts.no,
                          label: 'ab',
                          color: Colors.redAccent,
                        ),
                        _InlineTodayCount(
                          icon: Icons.schedule_rounded,
                          count: counts.open,
                          label: 'offen',
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.people_alt_rounded, color: AppColors.gold),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineTodayCount extends StatelessWidget {
  const _InlineTodayCount({
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            '$count $label',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
}

class _NextTrainingsOverview extends StatelessWidget {
  const _NextTrainingsOverview({
    required this.events,
    required this.players,
    required this.teamLabel,
    required this.onPlan,
  });

  final List<EventModel> events;
  final List<PlayerModel> players;
  final String Function(EventModel event) teamLabel;
  final void Function(EventModel event) onPlan;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final counts = combinedTrainingDashboardCounts(events, players);
    final labels = events.map(teamLabel).toSet().toList();
    final sameSchedule = events.every(
      (event) =>
          event.startAt == events.first.startAt &&
          event.location.trim() == events.first.location.trim(),
    );
    return Card(
      key: const ValueKey('next-training-overview'),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.yellowSoft.withValues(alpha: .20),
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 9 : 12,
            compact ? 10 : 14,
            compact ? 8 : 11,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 32 : 36,
                    height: compact ? 32 : 36,
                    decoration: BoxDecoration(
                      color: AppColors.yellowSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.sports_rounded, size: 19),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nächstes Training',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          labels.join(' + '),
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
                  if (events.length > 1)
                    _TrainingTeamCount(count: events.length),
                ],
              ),
              SizedBox(height: compact ? 6 : 8),
              if (sameSchedule)
                _TrainingScheduleLine(
                  event: events.first,
                  teamLabel: labels.join(' + '),
                )
              else
                for (final event in events)
                  _TrainingScheduleLine(
                    event: event,
                    teamLabel: teamLabel(event),
                  ),
              SizedBox(height: compact ? 6 : 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _TrainingResponseMetric(
                    icon: Icons.check_circle_rounded,
                    label: 'Zugesagt',
                    value: counts.yes,
                    color: AppColors.success,
                  ),
                  _TrainingResponseMetric(
                    icon: Icons.cancel_rounded,
                    label: 'Abgesagt',
                    value: counts.no,
                    color: Colors.redAccent,
                  ),
                  _TrainingResponseMetric(
                    icon: Icons.schedule_rounded,
                    label: 'Offen',
                    value: counts.open,
                    color: AppColors.muted,
                  ),
                  _TrainingResponseMetric(
                    icon: Icons.groups_rounded,
                    label: 'Gesamt',
                    value: counts.total,
                    color: AppColors.blue,
                  ),
                ],
              ),
              SizedBox(height: compact ? 7 : 9),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('all-training-responses'),
                      onPressed: () => _showCombinedTrainingResponses(
                        context,
                        events,
                        players,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.yellowSoft,
                        foregroundColor: AppColors.gold,
                        padding:
                            EdgeInsets.symmetric(vertical: compact ? 8 : 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.groups_rounded, size: 18),
                      label: const Text(
                        'Rückmeldungen',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  OutlinedButton.icon(
                    key: const ValueKey('next-training-planning'),
                    onPressed: () => _openTrainingPlanning(
                      context,
                      events,
                      teamLabel,
                      onPlan,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 9 : 12,
                        vertical: compact ? 8 : 10,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                    label: const Text('Planung'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingTeamCount extends StatelessWidget {
  const _TrainingTeamCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.yellowSoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$count Mannschaften',
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _TrainingScheduleLine extends StatelessWidget {
  const _TrainingScheduleLine({required this.event, required this.teamLabel});
  final EventModel event;
  final String teamLabel;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('next-training-overview-${event.id}'),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.yellowSoft,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                teamLabel,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${_shortDate(event.startAt)} · ${_time(event.startAt)} Uhr'
                '${event.location.trim().isEmpty ? '' : ' · ${event.location.trim()}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

void _openTrainingPlanning(
  BuildContext context,
  List<EventModel> events,
  String Function(EventModel event) teamLabel,
  void Function(EventModel event) onPlan,
) {
  if (events.length == 1) {
    onPlan(events.first);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Training planen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Wähle die Mannschaft, deren Trainingsplan du öffnen möchtest.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (final event in events)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text(teamLabel(event)),
              subtitle: Text(
                  '${_shortDate(event.startAt)} · ${_time(event.startAt)} Uhr'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(sheetContext);
                onPlan(event);
              },
            ),
        ],
      ),
    ),
  );
}

List<PlayerModel> _eventRoster(
  EventModel event,
  List<PlayerModel> players,
) {
  final teamIds = {
    event.teamId,
    ...event.targetTeams.map((team) => team.id),
  };
  final excludedPlayerIds = event.excludedParticipantPlayerIds.toSet();
  final requestedPlayerIds = event.participantPlayerIds.toSet();
  return players
      .where(
        (player) =>
            player.status == PlayerStatus.active &&
            player.teamId != null &&
            teamIds.contains(player.teamId) &&
            !excludedPlayerIds.contains(player.id) &&
            (requestedPlayerIds.isEmpty ||
                requestedPlayerIds.contains(player.id)),
      )
      .toList();
}

void _showCombinedTrainingResponses(
  BuildContext context,
  List<EventModel> events,
  List<PlayerModel> players,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _CombinedTrainingResponsesSheet(
      events: events,
      players: players,
    ),
  );
}

typedef _TrainingResponseEntry = ({
  String eventId,
  String playerId,
  String name,
  String? reason,
  String team,
  AttendanceStatus status,
  bool canManage,
});

typedef _TrainingResponseGroups = ({
  List<_TrainingResponseEntry> yes,
  List<_TrainingResponseEntry> no,
  List<_TrainingResponseEntry> open,
});

String _compactTeamLabel(
  String? teamId,
  EventModel event,
  OrganizationContext? organization,
) {
  TeamSummary? organizationTeam;
  for (final team in organization?.teams ?? const <TeamSummary>[]) {
    if (team.id == teamId) {
      organizationTeam = team;
      break;
    }
  }
  if (organizationTeam != null) {
    final direct = organizationTeam.name.trim();
    final match = RegExp(
      r'([A-ZÄÖÜ]+)\s*[- ]?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(direct);
    if (match != null) {
      return '${match.group(1)}${match.group(2)}'.toUpperCase();
    }
    return '${organizationTeam.ageGroup.code}${organizationTeam.teamNumber}'
        .toUpperCase();
  }
  for (final team in event.targetTeams) {
    if (team.id != teamId) continue;
    final code = team.ageGroupCode.trim();
    if (code.isNotEmpty) return code.toUpperCase();
    if (team.name.trim().isNotEmpty) return team.name.trim();
  }
  return 'Team';
}

String _eventCompactTeamLabels(
  EventModel event,
  OrganizationContext? organization,
) {
  final teamIds = <String>{
    event.teamId,
    ...event.targetTeams.map((team) => team.id),
  };
  return teamIds
      .map((teamId) => _compactTeamLabel(teamId, event, organization))
      .toSet()
      .join(' + ');
}

_TrainingResponseGroups _trainingResponseGroups(
  EventModel event,
  List<PlayerModel> roster,
  List<PlayerModel> allPlayers,
  OrganizationContext? organization,
) {
  final rosterIds = roster.map((player) => player.id).toSet();
  final playersById = {for (final player in allPlayers) player.id: player};
  final visibleAttendance = event.attendance
      .where((item) => rosterIds.contains(item.playerId))
      .toList(growable: false);
  final visibleMissingAttendance = event.missingAttendance
      .where((player) => rosterIds.contains(player.id))
      .toList(growable: false);
  String teamFor(String playerId) => _compactTeamLabel(
        playersById[playerId]?.teamId ?? event.teamId,
        event,
        organization,
      );
  List<_TrainingResponseEntry> replies(AttendanceStatus status) =>
      visibleAttendance
          .where((item) => item.status == status)
          .map(
            (item) => (
              eventId: event.id,
              playerId: item.playerId,
              name: item.playerName ??
                  playersById[item.playerId]?.fullName ??
                  'Spieler',
              reason: item.reason,
              team: teamFor(item.playerId),
              status: item.status,
              canManage: event.capabilities.canManage,
            ),
          )
          .toList();
  final repliedIds = visibleAttendance
      .where((item) =>
          item.status == AttendanceStatus.yes ||
          item.status == AttendanceStatus.no)
      .map((item) => item.playerId)
      .toSet();
  final explicitOpenIds =
      visibleMissingAttendance.map((item) => item.id).toSet();
  final explicitOpen = visibleMissingAttendance
      .map(
        (item) => (
          eventId: event.id,
          playerId: item.id,
          name: item.name,
          reason: null as String?,
          team: teamFor(item.id),
          status: AttendanceStatus.unknown,
          canManage: event.capabilities.canManage,
        ),
      )
      .toList();
  final open = <_TrainingResponseEntry>[
    ...explicitOpen,
    ...visibleAttendance
        .where((item) =>
            item.status == AttendanceStatus.unknown &&
            !explicitOpenIds.contains(item.playerId))
        .map(
          (item) => (
            eventId: event.id,
            playerId: item.playerId,
            name: item.playerName ??
                playersById[item.playerId]?.fullName ??
                'Spieler',
            reason: null as String?,
            team: teamFor(item.playerId),
            status: AttendanceStatus.unknown,
            canManage: event.capabilities.canManage,
          ),
        ),
    if (explicitOpen.isEmpty)
      ...roster
          .where((player) => !repliedIds.contains(player.id))
          .where((player) => !visibleAttendance.any(
                (item) =>
                    item.playerId == player.id &&
                    item.status == AttendanceStatus.unknown,
              ))
          .map(
            (player) => (
              eventId: event.id,
              playerId: player.id,
              name: player.fullName,
              reason: null as String?,
              team: teamFor(player.id),
              status: AttendanceStatus.unknown,
              canManage: event.capabilities.canManage,
            ),
          ),
  ];
  final result = (
    yes: replies(AttendanceStatus.yes),
    no: replies(AttendanceStatus.no),
    open: open,
  );
  for (final entries in [result.yes, result.no, result.open]) {
    entries.sort((a, b) {
      final byTeam = a.team.compareTo(b.team);
      return byTeam != 0 ? byTeam : a.name.compareTo(b.name);
    });
  }
  return result;
}

class _TrainingResponseMetric extends StatelessWidget {
  const _TrainingResponseMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(
              '$value $label',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      );
}

class _CombinedTrainingResponsesSheet extends ConsumerStatefulWidget {
  const _CombinedTrainingResponsesSheet({
    required this.events,
    required this.players,
  });

  final List<EventModel> events;
  final List<PlayerModel> players;

  @override
  ConsumerState<_CombinedTrainingResponsesSheet> createState() =>
      _CombinedTrainingResponsesSheetState();
}

class _CombinedTrainingResponsesSheetState
    extends ConsumerState<_CombinedTrainingResponsesSheet> {
  late List<EventModel> _events;
  final Set<String> _savingResponses = <String>{};

  @override
  void initState() {
    super.initState();
    _events = [...widget.events];
  }

  String _responseKey(_TrainingResponseEntry entry) =>
      '${entry.eventId}:${entry.playerId}';

  Future<void> _setAttendance(
    _TrainingResponseEntry entry,
    AttendanceStatus status,
  ) async {
    if (status == entry.status || !entry.canManage) return;
    final key = _responseKey(entry);
    setState(() => _savingResponses.add(key));
    try {
      final updated = await ref.read(repositoryProvider).setAttendance(
            eventId: entry.eventId,
            playerId: entry.playerId,
            status: status,
          );
      if (!mounted) return;
      setState(() {
        _events = [
          for (final event in _events)
            if (event.id == updated.id) updated else event,
        ];
      });
      ref.invalidate(eventsProvider);
      ref.invalidate(calendarEventsProvider);
      ref.invalidate(trainerDashboardSummaryProvider);
      ref.invalidate(personalResponsesProvider);
      ref.invalidate(parentDashboardEventsProvider);
      ref.invalidate(parentDashboardSummaryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${entry.name}: ${status.label} gespeichert.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Rückmeldung konnte nicht geändert werden.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingResponses.remove(key));
      }
    }
  }

  Future<void> _removeParticipant(_TrainingResponseEntry entry) async {
    if (!entry.canManage) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aus Termin entfernen?'),
        content: Text(
          '${entry.name} wird nur aus diesem Termin entfernt. '
          'Mannschaft und Spielerprofil bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('confirm-remove-event-participant'),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final key = _responseKey(entry);
    setState(() => _savingResponses.add(key));
    try {
      final updated = await ref.read(repositoryProvider).removeEventParticipant(
            eventId: entry.eventId,
            playerId: entry.playerId,
          );
      if (!mounted) return;
      setState(() {
        _events = [
          for (final event in _events)
            if (event.id == updated.id) updated else event,
        ];
      });
      ref.invalidate(eventsProvider);
      ref.invalidate(calendarEventsProvider);
      ref.invalidate(trainerDashboardSummaryProvider);
      ref.invalidate(personalResponsesProvider);
      ref.invalidate(parentDashboardEventsProvider);
      ref.invalidate(parentDashboardSummaryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.name} wurde aus dem Termin entfernt.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Spieler konnte nicht entfernt werden.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingResponses.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final organization = ref.watch(organizationProvider).valueOrNull;
    final yes = <_TrainingResponseEntry>[];
    final no = <_TrainingResponseEntry>[];
    final open = <_TrainingResponseEntry>[];
    for (final event in _events) {
      final groups = _trainingResponseGroups(
        event,
        _eventRoster(event, widget.players),
        widget.players,
        organization,
      );
      yes.addAll(groups.yes);
      no.addAll(groups.no);
      open.addAll(groups.open);
    }
    for (final entries in [yes, no, open]) {
      entries.sort((a, b) {
        final byTeam = a.team.compareTo(b.team);
        return byTeam != 0 ? byTeam : a.name.compareTo(b.name);
      });
    }
    final teamLabels = _events
        .expand(
          (event) => <String>{
            event.teamId,
            ...event.targetTeams.map((team) => team.id),
          }.map(
            (teamId) => _compactTeamLabel(teamId, event, organization),
          ),
        )
        .toSet()
        .toList()
      ..sort();
    final total = yes.length + no.length + open.length;
    final manageableEvents = _events
        .where(
          (event) =>
              event.capabilities.canManage &&
              event.category == EventCategory.training,
        )
        .toList();

    return FractionallySizedBox(
      key: const ValueKey('combined-training-responses-sheet'),
      heightFactor: .94,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 7),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rückmeldungen',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      Text(
                        '${teamLabels.join(' + ')} · $total Spieler',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < _events.length; index++) ...[
                      _CombinedTrainingEventBadge(
                        team: _eventCompactTeamLabels(
                          _events[index],
                          organization,
                        ),
                        event: _events[index],
                      ),
                      if (index != _events.length - 1) const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
            ),
            if (manageableEvents.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0;
                          index < manageableEvents.length;
                          index++) ...[
                        OutlinedButton.icon(
                          key: ValueKey(
                            _events.length == 1
                                ? 'trainer-training-reminder'
                                : 'trainer-training-reminder-${manageableEvents[index].id}',
                          ),
                          onPressed: () => showEventAttendanceReminder(
                            context,
                            ref,
                            manageableEvents[index],
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                          ),
                          icon: const Icon(
                            Icons.notifications_active_rounded,
                            size: 15,
                          ),
                          label: Text(
                            '${_eventCompactTeamLabels(manageableEvents[index], organization)} erinnern',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        if (index != manageableEvents.length - 1)
                          const SizedBox(width: 5),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: _FilteredTrainingResponses(
                yes: yes,
                no: no,
                open: open,
                savingResponses: _savingResponses,
                onStatusChanged: _setAttendance,
                onRemove: _removeParticipant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CombinedTrainingEventBadge extends StatelessWidget {
  const _CombinedTrainingEventBadge({required this.team, required this.event});

  final String team;
  final EventModel event;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(
          '$team · ${_shortDate(event.startAt)}, ${_time(event.startAt)} Uhr'
          '${event.location.trim().isEmpty ? '' : ' · ${event.location.trim()}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
      );
}

enum _TrainingResponseFilter { all, yes, no, open }

enum _TrainingResponseAction { unknown, yes, no, remove }

class _FilteredTrainingResponses extends StatefulWidget {
  const _FilteredTrainingResponses({
    required this.yes,
    required this.no,
    required this.open,
    required this.savingResponses,
    required this.onStatusChanged,
    required this.onRemove,
  });

  final List<_TrainingResponseEntry> yes;
  final List<_TrainingResponseEntry> no;
  final List<_TrainingResponseEntry> open;
  final Set<String> savingResponses;
  final Future<void> Function(
    _TrainingResponseEntry entry,
    AttendanceStatus status,
  ) onStatusChanged;
  final Future<void> Function(_TrainingResponseEntry entry) onRemove;

  @override
  State<_FilteredTrainingResponses> createState() =>
      _FilteredTrainingResponsesState();
}

class _FilteredTrainingResponsesState
    extends State<_FilteredTrainingResponses> {
  _TrainingResponseFilter filter = _TrainingResponseFilter.all;

  @override
  Widget build(BuildContext context) {
    final total = widget.yes.length + widget.no.length + widget.open.length;
    return Column(
      children: [
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Alle', total, _TrainingResponseFilter.all),
              _filterChip(
                'Zugesagt',
                widget.yes.length,
                _TrainingResponseFilter.yes,
              ),
              _filterChip(
                'Abgesagt',
                widget.no.length,
                _TrainingResponseFilter.no,
              ),
              _filterChip(
                'Offen',
                widget.open.length,
                _TrainingResponseFilter.open,
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: total == 0
              ? const Center(
                  child: Text(
                    'Noch keine Rückmeldungen vorhanden.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if ((filter == _TrainingResponseFilter.all ||
                            filter == _TrainingResponseFilter.yes) &&
                        widget.yes.isNotEmpty)
                      _TrainingResponseGroup(
                        title: 'Zugesagt',
                        color: AppColors.success,
                        entries: widget.yes,
                        savingResponses: widget.savingResponses,
                        onStatusChanged: widget.onStatusChanged,
                        onRemove: widget.onRemove,
                      ),
                    if ((filter == _TrainingResponseFilter.all ||
                            filter == _TrainingResponseFilter.no) &&
                        widget.no.isNotEmpty)
                      _TrainingResponseGroup(
                        title: 'Abgesagt',
                        color: Colors.redAccent,
                        entries: widget.no,
                        savingResponses: widget.savingResponses,
                        onStatusChanged: widget.onStatusChanged,
                        onRemove: widget.onRemove,
                      ),
                    if ((filter == _TrainingResponseFilter.all ||
                            filter == _TrainingResponseFilter.open) &&
                        widget.open.isNotEmpty)
                      _TrainingResponseGroup(
                        title: 'Keine Rückmeldung',
                        color: AppColors.muted,
                        entries: widget.open,
                        savingResponses: widget.savingResponses,
                        onStatusChanged: widget.onStatusChanged,
                        onRemove: widget.onRemove,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _filterChip(
    String label,
    int count,
    _TrainingResponseFilter value,
  ) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: filter == value,
          onSelected: (_) => setState(() => filter = value),
          visualDensity: VisualDensity.compact,
          label: Text('$label $count'),
        ),
      );
}

class _TrainingResponseGroup extends StatelessWidget {
  const _TrainingResponseGroup({
    required this.title,
    required this.color,
    required this.entries,
    required this.savingResponses,
    required this.onStatusChanged,
    required this.onRemove,
  });

  final String title;
  final Color color;
  final List<_TrainingResponseEntry> entries;
  final Set<String> savingResponses;
  final Future<void> Function(
    _TrainingResponseEntry entry,
    AttendanceStatus status,
  ) onStatusChanged;
  final Future<void> Function(_TrainingResponseEntry entry) onRemove;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 7),
        padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: .16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 560 ? 2 : 1;
                const gap = 5.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        width: width,
                        child: _TrainingResponsePersonChip(
                          entry: entry,
                          color: color,
                          saving: savingResponses
                              .contains('${entry.eventId}:${entry.playerId}'),
                          onStatusChanged: onStatusChanged,
                          onRemove: onRemove,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
}

class _TrainingResponsePersonChip extends StatelessWidget {
  const _TrainingResponsePersonChip({
    required this.entry,
    required this.color,
    required this.saving,
    required this.onStatusChanged,
    required this.onRemove,
  });

  final _TrainingResponseEntry entry;
  final Color color;
  final bool saving;
  final Future<void> Function(
    _TrainingResponseEntry entry,
    AttendanceStatus status,
  ) onStatusChanged;
  final Future<void> Function(_TrainingResponseEntry entry) onRemove;

  @override
  Widget build(BuildContext context) {
    final reason = entry.reason?.trim();
    return Semantics(
      label: '${entry.name}, ${entry.team}',
      container: true,
      child: Container(
        key: ValueKey('training-response-person-${entry.name}-${entry.team}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_rounded, color: color, size: 16),
            const SizedBox(width: 5),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          entry.team,
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (reason?.isNotEmpty == true)
                    Text(
                      reason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            if (entry.canManage) ...[
              const SizedBox(width: 3),
              if (saving)
                const SizedBox.square(
                  dimension: 20,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<_TrainingResponseAction>(
                  key: ValueKey(
                    'attendance-status-menu-${entry.eventId}-${entry.playerId}',
                  ),
                  tooltip: 'Status von ${entry.name} ändern',
                  padding: EdgeInsets.zero,
                  iconSize: 19,
                  onSelected: (action) {
                    if (action == _TrainingResponseAction.remove) {
                      onRemove(entry);
                      return;
                    }
                    onStatusChanged(
                      entry,
                      switch (action) {
                        _TrainingResponseAction.unknown =>
                          AttendanceStatus.unknown,
                        _TrainingResponseAction.yes => AttendanceStatus.yes,
                        _TrainingResponseAction.no => AttendanceStatus.no,
                        _TrainingResponseAction.remove =>
                          AttendanceStatus.unknown,
                      },
                    );
                  },
                  itemBuilder: (context) => [
                    for (final entryStatus in const [
                      (
                        _TrainingResponseAction.unknown,
                        AttendanceStatus.unknown
                      ),
                      (_TrainingResponseAction.yes, AttendanceStatus.yes),
                      (_TrainingResponseAction.no, AttendanceStatus.no),
                    ])
                      PopupMenuItem<_TrainingResponseAction>(
                        key: ValueKey(
                          'attendance-status-choice-${entry.eventId}-${entry.playerId}-${entryStatus.$2.apiName}',
                        ),
                        value: entryStatus.$1,
                        child: Row(
                          children: [
                            Icon(
                              entryStatus.$2 == AttendanceStatus.yes
                                  ? Icons.check_circle_rounded
                                  : entryStatus.$2 == AttendanceStatus.no
                                      ? Icons.cancel_rounded
                                      : Icons.schedule_rounded,
                              size: 18,
                              color: entryStatus.$2 == AttendanceStatus.yes
                                  ? AppColors.success
                                  : entryStatus.$2 == AttendanceStatus.no
                                      ? Colors.redAccent
                                      : AppColors.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(entryStatus.$2.label)),
                            if (entry.status == entryStatus.$2)
                              const Icon(Icons.check_rounded, size: 18),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem<_TrainingResponseAction>(
                      key: ValueKey(
                        'attendance-remove-choice-${entry.eventId}-${entry.playerId}',
                      ),
                      value: _TrainingResponseAction.remove,
                      child: const Row(
                        children: [
                          Icon(
                            Icons.person_remove_alt_1_rounded,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Aus Termin entfernen',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextEventHero extends StatelessWidget {
  const _NextEventHero({
    required this.event,
    required this.now,
    required this.eventRoute,
  });

  final EventModel? event;
  final DateTime now;
  final String Function(EventModel event) eventRoute;

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
            context.push(eventRoute(current));
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
                  ? event.category.isTournament
                      ? 'Turnier öffnen'
                      : 'Spieltag öffnen'
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
    required this.nextTrainings,
    required this.players,
    required this.nextMatch,
    required this.onOpenResponses,
    required this.onOpenNextMatch,
    required this.onRetryPlayers,
  });

  final bool playersLoading;
  final bool playersError;
  final int activePlayers;
  final int injuredPlayers;
  final List<EventModel> nextTrainings;
  final List<PlayerModel> players;
  final EventModel? nextMatch;
  final VoidCallback onOpenResponses;
  final VoidCallback onOpenNextMatch;
  final VoidCallback onRetryPlayers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 4 : 2;
          final compact = constraints.maxWidth < 600;
          final gap = compact ? 7.0 : 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          final responses =
              combinedTrainingDashboardCounts(nextTrainings, players);
          final responseValue = responses.total == 0
              ? '–'
              : '${responses.yes}/${responses.total}';
          final matchValue = nextMatch == null
              ? '–'
              : '${nextMatch!.startAt.day}.${nextMatch!.startAt.month}.';
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
              label: 'Rückmeldungen',
              value: responseValue,
              icon: Icons.how_to_reg_rounded,
              color: AppColors.success,
              onTap: onOpenResponses,
            ),
            _StatusItem(
              label: 'Nächstes Spiel',
              value: matchValue,
              icon: Icons.sports_soccer_rounded,
              color: AppColors.gold,
              onTap: onOpenNextMatch,
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(width: width, height: compact ? 70 : 78, child: item),
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
    this.route,
    this.onTap,
  }) : assert(route != null || onTap != null);

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? route;
  final VoidCallback? onTap;
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
        onTap: item.onTap ?? () => context.go(item.route!),
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
  const _AgendaCard({required this.events, required this.eventRoute});

  final List<EventModel> events;
  final String Function(EventModel event) eventRoute;

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
                    _AgendaRow(
                      event: events[index],
                      route: eventRoute(events[index]),
                    ),
                    if (index < events.length - 1)
                      const Divider(height: 1, indent: 45),
                  ],
                ],
              ),
      );
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.event, required this.route});

  final EventModel event;
  final String route;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push(route),
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

List<EventModel> dashboardEventsForContext(
  List<EventModel> stored,
  OrganizationContext? organization,
  DateTime now,
  Set<String> contextTeamIds,
) {
  final visibleStored =
      stored.where((event) => !event.isHiddenRegularOccurrence).toList();
  if (organization == null) return visibleStored;
  final result = [...visibleStored];
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
    (DateTime, DateTime, String)? next;
    for (final candidate in candidates) {
      final matching = stored.where(
        (event) =>
            event.category == EventCategory.training &&
            (event.isHiddenRegularOccurrence
                ? event.teamId == team.id
                : event.teamId == team.id ||
                    event.targetTeams.any((target) => target.id == team.id)) &&
            event.startAt.difference(candidate.$1).abs() <
                const Duration(minutes: 5),
      );
      if (matching.any(
        (event) =>
            event.isHiddenRegularOccurrence ||
            event.status == EventStatus.cancelled,
      )) {
        // This exact occurrence was deleted or cancelled for this team. The
        // exception must suppress only this date, not the following week.
        continue;
      }
      if (matching.isNotEmpty) {
        // A stored, visible occurrence is already part of the result.
        break;
      }
      next = candidate;
      break;
    }
    if (next == null) continue;
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

EventModel? nextTrainingForDashboard(Iterable<EventModel> events) {
  final trainings = events
      .where((event) => event.category == EventCategory.training)
      .toList()
    ..sort((left, right) => left.startAt.compareTo(right.startAt));
  return trainings.firstOrNull;
}

List<EventModel> todaysTrainingsForDashboard(
  Iterable<EventModel> events,
  Set<String> contextTeamIds,
  DateTime now,
) {
  final localNow = now.toLocal();
  final start = DateTime(localNow.year, localNow.month, localNow.day);
  final end = start.add(const Duration(days: 1));
  final seen = <String>{};
  final result = events.where((event) {
    if (!seen.add(event.id) ||
        event.isCancelled ||
        event.category != EventCategory.training) {
      return false;
    }
    final eventStart = event.startAt.toLocal();
    if (eventStart.isBefore(start) || !eventStart.isBefore(end)) {
      return false;
    }
    if (contextTeamIds.isEmpty) return true;
    return contextTeamIds.contains(event.teamId) ||
        event.targetTeams.any((team) => contextTeamIds.contains(team.id));
  }).toList()
    ..sort((left, right) => left.startAt.compareTo(right.startAt));
  return result;
}

List<EventModel> nextTrainingsByTeamForDashboard(
  Iterable<EventModel> events,
  Set<String> contextTeamIds,
) {
  final trainings = events
      .where((event) => event.category == EventCategory.training)
      .toList()
    ..sort((left, right) => left.startAt.compareTo(right.startAt));
  final coveredTeamIds = <String>{};
  final result = <EventModel>[];
  for (final event in trainings) {
    final eventTeamIds = {
      event.teamId,
      ...event.targetTeams.map((team) => team.id),
    }
        .where(
          (teamId) => contextTeamIds.isEmpty || contextTeamIds.contains(teamId),
        )
        .toSet();
    if (eventTeamIds.isEmpty || eventTeamIds.every(coveredTeamIds.contains)) {
      continue;
    }
    result.add(event);
    coveredTeamIds.addAll(eventTeamIds);
    if (contextTeamIds.isNotEmpty &&
        coveredTeamIds.containsAll(contextTeamIds)) {
      break;
    }
  }
  return result;
}

({int yes, int no, int open, int total}) trainingDashboardCounts(
  AttendanceSummary summary, {
  required int missingCount,
  required int rosterCount,
}) {
  final fallbackOpen =
      summary.total == 0 && missingCount == 0 ? rosterCount : 0;
  final open = summary.unknown > 0
      ? summary.unknown + summary.maybe
      : missingCount > 0
          ? missingCount + summary.maybe
          : fallbackOpen + summary.maybe;
  return (
    yes: summary.yes,
    no: summary.no,
    open: open,
    total: summary.yes + summary.no + open,
  );
}

({int yes, int no, int open, int total}) combinedTrainingDashboardCounts(
  Iterable<EventModel> events,
  List<PlayerModel> players,
) {
  var yes = 0;
  var no = 0;
  var open = 0;
  var total = 0;
  for (final event in events) {
    final roster = _eventRoster(event, players);
    final counts = trainingDashboardCounts(
      event.attendanceSummary,
      missingCount: event.missingAttendance.length,
      rosterCount: roster.length,
    );
    yes += counts.yes;
    no += counts.no;
    open += counts.open;
    total += counts.total;
  }
  return (yes: yes, no: no, open: open, total: total);
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
