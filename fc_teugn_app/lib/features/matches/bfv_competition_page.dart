import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';

Uri? buildBfvWidgetUri({
  required String teamName,
  required String? widgetTeamId,
}) {
  final normalizedId = widgetTeamId?.trim() ?? '';
  if (normalizedId.isEmpty) return null;
  return Uri.https('fcteugnapp.vercel.app', '/bfv-widget.html', {
    'teamId': normalizedId,
    'teamName': teamName,
  });
}

Uri? buildBfvTeamPageUri(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  final host = uri?.host.toLowerCase() ?? '';
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      (host != 'bfv.de' && !host.endsWith('.bfv.de'))) {
    return null;
  }
  return uri;
}

class BfvCompetitionPage extends ConsumerStatefulWidget {
  const BfvCompetitionPage({
    super.key,
    required this.staffView,
  });

  final bool staffView;

  @override
  ConsumerState<BfvCompetitionPage> createState() => _BfvCompetitionPageState();
}

class _BfvCompetitionPageState extends ConsumerState<BfvCompetitionPage> {
  String? _selectedTeamId;

  void _openInsideApp(TeamSummary team) {
    final route = Uri(
      path: '/bfv-browser',
      queryParameters: {
        'teamName': team.displayName,
        if (team.bfvTeamId?.trim().isNotEmpty == true)
          'teamId': team.bfvTeamId!.trim()
        else if (team.bfvTeamUrl?.trim().isNotEmpty == true)
          'teamUrl': team.bfvTeamUrl!.trim(),
      },
    );
    context.push(route.toString());
  }

  @override
  Widget build(BuildContext context) {
    final organization = ref.watch(organizationProvider);
    return organization.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: FilledButton.icon(
          onPressed: () => ref.invalidate(organizationProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Mannschaftsdaten erneut laden'),
        ),
      ),
      data: (value) => _buildContent(value),
    );
  }

  Widget _buildContent(OrganizationContext organization) {
    final teams = organization.teams.where((team) => team.isActive).toList()
      ..sort((a, b) {
        final ageGroup = a.ageGroup.sortOrder.compareTo(b.ageGroup.sortOrder);
        return ageGroup != 0 ? ageGroup : a.teamNumber.compareTo(b.teamNumber);
      });
    if (teams.isEmpty) {
      return const _EmptyBfvState(
        title: 'Keine Mannschaft verfügbar',
        message:
            'Für dein Konto ist aktuell keine aktive Mannschaft hinterlegt.',
      );
    }

    final fallbackId =
        teams.any((team) => team.id == organization.currentTeam.id)
            ? organization.currentTeam.id
            : teams.first.id;
    final effectiveId = teams.any((team) => team.id == _selectedTeamId)
        ? _selectedTeamId!
        : fallbackId;
    final team = teams.firstWhere((item) => item.id == effectiveId);
    final widgetUri = buildBfvWidgetUri(
      teamName: team.displayName,
      widgetTeamId: team.bfvTeamId,
    );
    final teamUri = buildBfvTeamPageUri(team.bfvTeamUrl);
    final officialUri = widgetUri ?? teamUri;
    final compact = MediaQuery.sizeOf(context).width < 680;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 20 : 30,
        compact ? 16 : 32,
        40,
      ),
      children: [
        _PageHeading(staffView: widget.staffView),
        const SizedBox(height: 18),
        _TeamPicker(
          teams: teams,
          selectedTeamId: effectiveId,
          onChanged: (id) => setState(() => _selectedTeamId = id),
        ),
        const SizedBox(height: 18),
        _OfficialBfvHero(team: team, configured: officialUri != null),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final cardWidth = stacked
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _BfvActionCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Tabelle & Ergebnisse',
                    description:
                        'Offizieller Tabellenstand, Liga-Spieltag und Partien der Gegner direkt beim BfV.',
                    buttonLabel: 'Offizielle BfV-Ansicht öffnen',
                    primary: true,
                    enabled: officialUri != null,
                    onPressed: () => _openInsideApp(team),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _BfvActionCard(
                    icon: Icons.sports_soccer_rounded,
                    title: 'Unsere Spiele',
                    description:
                        'Die selbst gepflegten FC-Teugn-Spiele, Kaderinformationen und freigegebenen Spieltage.',
                    buttonLabel: 'Zu unseren Spielen',
                    enabled: true,
                    onPressed: () => context.go(
                      widget.staffView ? '/trainer/matches' : '/parent/matches',
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (teamUri != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _openInsideApp(team),
            icon: const Icon(Icons.fullscreen_rounded),
            label: const Text('BfV-Mannschaftsseite in der App öffnen'),
          ),
        ],
        if (officialUri == null) ...[
          const SizedBox(height: 16),
          _EmptyBfvState(
            title: 'BfV-Verknüpfung fehlt',
            message: widget.staffView
                ? 'Öffne im Spielbetrieb „Liga & Gegner“ und hinterlege im Reiter „BfV“ die Mannschaftskennung oder Mannschaftsseite.'
                : 'Das Trainerteam hat für diese Mannschaft noch keine offizielle BfV-Verknüpfung hinterlegt.',
          ),
        ],
        const SizedBox(height: 18),
        const _OfficialDataNotice(),
      ],
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.staffView});

  final bool staffView;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tabelle & Ergebnisse',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  staffView
                      ? 'Offizielle BfV-Daten und eigene Spieltage sauber getrennt an einem Ort.'
                      : 'Alle offiziellen Liga-Informationen der ausgewählten Mannschaft auf einen Blick.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.appColors.textMuted,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.verified_rounded, color: context.appWarning),
        ],
      );
}

