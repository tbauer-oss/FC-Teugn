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
              const SizedBox(height: 12),
              const _SectionTitle(
                title: 'Mannschaft verwalten',
                subtitle: 'Alles, was deine eigene Mannschaft betrifft.',
              ),
              const SizedBox(height: 7),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context)
                      .scale(1)
                      .clamp(1.0, 2.0)
                      .toDouble();
                  final useCompactRows = constraints.maxWidth < 350 ||
                      (constraints.maxWidth < 560 && textScale > 1.35);
                  final columns = constraints.maxWidth >= 980
                      ? 4
                      : useCompactRows
                          ? 1
                          : 2;
                  final gap = constraints.maxWidth < 560 ? 8.0 : 12.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final height = useCompactRows
                      ? 108.0 + (textScale - 1) * 108
                      : constraints.maxWidth < 560
                          ? 134.0 + (textScale - 1) * 46
                          : 118.0 + (textScale - 1) * 34;
                  final actions = [
                    _TeamAction(
                      key: const ValueKey('team-action-players'),
                      icon: Icons.badge_rounded,
                      title: 'Spieler & Kader',
                      subtitle: 'Profile, Nummern und Positionen',
                      horizontal: useCompactRows,
                      onTap: () => context.go('/trainer/players'),
                    ),
                    _TeamAction(
                      key: const ValueKey('team-action-lineup'),
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Stammformation',
                      subtitle: team.defaultLineup == null
                          ? 'Jetzt festlegen'
                          : '${team.defaultLineup!.formation} · ${team.defaultLineup!.positions.length} Spieler',
                      emphasized: true,
                      horizontal: useCompactRows,
                      onTap: () => _openDefaultLineup(context, ref, team),
                    ),
                    _TeamAction(
                      key: const ValueKey('team-action-data'),
                      icon: Icons.tune_rounded,
                      title: 'Teamdaten',
                      subtitle: 'Trainerteam, Zeiten und Einstellungen',
                      horizontal: useCompactRows,
                      onTap: () => context.go('/trainer/organization'),
                    ),
                    _TeamAction(
                      key: const ValueKey('team-action-operations'),
                      icon: Icons.inventory_2_outlined,
                      title: 'Aufgaben & Material',
                      subtitle: 'Organisation im Teamalltag',
                      horizontal: useCompactRows,
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
                          height: height,
                          child: action,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const _SectionTitle(
                title: 'Training & Spielbetrieb',
                subtitle: 'Planung und sportlicher Betrieb.',
              ),
              const SizedBox(height: 7),
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
          color: context.appColors.brandSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.yellow),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: context.appWarning),
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
      padding: EdgeInsets.all(compact ? 12 : 20),
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
            width: compact ? 42 : 58,
            height: compact ? 42 : 58,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: AppColors.black,
              size: 25,
            ),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.isPlayingCommunity ? team.playingName : team.displayName,
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
                    if (team.isPlayingCommunity) team.displayName,
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
                  color: context.appColors.textMuted,
                ),
          ),
        ],
      );
}

class _TeamAction extends StatelessWidget {
  const _TeamAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
    this.horizontal = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final iconTile = Container(
      width: horizontal ? 38 : 34,
      height: horizontal ? 38 : 34,
      decoration: BoxDecoration(
        color: emphasized ? AppColors.yellow : context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: 19,
        color: emphasized ? AppColors.black : context.appColors.text,
      ),
    );
    final arrow = Icon(
      Icons.arrow_forward_rounded,
      size: 19,
      color: context.appColors.textMuted,
    );
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: horizontal ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appColors.textMuted,
            fontSize: 11,
            height: 1.2,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: emphasized
            ? context.appColors.brandSoft
            : context.appColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: emphasized
                ? AppColors.yellow.withValues(alpha: .7)
                : context.appColors.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: horizontal
                ? Row(
                    children: [
                      iconTile,
                      const SizedBox(width: 10),
                      Expanded(child: labels),
                      const SizedBox(width: 6),
                      arrow,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [iconTile, const Spacer(), arrow]),
                      const SizedBox(height: 8),
                      Expanded(child: labels),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
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
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          if (compact) {
            final width = (constraints.maxWidth - 1) / 2;
            return Wrap(
              children: [
                for (var index = 0; index < links.length; index++)
                  SizedBox(
                    width: width,
                    child: _SportLink(
                      icon: links[index].$1,
                      label: links[index].$2,
                      onTap: () => context.go(links[index].$3),
                    ),
                  ),
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: context.appWarning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.appColors.textMuted,
              ),
            ],
          ),
        ),
      );
}
