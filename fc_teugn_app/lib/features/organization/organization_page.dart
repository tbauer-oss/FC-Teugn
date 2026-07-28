import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class OrganizationPage extends ConsumerWidget {
  const OrganizationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organization = ref.watch(organizationProvider);

    return PageScaffold(
      title: 'Verein & Mannschaften',
      subtitle:
          'Saison, Altersklassen und Teams in einer gemeinsamen Struktur verwalten.',
      child: organization.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _OrganizationError(
          onRetry: () => ref.invalidate(organizationProvider),
        ),
        data: (data) => _OrganizationContent(
          data: data,
          onCreateTeam: data.can('MANAGE_ORGANIZATION')
              ? () => _createTeam(context, ref, data)
              : null,
        ),
      ),
    );
  }

  Future<void> _createTeam(
    BuildContext context,
    WidgetRef ref,
    OrganizationContext organization,
  ) async {
    final draft = await showDialog<_TeamDraft>(
      context: context,
      builder: (context) => _CreateTeamDialog(
        ageGroups: organization.ageGroups,
        initialAgeGroupId: organization.currentTeam.ageGroup.id,
      ),
    );
    if (draft == null) return;

    try {
      await ref.read(repositoryProvider).createTeam(
            ageGroupId: draft.ageGroupId,
            name: draft.name,
            shortName: draft.shortName,
            level: draft.level,
          );
      ref.invalidate(organizationProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${draft.name} wurde angelegt.')),
        );
      }
    } on DioException catch (error) {
      final data = error.response?.data;
      final message = data is Map<String, dynamic>
          ? data['message'] as String?
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message ?? 'Mannschaft konnte nicht angelegt werden.')),
        );
      }
    }
  }
}

class _OrganizationContent extends StatelessWidget {
  const _OrganizationContent({
    required this.data,
    required this.onCreateTeam,
  });

  final OrganizationContext data;
  final VoidCallback? onCreateTeam;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<TeamSummary>>{};
    for (final ageGroup in data.ageGroups) {
      grouped[ageGroup.id] = data.teams
          .where((team) => team.ageGroup.id == ageGroup.id)
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClubHero(data: data),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mannschaftsstruktur',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${data.ageGroups.length} Altersklassen · ${data.teams.length} aktive Mannschaften',
                  ),
                ],
              ),
            ),
            if (onCreateTeam != null)
              FilledButton.icon(
                onPressed: onCreateTeam,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Mannschaft anlegen'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final ageGroup in data.ageGroups)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AgeGroupCard(
              ageGroup: ageGroup,
              teams: grouped[ageGroup.id] ?? const [],
              currentTeamId: data.currentTeam.id,
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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                    ),
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
            label: 'Spieler im aktiven Team',
          ),
          _HeroMetric(
            value: '${data.metrics.upcomingEvents}',
            label: 'kommende Termine',
          ),
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
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .65),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgeGroupCard extends StatelessWidget {
  const _AgeGroupCard({
    required this.ageGroup,
    required this.teams,
    required this.currentTeamId,
  });

  final AgeGroupSummary ageGroup;
  final List<TeamSummary> teams;
  final String currentTeamId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: teams.isEmpty
                    ? AppColors.background
                    : AppColors.blue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                ageGroup.code,
                style: TextStyle(
                  color: teams.isEmpty ? AppColors.muted : AppColors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ageGroup.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (teams.isEmpty)
                    const Text('Noch keine Mannschaft in dieser Altersklasse.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final team in teams)
                          Chip(
                            avatar: Icon(
                              team.id == currentTeamId
                                  ? Icons.check_circle_rounded
                                  : Icons.shield_outlined,
                              size: 17,
                              color: team.id == currentTeamId
                                  ? AppColors.teal
                                  : AppColors.muted,
                            ),
                            label: Text(
                              [
                                team.name,
                                if (team.level?.isNotEmpty == true) team.level!,
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrganizationError extends StatelessWidget {
  const _OrganizationError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
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
}

class _CreateTeamDialog extends StatefulWidget {
  const _CreateTeamDialog({
    required this.ageGroups,
    required this.initialAgeGroupId,
  });

  final List<AgeGroupSummary> ageGroups;
  final String initialAgeGroupId;

  @override
  State<_CreateTeamDialog> createState() => _CreateTeamDialogState();
}

class _CreateTeamDialogState extends State<_CreateTeamDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _shortName = TextEditingController();
  final _level = TextEditingController();
  late String _ageGroupId;

  @override
  void initState() {
    super.initState();
    _ageGroupId = widget.initialAgeGroupId;
  }

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Mannschaft'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _ageGroupId,
                decoration: const InputDecoration(labelText: 'Altersklasse'),
                items: [
                  for (final ageGroup in widget.ageGroups)
                    DropdownMenuItem(
                      value: ageGroup.id,
                      child: Text(ageGroup.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _ageGroupId = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Mannschaftsname',
                  hintText: 'z. B. E1',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte einen Namen eingeben.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortName,
                decoration:
                    const InputDecoration(labelText: 'Kurzname (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _level,
                decoration: const InputDecoration(
                  labelText: 'Spielklasse / Niveau (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _TeamDraft(
                ageGroupId: _ageGroupId,
                name: _name.text.trim(),
                shortName:
                    _shortName.text.trim().isEmpty ? null : _shortName.text.trim(),
                level: _level.text.trim().isEmpty ? null : _level.text.trim(),
              ),
            );
          },
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}

class _TeamDraft {
  const _TeamDraft({
    required this.ageGroupId,
    required this.name,
    this.shortName,
    this.level,
  });

  final String ageGroupId;
  final String name;
  final String? shortName;
  final String? level;
}