class _TeamPicker extends StatelessWidget {
  const _TeamPicker({
    required this.teams,
    required this.selectedTeamId,
    required this.onChanged,
  });

  final List<TeamSummary> teams;
  final String selectedTeamId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: ValueKey(selectedTeamId),
        initialValue: selectedTeamId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Mannschaft auswählen',
          prefixIcon: Icon(Icons.groups_rounded),
        ),
        items: [
          for (final team in teams)
            DropdownMenuItem(
              value: team.id,
              child: Text(
                team.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      );
}

class _OfficialBfvHero extends StatelessWidget {
  const _OfficialBfvHero({required this.team, required this.configured});

  final TeamSummary team;
  final bool configured;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF171A18), Color(0xFF514A00)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.yellow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.sports_score_rounded,
                color: AppColors.black,
                size: 29,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    configured
                        ? 'Mit offizieller BfV-Ansicht verbunden'
                        : 'Noch nicht mit dem BfV verbunden',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _BfvActionCard extends StatelessWidget {
  const _BfvActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.enabled,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final bool enabled;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.appColors.brandSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: context.appWarning),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(description),
              const SizedBox(height: 18),
              if (primary)
                FilledButton.icon(
                  onPressed: enabled ? onPressed : null,
                  icon: const Icon(Icons.fullscreen_rounded),
                  label: Text(buttonLabel, textAlign: TextAlign.center),
                )
              else
                OutlinedButton.icon(
                  onPressed: enabled ? onPressed : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(buttonLabel, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      );
}

class _EmptyBfvState extends StatelessWidget {
  const _EmptyBfvState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.appColors.brandSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.appWarning.withValues(alpha: .18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: context.appWarning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      );
}

class _OfficialDataNotice extends StatelessWidget {
  const _OfficialDataNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 21),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Tabelle, Gegnerpartien und amtliche Ergebnisse werden direkt '
                'vom Bayerischen Fußball-Verband geladen. Eigene App-Spiele '
                'bleiben davon getrennt und können weiterhin selbst gepflegt werden.',
              ),
            ),
          ],
        ),
      );
}
