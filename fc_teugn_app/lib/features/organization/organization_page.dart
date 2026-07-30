import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../../core/models/organization.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/team_game_format.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import 'organization_admin_tools.dart';

class OrganizationPage extends ConsumerWidget {
  const OrganizationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organization = ref.watch(organizationProvider);
    return PageScaffold(
      title: 'Verein & Mannschaften',
      subtitle:
          'Verantwortlichkeiten, Trainingsbetrieb und Mannschaftsdaten zentral verwalten.',
      child: organization.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _OrganizationError(
          onRetry: () => ref.invalidate(organizationProvider),
        ),
        data: (data) => Column(
          children: [
            _ClubHero(data: data),
            const SizedBox(height: 20),
            _OrganizationContent(data: data),
            if (data.can('MANAGE_ORGANIZATION'))
              OrganizationAdminTools(organization: data),
          ],
        ),
      ),
    );
  }
}

class _OrganizationContent extends ConsumerWidget {
  const _OrganizationContent({required this.data});
  final OrganizationContext data;

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    TeamSummary? team,
    required AgeGroupSummary initialAgeGroup,
  }) async {
    final draft = await showDialog<_TeamDraft>(
      context: context,
      builder: (_) => _TeamEditorDialog(
        ageGroups: data.ageGroups,
        teams: data.teams,
        initialAgeGroup: initialAgeGroup,
        team: team,
      ),
    );
    if (draft == null) return;
    try {
      final repository = ref.read(repositoryProvider);
      if (team == null) {
        await repository.createTeam(
          ageGroupId: draft.ageGroupId,
          teamNumber: draft.teamNumber,
          name: draft.name,
          shortName: draft.shortName,
          level: draft.level,
          teamType: draft.teamType,
          gender: draft.gender,
          gameFormat: draft.gameFormat,
          birthYears: draft.birthYears,
          description: draft.description,
          trainingLocation: draft.trainingLocation,
          trainingTimes: draft.trainingTimes,
          seasonStartDate: draft.seasonStartDate,
          seasonEndDate: draft.seasonEndDate,
          indoorSeasonStartDate: draft.indoorSeasonStartDate,
          indoorSeasonEndDate: draft.indoorSeasonEndDate,
          indoorTrainingLocation: draft.indoorTrainingLocation,
          indoorTrainingTimes: draft.indoorTrainingTimes,
          homeVenue: draft.homeVenue,
          bfvTeamId: draft.bfvTeamId,
          dfbnetTeamId: draft.dfbnetTeamId,
          bfvTeamUrl: draft.bfvTeamUrl,
          isActive: draft.isActive,
        );
      } else {
        await repository.updateTeam(
          teamId: team.id,
          teamNumber: draft.teamNumber,
          name: draft.name,
          shortName: draft.shortName,
          level: draft.level,
          teamType: draft.teamType,
          gender: draft.gender,
          gameFormat: draft.gameFormat,
          birthYears: draft.birthYears,
          description: draft.description,
          trainingLocation: draft.trainingLocation,
          trainingTimes: draft.trainingTimes,
          seasonStartDate: draft.seasonStartDate,
          seasonEndDate: draft.seasonEndDate,
          indoorSeasonStartDate: draft.indoorSeasonStartDate,
          indoorSeasonEndDate: draft.indoorSeasonEndDate,
          indoorTrainingLocation: draft.indoorTrainingLocation,
          indoorTrainingTimes: draft.indoorTrainingTimes,
          homeVenue: draft.homeVenue,
          bfvTeamId: draft.bfvTeamId,
          dfbnetTeamId: draft.dfbnetTeamId,
          bfvTeamUrl: draft.bfvTeamUrl,
          isActive: draft.isActive,
        );
      }
      ref.invalidate(organizationProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(team == null
              ? '${draft.displayName} wurde angelegt.'
              : '${draft.displayName} wurde aktualisiert.'),
        ));
      }
    } on DioException catch (error) {
      final response = error.response?.data;
      final message = response is Map<String, dynamic>
          ? response['message'] as String?
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(message ?? 'Mannschaft konnte nicht gespeichert werden.'),
        ));
      }
    }
  }

  Future<void> _changePhoto(
    BuildContext context,
    WidgetRef ref,
    TeamSummary team,
  ) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    final decoded = img.decodeImage(await picked.readAsBytes());
    if (decoded == null) return;
    final oriented = img.bakeOrientation(decoded);
    final resized = oriented.width > 1600
        ? img.copyResize(oriented, width: 1600)
        : oriented;
    final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 86));
    try {
      final uploaded = await ref.read(repositoryProvider).uploadTeamPhoto(
            teamId: team.id,
            bytes: bytes,
            fileName: '${team.id}.jpg',
          );
      if (uploaded.photoUrl == null) {
        throw StateError('Foto wurde nicht vom Backend bestätigt.');
      }
      ref.invalidate(organizationProvider);
      final refreshed = await ref.read(organizationProvider.future);
      final confirmed = refreshed.teams.any(
        (candidate) => candidate.id == team.id && candidate.photoUrl != null,
      );
      if (!confirmed) {
        throw StateError(
            'Foto konnte nach dem Speichern nicht geladen werden.');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Mannschaftsfoto geschützt gespeichert.')),
        );
      }
    } on DioException catch (error) {
      final response = error.response?.data;
      final message = response is Map<String, dynamic>
          ? response['message'] as String?
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(message ?? 'Foto konnte nicht gespeichert werden.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
            'Das Foto wurde nicht vollständig bestätigt. Bitte erneut versuchen.',
          )),
        );
      }
    }
  }

  Future<void> _removePhoto(
    BuildContext context,
    WidgetRef ref,
    TeamSummary team,
  ) async {
    await ref.read(repositoryProvider).removeTeamPhoto(team.id);
    ref.invalidate(organizationProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mannschaftsfoto entfernt.')),
      );
    }
  }

  Future<void> _deleteTeam(
    BuildContext context,
    WidgetRef ref,
    TeamSummary team,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: Text('${team.displayName} löschen?'),
        content: const Text(
          'Die Mannschaft wird aus der aktiven Vereinsstruktur entfernt. '
          'Alle zugeordneten Spieler erscheinen danach unter „Nicht zugeordnet“ '
          'und können einer anderen Mannschaft zugewiesen werden. Historische '
          'Spiele und Statistiken bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Mannschaft löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await ref.read(repositoryProvider).deleteTeam(team.id);
      ref.invalidate(organizationProvider);
      ref.invalidate(playersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${team.displayName} wurde gelöscht. '
              '$count ${count == 1 ? 'Spieler ist' : 'Spieler sind'} jetzt nicht zugeordnet.',
            ),
          ),
        );
      }
    } on DioException catch (error) {
      final response = error.response?.data;
      final message = response is Map<String, dynamic>
          ? response['message'] as String?
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(message ?? 'Mannschaft konnte nicht gelöscht werden.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDeleteTeams =
        ref.watch(authProvider).user?.role == UserRole.superAdmin;
    final grouped = <String, List<TeamSummary>>{};
    for (final ageGroup in data.ageGroups) {
      grouped[ageGroup.id] =
          data.teams.where((team) => team.ageGroup.id == ageGroup.id).toList();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mannschaftsstruktur',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  '${data.ageGroups.length} Altersklassen · ${data.teams.where((team) => team.isActive).length} aktive Mannschaften',
                ),
              ],
            );
            final action = data.can('MANAGE_ORGANIZATION')
                ? FilledButton.icon(
                    onPressed: () => _openEditor(
                      context,
                      ref,
                      initialAgeGroup: data.currentTeam.ageGroup,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Mannschaft anlegen'),
                  )
                : null;
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      if (action != null) ...[
                        const SizedBox(height: 12),
                        action,
                      ],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: heading),
                      if (action != null) action,
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        for (final ageGroup in data.ageGroups)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _AgeGroupSection(
              ageGroup: ageGroup,
              teams: grouped[ageGroup.id] ?? const [],
              currentTeamId: data.currentTeam.id,
              canEdit: (team) =>
                  data.can('MANAGE_ORGANIZATION') ||
                  (data.can('MANAGE_TEAM') && team.id == data.currentTeam.id),
              canDelete: canDeleteTeams,
              onEdit: (team) => _openEditor(
                context,
                ref,
                team: team,
                initialAgeGroup: team.ageGroup,
              ),
              onPhoto: (team) => _changePhoto(context, ref, team),
              onRemovePhoto: (team) => _removePhoto(context, ref, team),
              onDelete: (team) => _deleteTeam(context, ref, team),
            ),
          ),
      ],
    );
  }
}

