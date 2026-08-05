import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/providers.dart';
import '../organization/team_default_lineup_dialog.dart';
import '../shared/page_scaffold.dart';

class TrainerTeamPage extends ConsumerWidget {
  const TrainerTeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organization = ref.watch(organizationProvider);
    final allPlayers = ref.watch(playersProvider);

    return PageScaffold(
      title: 'Meine Mannschaft',
      subtitle: 'Spieler, Stammformation und Teamorganisation an einem Ort.',
      denseMobileHeader: true,
      child: organization.when(
        loading: () => const Center(
          child: LogoLoadingPanel(message: 'Mannschaft wird geladen …'),
        ),
        error: (_, __) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Mannschaft nicht erreichbar',
          message: 'Die Teamdaten konnten gerade nicht geladen werden.',
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(organizationProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut laden'),
          ),
        ),
        data: (organization) {
          final team = organization.currentTeam;
          final teamPlayers = (allPlayers.valueOrNull ?? const <PlayerModel>[])
              .where((player) => player.teamId == team.id)
              .toList();
          final activePlayers = teamPlayers
              .where(
                (player) =>
                    player.status == PlayerStatus.active ||
                    player.status == PlayerStatus.injured,
              )
              .length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TeamHero(
                team: team,
                playerCount: allPlayers.isLoading || allPlayers.hasError
                    ? null
                    : activePlayers,
              ),
              if (allPlayers.hasError) ...[
                const SizedBox(height: 12),
                _TeamPlayerLoadFailure(
                  onRetry: () => ref.invalidate(playersProvider),
                ),
              ],
              const SizedBox(height: 18),
              const _SectionTitle(
                title: 'Mannschaft verwalten',
                subtitle: 'Alles, was deine eigene Mannschaft betrifft.',
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 980
                      ? 4
                      : constraints.maxWidth >= 560
                          ? 2
                          : 2;
                  final gap = constraints.maxWidth < 560 ? 10.0 : 14.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final actions = [
                    _TeamAction(
                      icon: Icons.badge_rounded,
                      title: 'Spieler & Kader',
                      subtitle: 'Profile, Nummern und Positionen',
                      onTap: () => context.go('/trainer/players'),
                    ),
                    _TeamAction(
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Stammformation',
                      subtitle: team.defaultLineup == null
                          ? 'Jetzt festlegen'
                          : '${team.defaultLineup!.formation} · ${team.defaultLineup!.positions.length} Spieler',
                      emphasized: true,
                      onTap: () => _openDefaultLineup(context, ref, team),
                    ),
                    _TeamAction(
                      icon: Icons.tune_rounded,
                      title: 'Teamdaten',
                      subtitle: 'Trainerteam, Zeiten und Einstellungen',
                      onTap: () => context.go('/trainer/organization'),
                    ),
                    _TeamAction(
                      icon: Icons.inventory_2_outlined,
                      title: 'Aufgaben & Material',
                      subtitle: 'Organisation im Teamalltag',
                      onTap: () => context.go('/trainer/operations'),
                    ),
                  ];
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width: width,
                          height: constraints.maxWidth < 560 ? 138 : 126,
                          child: action,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const _SectionTitle(
                title: 'Training & Spieltag',
                subtitle: 'Planung und sportlicher Betrieb.',
              ),
              const SizedBox(height: 10),
              _SportLinks(team: team),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDefaultLineup(
    BuildContext context,
    WidgetRef ref,
    TeamSummary team,
  ) async {
    try {
      final allPlayers = await ref.read(playersProvider.future);
      final players = allPlayers
          .where(
            (player) =>
                player.teamId == team.id &&
                (player.status == PlayerStatus.active ||
                    player.status == PlayerStatus.injured),
          )
          .toList()
        ..sort((a, b) {
          final byNumber =
              (a.shirtNumber ?? 999).compareTo(b.shirtNumber ?? 999);
          return byNumber != 0 ? byNumber : a.fullName.compareTo(b.fullName);
        });
      if (!context.mounted) return;
      if (players.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Lege zuerst aktive Spieler für diese Mannschaft an.'),
          ),
        );
        return;
      }

      final draft = await showDialog<TeamDefaultLineupDraft>(
        context: context,
        builder: (_) => TeamDefaultLineupDialog(team: team, players: players),
      );
      if (draft == null) return;
      await ref.read(repositoryProvider).saveTeamDefaultLineup(
            teamId: team.id,
            formation: draft.formation,
            positions: draft.positions,
            customFormations: draft.customFormations,
            formationTemplates: draft.formationTemplates,
          );
      ref.invalidate(organizationProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stammformation ${draft.formation} gespeichert.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stammformation konnte nicht gespeichert werden.'),
          ),
        );
      }
    }
  }
}

class _TeamPlayerLoadFailure extends StatelessWidget {
  const _TeamPlayerLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.yellowSoft.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.yellow),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.gold),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Spielerdaten momentan nicht erreichbar. Mannschaftsverwaltung und Navigation bleiben verfügbar.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Spieler erneut laden',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
}

class _TeamHero extends StatelessWidget {
  const _TeamHero({required this.team, required this.playerCount});

  final TeamSummary team;
  final int? playerCount;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A18), Color(0xFF3B3600)],
        ),
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 48 : 58,
            height: compact ? 48 : 58,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: AppColors.black,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    '${playerCount ?? '–'} Spieler',
                    team.gameFormat.strength,
                    team.seasonName,
                  ].join(' · '),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .68),
                    fontSize: compact ? 12 : 13,
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            _HeroBadge(
              label: team.defaultLineup?.formation ?? 'Offen',
              caption: 'Stammformation',
            ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.yellow,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              caption,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
          ),
        ],
      );
}

class _TeamAction extends StatelessWidget {
  const _TeamAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Material(
        color: emphasized ? AppColors.yellowSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: emphasized
                ? AppColors.yellow.withValues(alpha: .7)
                : AppColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: emphasized
                            ? AppColors.yellow
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 21, color: AppColors.black),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 19,
                      color: AppColors.muted,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SportLinks extends StatelessWidget {
  const _SportLinks({required this.team});

  final TeamSummary team;

  @override
  Widget build(BuildContext context) {
    final links = [
      (Icons.calendar_month_rounded, 'Kalender', '/trainer/events'),
      (Icons.fitness_center_rounded, 'Training', '/trainer/training'),
      (Icons.sports_soccer_rounded, 'Spiele', '/trainer/matches'),
      (Icons.query_stats_rounded, 'Auswertung', '/trainer/statistics'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 560;
          if (vertical) {
            return Column(
              children: [
                for (var index = 0; index < links.length; index++) ...[
                  _SportLink(
                    icon: links[index].$1,
                    label: links[index].$2,
                    onTap: () => context.go(links[index].$3),
                  ),
                  if (index < links.length - 1)
                    const Divider(height: 1, indent: 56),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < links.length; index++) ...[
                Expanded(
                  child: _SportLink(
                    icon: links[index].$1,
                    label: links[index].$2,
                    onTap: () => context.go(links[index].$3),
                  ),
                ),
                if (index < links.length - 1)
                  const SizedBox(height: 44, child: VerticalDivider()),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SportLink extends StatelessWidget {
  const _SportLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.gold),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      );
}
