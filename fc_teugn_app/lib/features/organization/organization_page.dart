import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
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
          name: draft.name,
          shortName: draft.shortName,
          level: draft.level,
          teamType: draft.teamType,
          gender: draft.gender,
          birthYears: draft.birthYears,
          description: draft.description,
          trainingLocation: draft.trainingLocation,
          trainingTimes: draft.trainingTimes,
          homeVenue: draft.homeVenue,
          bfvTeamId: draft.bfvTeamId,
          dfbnetTeamId: draft.dfbnetTeamId,
          bfvTeamUrl: draft.bfvTeamUrl,
          isActive: draft.isActive,
        );
      } else {
        await repository.updateTeam(
          teamId: team.id,
          name: draft.name,
          shortName: draft.shortName,
          level: draft.level,
          teamType: draft.teamType,
          gender: draft.gender,
          birthYears: draft.birthYears,
          description: draft.description,
          trainingLocation: draft.trainingLocation,
          trainingTimes: draft.trainingTimes,
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
              ? '${draft.name} wurde angelegt.'
              : '${draft.name} wurde aktualisiert.'),
        ));
      }
    } on DioException catch (error) {
      final response = error.response?.data;
      final message =
          response is Map<String, dynamic> ? response['message'] as String? : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message ?? 'Mannschaft konnte nicht gespeichert werden.'),
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
      await ref.read(repositoryProvider).uploadTeamPhoto(
            teamId: team.id,
            bytes: bytes,
            fileName: '${team.id}.jpg',
          );
      ref.invalidate(organizationProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mannschaftsfoto geschützt gespeichert.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto konnte nicht gespeichert werden.')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = <String, List<TeamSummary>>{};
    for (final ageGroup in data.ageGroups) {
      grouped[ageGroup.id] =
          data.teams.where((team) => team.ageGroup.id == ageGroup.id).toList();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mannschaftsstruktur',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${data.ageGroups.length} Altersklassen · ${data.teams.where((team) => team.isActive).length} aktive Mannschaften',
                  ),
                ],
              ),
            ),
            if (data.can('MANAGE_ORGANIZATION'))
              FilledButton.icon(
                onPressed: () => _openEditor(
                  context,
                  ref,
                  initialAgeGroup: data.currentTeam.ageGroup,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Mannschaft anlegen'),
              ),
          ],
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
              onEdit: (team) => _openEditor(
                context,
                ref,
                team: team,
                initialAgeGroup: team.ageGroup,
              ),
              onPhoto: (team) => _changePhoto(context, ref, team),
              onRemovePhoto: (team) => _removePhoto(context, ref, team),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, Color(0xFF174D68)],
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
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(
              data.club.shortName,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
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
    required this.onEdit,
    required this.onPhoto,
    required this.onRemovePhoto,
  });
  final AgeGroupSummary ageGroup;
  final List<TeamSummary> teams;
  final String currentTeamId;
  final bool Function(TeamSummary) canEdit;
  final ValueChanged<TeamSummary> onEdit;
  final ValueChanged<TeamSummary> onPhoto;
  final ValueChanged<TeamSummary> onRemovePhoto;

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
                      onEdit: () => onEdit(team),
                      onPhoto: () => onPhoto(team),
                      onRemovePhoto: () => onRemovePhoto(team),
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
    required this.onEdit,
    required this.onPhoto,
    required this.onRemovePhoto,
  });
  final TeamSummary team;
  final bool isCurrent;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onPhoto;
  final VoidCallback onRemovePhoto;

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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 140,
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(team.name,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (isCurrent)
                      const Tooltip(
                        message: 'Aktive Mannschaft',
                        child: Icon(Icons.check_circle_rounded,
                            color: AppColors.teal),
                      ),
                    if (!team.isActive)
                      const Chip(label: Text('Inaktiv')),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_label(team.teamType)} · ${_gender(team.gender)}'
                  '${team.level?.isNotEmpty == true ? ' · ${team.level}' : ''}',
                  style: const TextStyle(color: AppColors.muted),
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
                if (team.staff.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Teamverantwortliche',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 5),
                  Text(
                    team.staff
                        .map((member) => '${member.name} · ${_role(member.role)}')
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
    required this.initialAgeGroup,
    this.team,
  });
  final List<AgeGroupSummary> ageGroups;
  final AgeGroupSummary initialAgeGroup;
  final TeamSummary? team;

  @override
  State<_TeamEditorDialog> createState() => _TeamEditorDialogState();
}