class _ClubHero extends StatelessWidget {
  const _ClubHero({required this.data});
  final OrganizationContext data;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.black, Color(0xFF3A3400)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ClubLogo(size: compact ? 58 : 76),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.club.name,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text(
                'Jugendfußball · Saison ${data.season.name}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          _HeroMetric(
              value: '${data.metrics.players}',
              label: 'Spieler im aktiven Team'),
          _HeroMetric(
              value: '${data.metrics.upcomingEvents}',
              label: 'kommende Termine'),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .65), fontSize: 12)),
          ],
        ),
      );
}

class _AgeGroupSection extends StatelessWidget {
  const _AgeGroupSection({
    required this.ageGroup,
    required this.teams,
    required this.currentTeamId,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onPhoto,
    required this.onRemovePhoto,
    required this.onDelete,
  });
  final AgeGroupSummary ageGroup;
  final List<TeamSummary> teams;
  final String currentTeamId;
  final bool Function(TeamSummary) canEdit;
  final bool canDelete;
  final ValueChanged<TeamSummary> onEdit;
  final ValueChanged<TeamSummary> onPhoto;
  final ValueChanged<TeamSummary> onRemovePhoto;
  final ValueChanged<TeamSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(ageGroup.code,
                  style: const TextStyle(
                      color: AppColors.blue, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 12),
            Text(ageGroup.name, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 10),
        if (teams.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Noch keine Mannschaft in dieser Altersklasse.'),
            ),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 1050
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth >= 680
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final team in teams)
                  SizedBox(
                    width: width,
                    child: _TeamCard(
                      team: team,
                      isCurrent: team.id == currentTeamId,
                      canEdit: canEdit(team),
                      canDelete: canDelete,
                      onEdit: () => onEdit(team),
                      onPhoto: () => onPhoto(team),
                      onRemovePhoto: () => onRemovePhoto(team),
                      onDelete: () => onDelete(team),
                    ),
                  ),
              ],
            );
          }),
      ],
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.isCurrent,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onPhoto,
    required this.onRemovePhoto,
    required this.onDelete,
  });
  final TeamSummary team;
  final bool isCurrent;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onDelete;

  String _label(String value) => switch (value) {
        'DEVELOPMENT' => 'Förderteam',
        'FESTIVAL' => 'Festivalteam',
        'RECREATIONAL' => 'Freizeitteam',
        _ => 'Wettkampfteam',
      };

  String _gender(String value) => switch (value) {
        'MALE' => 'männlich',
        'FEMALE' => 'weiblich',
        _ => 'gemischt',
      };

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: compact ? 96 : 140,
            width: double.infinity,
            child: team.photoUrl != null
                ? Image.network(team.photoUrl!, fit: BoxFit.cover)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppColors.navy,
                        AppColors.blue.withValues(alpha: .75),
                      ]),
                    ),
                    child: const Icon(Icons.groups_rounded,
                        size: 58, color: Colors.white70),
                  ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(team.displayName,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (isCurrent)
                      const Tooltip(
                        message: 'Aktive Mannschaft',
                        child: Icon(Icons.check_circle_rounded,
                            color: AppColors.teal),
                      ),
                    if (!team.isActive) const Chip(label: Text('Inaktiv')),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_label(team.teamType)} · ${_gender(team.gender)}'
                  '${team.level?.isNotEmpty == true ? ' · ${team.level}' : ''}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                _InfoLine(
                  icon: Icons.sports_soccer_rounded,
                  text: team.gameFormat.label,
                ),
                if (team.birthYears.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _InfoLine(
                    icon: Icons.cake_outlined,
                    text: 'Jahrgänge ${team.birthYears.join(', ')}',
                  ),
                ],
                if (team.trainingLocation?.isNotEmpty == true) ...[
                  const SizedBox(height: 7),
                  _InfoLine(
                      icon: Icons.location_on_outlined,
                      text: team.trainingLocation!),
                ],
                if (team.trainingTimes.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  _InfoLine(
                      icon: Icons.schedule_rounded,
                      text: team.trainingTimes.join(' · ')),
                ],
                if (team.seasonStartDate != null ||
                    team.seasonEndDate != null) ...[
                  const SizedBox(height: 7),
                  _InfoLine(
                    icon: Icons.date_range_rounded,
                    text: 'Mannschaftssaison '
                        '${_date(team.seasonStartDate) ?? 'Vereinsstart'} – '
                        '${_date(team.seasonEndDate) ?? 'Vereinsende'}',
                  ),
                ],
                if (team.indoorSeasonStartDate != null &&
                    team.indoorSeasonEndDate != null) ...[
                  const SizedBox(height: 7),
                  _InfoLine(
                    icon: Icons.sports_handball_rounded,
                    text: 'Halle ${_date(team.indoorSeasonStartDate)} – '
                        '${_date(team.indoorSeasonEndDate)}'
                        '${team.indoorTrainingLocation?.isNotEmpty == true ? ' · ${team.indoorTrainingLocation}' : ''}',
                  ),
                ],
                if (team.staff.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Teamverantwortliche',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 5),
                  Text(
                    team.staff
                        .map((member) =>
                            '${member.name} · ${_role(member.role)}')
                        .join('\n'),
                  ),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Bearbeiten'),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Mannschaftsfoto ändern',
                        onPressed: onPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                      ),
                      if (team.photoUrl != null)
                        IconButton(
                          tooltip: 'Foto entfernen',
                          onPressed: onRemovePhoto,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      if (canDelete)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Löschen'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _role(String role) => switch (role) {
        'COACH' || 'TRAINER' => 'Trainer',
        'ASSISTANT_COACH' => 'Co-Trainer',
        'TEAM_MANAGER' => 'Teammanager',
        'YOUTH_DIRECTOR' => 'Jugendleitung',
        _ => 'Vereinsleitung',
      };

  String? _date(DateTime? value) => value == null
      ? null
      : '${value.day.toString().padLeft(2, '0')}.'
          '${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.blue),
          const SizedBox(width: 7),
          Expanded(child: Text(text)),
        ],
      );
}

