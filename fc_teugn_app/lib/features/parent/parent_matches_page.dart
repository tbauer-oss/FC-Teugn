import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/providers.dart';
import '../../core/widgets/team_crest.dart';
import '../calendar/tournament_plan_browser_page.dart';
import '../shared/page_scaffold.dart';

class ParentMatchesPage extends ConsumerWidget {
  const ParentMatchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(matchEventsProvider);
    return PageScaffold(
      title: 'Spiele',
      subtitle: 'Spielplan, Treffpunkt und Ergebnisse der Mannschaft.',
      child: events.when(
        data: (items) {
          final matches = items
              .where(
                (event) =>
                    event.type == EventType.match &&
                    event.parentTournamentId == null,
              )
              .toList()
            ..sort((a, b) => b.startAt.compareTo(a.startAt));
          if (matches.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_soccer_rounded,
              title: 'Noch keine Spiele',
              message:
                  'Sobald das Trainerteam einen Spieltag plant, erscheint er hier.',
            );
          }
          return Column(
            children: [
              for (final match in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: match.category.isTournament
                      ? _PublicTournamentCard(
                          event: match,
                          onOpenFixture: (fixtureId) =>
                              context.push('/parent/matches/$fixtureId'),
                        )
                      : _PublicMatchCard(
                          event: match,
                          onOpen: () =>
                              context.push('/parent/matches/${match.id}'),
                        ),
                ),
            ],
          );
        },
        loading: () => const Center(
          child: LogoLoadingPanel(message: 'Spiele werden geladen …'),
        ),
        error: (_, __) => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Spielplan nicht erreichbar',
          message: 'Bitte versuche es in einem Moment erneut.',
        ),
      ),
    );
  }
}

class _PublicTournamentCard extends StatelessWidget {
  const _PublicTournamentCard({
    required this.event,
    required this.onOpenFixture,
  });

  final EventModel event;
  final ValueChanged<String> onOpenFixture;

  @override
  Widget build(BuildContext context) {
    final date = event.startAt.toLocal();
    final fixtures = event.tournamentFixtures;
    final tournamentPlan = event.meinTurnierplanAttachment;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.navy, AppColors.gold],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.yellow,
                  size: 34,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${event.category.label} · ${date.day}.${date.month}.${date.year}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (event.location.trim().isNotEmpty)
                        Text(
                          event.location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    '${fixtures.length} ${fixtures.length == 1 ? 'Partie' : 'Partien'}',
                  ),
                ),
              ],
            ),
          ),
          if (tournamentPlan != null &&
              isMeinTurnierplanUrl(tournamentPlan.url))
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: ValueKey('parent-tournament-plan-${event.id}'),
                  onPressed: () => openTournamentPlanBrowser(
                    context,
                    url: tournamentPlan.url,
                    tournamentName: event.title,
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('Live-Turnierplan öffnen'),
                ),
              ),
            ),
          if (fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.schedule_rounded),
                title: Text('Turnierpartien werden vorbereitet'),
                subtitle: Text(
                  'Sobald das Trainerteam einzelne Partien freigibt, erscheinen sie hier.',
                ),
              ),
            )
          else
            for (var index = 0; index < fixtures.length; index++) ...[
              _PublicTournamentFixtureTile(
                fixture: fixtures[index],
                onOpen: () => onOpenFixture(fixtures[index].id),
              ),
              if (index < fixtures.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _PublicTournamentFixtureTile extends StatelessWidget {
  const _PublicTournamentFixtureTile({
    required this.fixture,
    required this.onOpen,
  });

  final TournamentFixtureModel fixture;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final details = fixture.matchDetails;
    final time = fixture.startAt.toLocal();
    final hasResult = details?.ourGoals != null && details?.theirGoals != null;
    final score = hasResult
        ? '${details!.ourGoals}:${details.theirGoals}'
        : '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      leading: TeamCrest.opponent(
        size: 38,
        logoUrl: details?.opponentLogoUrl,
      ),
      title: Text(
        details?.opponent ?? 'Gegner noch offen',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(hasResult ? 'Ergebnis' : 'Anstoß'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            score,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: onOpen,
    );
  }
}

class _PublicMatchCard extends StatelessWidget {
  const _PublicMatchCard({required this.event, required this.onOpen});

  final EventModel event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final details = event.matchDetails;
    final date = event.startAt.toLocal();
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final result = details?.ourGoals != null &&
                  details?.theirGoals != null
              ? '${details!.ourGoals} : ${details.theirGoals}'
              : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          final opponent = details?.opponent ?? event.title;
          final teams = compact
              ? Column(
                  children: [
                    Text(
                      event.ownTeamName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(result,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 5),
                    Text(
                      opponent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.ownTeamName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Text(
                      result,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Expanded(
                      child: Text(
                        opponent,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                );
          return Padding(
            padding: EdgeInsets.all(compact ? 16 : 20),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text(details?.competition ?? 'Spiel')),
                    Text('${date.day}.${date.month}.${date.year}'),
                  ],
                ),
                SizedBox(height: compact ? 14 : 18),
                teams,
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        event.location.trim().isEmpty
                            ? 'Ort noch offen'
                            : event.location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                if (event.meetingAt != null ||
                    event.meetingLocation?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            if (event.meetingAt != null)
                              'Treffpunkt ${event.meetingAt!.hour.toString().padLeft(2, '0')}:${event.meetingAt!.minute.toString().padLeft(2, '0')} Uhr',
                            if (event.meetingLocation?.trim().isNotEmpty ==
                                true)
                              event.meetingLocation!.trim(),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.stadium_rounded),
                    label: const Text('Spieltag öffnen'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