class _TeamEditorDialogState extends State<_TeamEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _shortName;
  late final TextEditingController _level;
  late final TextEditingController _birthYears;
  late final TextEditingController _description;
  late final TextEditingController _trainingLocation;
  late final TextEditingController _trainingTimes;
  late final TextEditingController _homeVenue;
  late final TextEditingController _bfvTeamId;
  late final TextEditingController _dfbnetTeamId;
  late final TextEditingController _bfvTeamUrl;
  late String _ageGroupId;
  late String _teamType;
  late String _gender;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final team = widget.team;
    _name = TextEditingController(text: team?.name);
    _shortName = TextEditingController(text: team?.shortName);
    _level = TextEditingController(text: team?.level);
    _birthYears = TextEditingController(text: team?.birthYears.join(', '));
    _description = TextEditingController(text: team?.description);
    _trainingLocation = TextEditingController(text: team?.trainingLocation);
    _trainingTimes =
        TextEditingController(text: team?.trainingTimes.join('\n'));
    _homeVenue = TextEditingController(text: team?.homeVenue);
    _bfvTeamId = TextEditingController(text: team?.bfvTeamId);
    _dfbnetTeamId = TextEditingController(text: team?.dfbnetTeamId);
    _bfvTeamUrl = TextEditingController(text: team?.bfvTeamUrl);
    _ageGroupId = team?.ageGroup.id ?? widget.initialAgeGroup.id;
    _teamType = team?.teamType ?? 'COMPETITIVE';
    _gender = team?.gender ?? 'MIXED';
    _isActive = team?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _shortName,
      _level,
      _birthYears,
      _description,
      _trainingLocation,
      _trainingTimes,
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

  @override
  Widget build(BuildContext context) {
    final editing = widget.team != null;
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
                    : (value) => setState(() => _ageGroupId = value!),
              ),
              const SizedBox(height: 12),
              _twoColumns(
                TextFormField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Mannschaftsname *'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Bitte Namen eingeben.'
                      : null,
                ),
                TextFormField(
                  controller: _shortName,
                  decoration: const InputDecoration(labelText: 'Kurzname'),
                ),
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
                TextFormField(
                  controller: _birthYears,
                  decoration: const InputDecoration(
                    labelText: 'Jahrgänge',
                    hintText: 'z. B. 2015, 2016',
                  ),
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
                  decoration:
                      const InputDecoration(labelText: 'Trainingsort'),
                ),
                TextFormField(
                  controller: _homeVenue,
                  decoration: const InputDecoration(labelText: 'Heimspielstätte'),
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
                  decoration: const InputDecoration(labelText: 'DFBnet-Team-ID'),
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final years = _birthYears.text
        .split(RegExp(r'[,;\s]+'))
        .map(int.tryParse)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    Navigator.pop(
      context,
      _TeamDraft(
        ageGroupId: _ageGroupId,
        name: _name.text.trim(),
        shortName: _optional(_shortName),
        level: _optional(_level),
        teamType: _teamType,
        gender: _gender,
        birthYears: years,
        description: _optional(_description),
        trainingLocation: _optional(_trainingLocation),
        trainingTimes: _trainingTimes.text
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

class _TeamDraft {
  const _TeamDraft({
    required this.ageGroupId,
    required this.name,
    required this.teamType,
    required this.gender,
    required this.birthYears,
    required this.trainingTimes,
    required this.isActive,
    this.shortName,
    this.level,
    this.description,
    this.trainingLocation,
    this.homeVenue,
    this.bfvTeamId,
    this.dfbnetTeamId,
    this.bfvTeamUrl,
  });
  final String ageGroupId;
  final String name;
  final String? shortName;
  final String? level;
  final String teamType;
  final String gender;
  final List<int> birthYears;
  final String? description;
  final String? trainingLocation;
  final List<String> trainingTimes;
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