class _TeamEditorDialog extends StatefulWidget {
  const _TeamEditorDialog({
    required this.ageGroups,
    required this.teams,
    required this.initialAgeGroup,
    this.team,
  });
  final List<AgeGroupSummary> ageGroups;
  final List<TeamSummary> teams;
  final AgeGroupSummary initialAgeGroup;
  final TeamSummary? team;

  @override
  State<_TeamEditorDialog> createState() => _TeamEditorDialogState();
}

class _TeamEditorDialogState extends State<_TeamEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _level;
  late final TextEditingController _description;
  late final TextEditingController _trainingLocation;
  late final TextEditingController _trainingTimes;
  late final TextEditingController _indoorTrainingLocation;
  late final TextEditingController _indoorTrainingTimes;
  late final TextEditingController _homeVenue;
  late final TextEditingController _bfvTeamId;
  late final TextEditingController _dfbnetTeamId;
  late final TextEditingController _bfvTeamUrl;
  late String _ageGroupId;
  late int _teamNumber;
  late String _teamType;
  late String _gender;
  late TeamGameFormat _gameFormat;
  late bool _isActive;
  late Set<int> _birthYears;
  DateTime? _seasonStartDate;
  DateTime? _seasonEndDate;
  DateTime? _indoorSeasonStartDate;
  DateTime? _indoorSeasonEndDate;

  @override
  void initState() {
    super.initState();
    final team = widget.team;
    _level = TextEditingController(text: team?.level);
    _birthYears = {...?team?.birthYears};
    _description = TextEditingController(text: team?.description);
    _trainingLocation = TextEditingController(text: team?.trainingLocation);
    _trainingTimes =
        TextEditingController(text: team?.trainingTimes.join('\n'));
    _indoorTrainingLocation =
        TextEditingController(text: team?.indoorTrainingLocation);
    _indoorTrainingTimes =
        TextEditingController(text: team?.indoorTrainingTimes.join('\n'));
    _seasonStartDate = team?.seasonStartDate;
    _seasonEndDate = team?.seasonEndDate;
    _indoorSeasonStartDate = team?.indoorSeasonStartDate;
    _indoorSeasonEndDate = team?.indoorSeasonEndDate;
    _homeVenue = TextEditingController(text: team?.homeVenue);
    _bfvTeamId = TextEditingController(text: team?.bfvTeamId);
    _dfbnetTeamId = TextEditingController(text: team?.dfbnetTeamId);
    _bfvTeamUrl = TextEditingController(text: team?.bfvTeamUrl);
    _ageGroupId = team?.ageGroup.id ?? widget.initialAgeGroup.id;
    _teamNumber = team?.teamNumber ?? _nextAvailableTeamNumber(_ageGroupId);
    _teamType = team?.teamType ?? 'COMPETITIVE';
    _gender = team?.gender ?? 'MIXED';
    _gameFormat =
        team?.gameFormat ?? suggestedGameFormat(widget.initialAgeGroup.code);
    _isActive = team?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _level,
      _description,
      _trainingLocation,
      _trainingTimes,
      _indoorTrainingLocation,
      _indoorTrainingTimes,
      _homeVenue,
      _bfvTeamId,
      _dfbnetTeamId,
      _bfvTeamUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Set<int> _usedTeamNumbers(String ageGroupId) => widget.teams
      .where(
        (team) => team.ageGroup.id == ageGroupId && team.id != widget.team?.id,
      )
      .map((team) => team.teamNumber)
      .toSet();

  int _nextAvailableTeamNumber(String ageGroupId) {
    final used = _usedTeamNumbers(ageGroupId);
    return List.generate(5, (index) => index + 1)
        .firstWhere((number) => !used.contains(number), orElse: () => 1);
  }

  int _projectedTeamCount(String ageGroupId) {
    final existing =
        widget.teams.where((team) => team.ageGroup.id == ageGroupId).length;
    return widget.team == null ? existing + 1 : existing;
  }

  String _displayName(AgeGroupSummary ageGroup) =>
      _projectedTeamCount(ageGroup.id) <= 1 && _teamNumber == 1
          ? '${ageGroup.code}-Jugend'
          : '${ageGroup.code}$_teamNumber-Jugend';

  @override
  Widget build(BuildContext context) {
    final editing = widget.team != null;
    final selectedAgeGroup = widget.ageGroups.firstWhere(
      (group) => group.id == _ageGroupId,
    );
    final availableGameFormats = {
      _gameFormat,
      ...gameFormatsForAgeGroup(selectedAgeGroup.code),
    };
    final usedTeamNumbers = _usedTeamNumbers(_ageGroupId);
    final availableTeamNumbers = List.generate(5, (index) => index + 1)
        .where(
          (number) =>
              number == _teamNumber || !usedTeamNumbers.contains(number),
        )
        .toList();
    return AlertDialog(
      title: Text(editing ? 'Mannschaft bearbeiten' : 'Neue Mannschaft'),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .72,
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('Identität', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _ageGroupId,
                decoration: const InputDecoration(labelText: 'Altersklasse'),
                items: [
                  for (final group in widget.ageGroups)
                    DropdownMenuItem(value: group.id, child: Text(group.name)),
                ],
                onChanged: editing
                    ? null
                    : (value) {
                        final group = widget.ageGroups.firstWhere(
                          (item) => item.id == value,
                        );
                        setState(() {
                          _ageGroupId = value!;
                          _teamNumber = _nextAvailableTeamNumber(_ageGroupId);
                          _gameFormat = suggestedGameFormat(group.code);
                        });
                      },
              ),
              const SizedBox(height: 12),
              _twoColumns(
                DropdownButtonFormField<int>(
                  key: ValueKey('$_ageGroupId-$_teamNumber'),
                  initialValue: _teamNumber,
                  decoration: const InputDecoration(
                    labelText: 'Mannschaft innerhalb der Jugend *',
                    helperText:
                        'Nummern können in jeder Jugend separat vergeben werden.',
                    prefixIcon: Icon(Icons.format_list_numbered_rounded),
                  ),
                  items: [
                    for (final number in availableTeamNumbers)
                      DropdownMenuItem(
                        value: number,
                        child: Text(
                          '${selectedAgeGroup.code}$number-Jugend',
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _teamNumber = value!),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.yellowSoft.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Angezeigter Mannschaftsname',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _displayName(selectedAgeGroup),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TeamGameFormat>(
                initialValue: _gameFormat,
                decoration: const InputDecoration(
                  labelText: 'BFV-Spielform der Mannschaft *',
                  helperText:
                      'Altersgerechte Modelle; bestimmt auch die Aufstellung.',
                  prefixIcon: Icon(Icons.sports_soccer_rounded),
                ),
                items: [
                  for (final format in availableGameFormats)
                    DropdownMenuItem(
                      value: format,
                      child: Text(format.label),
                    ),
                ],
                onChanged: (value) => setState(() => _gameFormat = value!),
              ),
              const SizedBox(height: 12),
              _twoColumns(
                DropdownButtonFormField<String>(
                  initialValue: _teamType,
                  decoration: const InputDecoration(labelText: 'Teamtyp'),
                  items: const [
                    DropdownMenuItem(
                        value: 'COMPETITIVE', child: Text('Wettkampfteam')),
                    DropdownMenuItem(
                        value: 'DEVELOPMENT', child: Text('Förderteam')),
                    DropdownMenuItem(
                        value: 'FESTIVAL', child: Text('Festivalteam')),
                    DropdownMenuItem(
                        value: 'RECREATIONAL', child: Text('Freizeitteam')),
                  ],
                  onChanged: (value) => setState(() => _teamType = value!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Ausrichtung'),
                  items: const [
                    DropdownMenuItem(value: 'MIXED', child: Text('Gemischt')),
                    DropdownMenuItem(value: 'MALE', child: Text('Männlich')),
                    DropdownMenuItem(value: 'FEMALE', child: Text('Weiblich')),
                  ],
                  onChanged: (value) => setState(() => _gender = value!),
                ),
              ),
              const SizedBox(height: 12),
              _twoColumns(
                _BirthYearMultiSelectField(
                  selectedYears: _birthYears,
                  onTap: _selectBirthYears,
                ),
                TextFormField(
                  controller: _level,
                  decoration:
                      const InputDecoration(labelText: 'Spielklasse / Niveau'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Beschreibung und Mannschaftsprofil'),
              ),
              const SizedBox(height: 22),
              Text('Training & Heimspiele',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _twoColumns(
                TextFormField(
                  controller: _trainingLocation,
                  decoration: const InputDecoration(
                    labelText: 'Trainingsplatz / Bereich',
                    hintText: 'z. B. Platz 1 unten',
                    helperText: 'Bestimmt die Farbe im Platzbelegungsplan.',
                  ),
                ),
                TextFormField(
                  controller: _homeVenue,
                  decoration:
                      const InputDecoration(labelText: 'Heimspielstätte'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _trainingTimes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reguläre Trainingszeiten',
                  hintText: 'Eine Zeit pro Zeile, z. B. Dienstag 17:00–18:30',
                  helperText:
                      'Diese Zeiten erscheinen für alle Trainer im gemeinsamen Platzplan.',
                ),
              ),
              const SizedBox(height: 16),
              Text('Mannschaftssaison',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Diese Grenzen steuern Saisonmarkierungen und die '
                'automatische Trainingsserie im Kalender.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              _twoColumns(
                _dateField(
                  'Saisonanfang',
                  _seasonStartDate,
                  (value) => setState(() => _seasonStartDate = value),
                ),
                _dateField(
                  'Saisonende',
                  _seasonEndDate,
                  (value) => setState(() => _seasonEndDate = value),
                ),
              ),
              const SizedBox(height: 22),
              Text('Wintersaison & Halle',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _twoColumns(
                _dateField(
                  'Hallenstart',
                  _indoorSeasonStartDate,
                  (value) => setState(() => _indoorSeasonStartDate = value),
                ),
                _dateField(
                  'Hallenende',
                  _indoorSeasonEndDate,
                  (value) => setState(() => _indoorSeasonEndDate = value),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _indoorTrainingLocation,
                decoration: const InputDecoration(
                  labelText: 'Sporthalle / Hallenbereich',
                  hintText: 'z. B. Mehrzweckhalle Teugn',
                  prefixIcon: Icon(Icons.sports_handball_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _indoorTrainingTimes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reguläre Hallentrainingszeiten',
                  hintText: 'Eine Zeit pro Zeile, z. B. Freitag 17:00–18:30',
                ),
              ),
              const SizedBox(height: 22),
              Text('Verbandsreferenzen',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _twoColumns(
                TextFormField(
                  controller: _bfvTeamId,
                  decoration: const InputDecoration(labelText: 'BFV-Team-ID'),
                ),
                TextFormField(
                  controller: _dfbnetTeamId,
                  decoration:
                      const InputDecoration(labelText: 'DFBnet-Team-ID'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bfvTeamUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'BFV-Teamseite'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final uri = Uri.tryParse(text);
                  return uri != null &&
                          (uri.scheme == 'https' || uri.scheme == 'http') &&
                          uri.host.isNotEmpty
                      ? null
                      : 'Bitte eine gültige Webadresse eingeben.';
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mannschaft aktiv'),
                subtitle: const Text(
                    'Inaktive Teams bleiben dokumentiert, werden aber klar markiert.'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Speichern'),
        ),
      ],
    );
  }

  Widget _twoColumns(Widget first, Widget second) => LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 540
            ? Column(children: [
                first,
                const SizedBox(height: 12),
                second,
              ])
            : Row(children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: second),
              ]),
      );

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) =>
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(DateTime.now().year - 2),
            lastDate: DateTime(DateTime.now().year + 4, 12, 31),
          );
          if (selected != null) onChanged(selected);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.event_rounded),
            suffixIcon: value == null
                ? null
                : IconButton(
                    tooltip: 'Datum entfernen',
                    onPressed: () => onChanged(null),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          child: Text(
            value == null
                ? 'Vereinssaison verwenden'
                : '${value.day.toString().padLeft(2, '0')}.'
                    '${value.month.toString().padLeft(2, '0')}.${value.year}',
          ),
        ),
      );

  Future<void> _selectBirthYears() async {
    final currentYear = DateTime.now().year;
    final availableYears = List.generate(26, (index) => currentYear - index);
    final selected = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) {
        var draft = {..._birthYears};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Jahrgänge auswählen'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Wähle alle Geburtsjahrgänge aus, die zu dieser '
                      'Mannschaft gehören.',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final year in availableYears)
                          FilterChip(
                            label: Text('$year'),
                            selected: draft.contains(year),
                            onSelected: (value) => setDialogState(() {
                              if (value) {
                                draft.add(year);
                              } else {
                                draft.remove(year);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    draft.isEmpty ? null : () => setDialogState(draft.clear),
                child: const Text('Alle abwählen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, draft),
                icon: const Icon(Icons.check_rounded),
                label: Text('${draft.length} übernehmen'),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _birthYears = selected);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_seasonStartDate != null &&
        _seasonEndDate != null &&
        _seasonStartDate!.isAfter(_seasonEndDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Saisonanfang muss vor dem Saisonende liegen.'),
        ),
      );
      return;
    }
    if ((_indoorSeasonStartDate == null) != (_indoorSeasonEndDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Hallenanfang und Hallenende angeben.'),
        ),
      );
      return;
    }
    if (_indoorSeasonStartDate != null &&
        _indoorSeasonStartDate!.isAfter(_indoorSeasonEndDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Hallenanfang muss vor dem Hallenende liegen.'),
        ),
      );
      return;
    }
    final selectedAgeGroup = widget.ageGroups.firstWhere(
      (group) => group.id == _ageGroupId,
    );
    final compactName = '${selectedAgeGroup.code}$_teamNumber';
    final years = _birthYears.toList()..sort((a, b) => b.compareTo(a));
    Navigator.pop(
      context,
      _TeamDraft(
        ageGroupId: _ageGroupId,
        teamNumber: _teamNumber,
        name: compactName,
        displayName: _displayName(selectedAgeGroup),
        shortName: compactName,
        level: _optional(_level),
        teamType: _teamType,
        gender: _gender,
        gameFormat: _gameFormat,
        birthYears: years,
        description: _optional(_description),
        trainingLocation: _optional(_trainingLocation),
        trainingTimes: _trainingTimes.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        seasonStartDate: _seasonStartDate,
        seasonEndDate: _seasonEndDate,
        indoorSeasonStartDate: _indoorSeasonStartDate,
        indoorSeasonEndDate: _indoorSeasonEndDate,
        indoorTrainingLocation: _optional(_indoorTrainingLocation),
        indoorTrainingTimes: _indoorTrainingTimes.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        homeVenue: _optional(_homeVenue),
        bfvTeamId: _optional(_bfvTeamId),
        dfbnetTeamId: _optional(_dfbnetTeamId),
        bfvTeamUrl: _optional(_bfvTeamUrl),
        isActive: _isActive,
      ),
    );
  }
}

class _BirthYearMultiSelectField extends StatelessWidget {
  const _BirthYearMultiSelectField({
    required this.selectedYears,
    required this.onTap,
  });

  final Set<int> selectedYears;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final years = selectedYears.toList()..sort((a, b) => b.compareTo(a));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: years.isEmpty,
        decoration: const InputDecoration(
          labelText: 'Jahrgänge',
          helperText: 'Mehrfachauswahl möglich',
          prefixIcon: Icon(Icons.cake_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: years.isEmpty
            ? const Text(
                'Jahrgänge auswählen',
                style: TextStyle(color: AppColors.muted),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  for (final year in years)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$year'),
                    ),
                ],
              ),
      ),
    );
  }
}

class _TeamDraft {
  const _TeamDraft({
    required this.ageGroupId,
    required this.teamNumber,
    required this.name,
    required this.displayName,
    required this.teamType,
    required this.gender,
    required this.gameFormat,
    required this.birthYears,
    required this.trainingTimes,
    required this.indoorTrainingTimes,
    required this.isActive,
    this.shortName,
    this.level,
    this.description,
    this.trainingLocation,
    this.seasonStartDate,
    this.seasonEndDate,
    this.indoorSeasonStartDate,
    this.indoorSeasonEndDate,
    this.indoorTrainingLocation,
    this.homeVenue,
    this.bfvTeamId,
    this.dfbnetTeamId,
    this.bfvTeamUrl,
  });
  final String ageGroupId;
  final int teamNumber;
  final String name;
  final String displayName;
  final String? shortName;
  final String? level;
  final String teamType;
  final String gender;
  final TeamGameFormat gameFormat;
  final List<int> birthYears;
  final String? description;
  final String? trainingLocation;
  final List<String> trainingTimes;
  final DateTime? seasonStartDate;
  final DateTime? seasonEndDate;
  final DateTime? indoorSeasonStartDate;
  final DateTime? indoorSeasonEndDate;
  final String? indoorTrainingLocation;
  final List<String> indoorTrainingTimes;
  final String? homeVenue;
  final String? bfvTeamId;
  final String? dfbnetTeamId;
  final String? bfvTeamUrl;
  final bool isActive;
}

class _OrganizationError extends StatelessWidget {
  const _OrganizationError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Vereinsstruktur nicht erreichbar',
        message: 'Bitte Verbindung prüfen und erneut laden.',
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut laden'),
        ),
      );
}
