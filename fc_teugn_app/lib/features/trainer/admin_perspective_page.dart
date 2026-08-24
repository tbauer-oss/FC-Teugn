import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class AdminPerspectivePage extends ConsumerStatefulWidget {
  const AdminPerspectivePage({super.key});

  @override
  ConsumerState<AdminPerspectivePage> createState() =>
      _AdminPerspectivePageState();
}

class _AdminPerspectivePageState extends ConsumerState<AdminPerspectivePage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _openingId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(authProvider).user;
    if (current?.role != UserRole.superAdmin) {
      return const PageScaffold(
        title: 'Ansicht als Mitglied',
        subtitle:
            'Diese Funktion steht nur der Systemadministration zur Verfügung.',
        child: Center(child: Text('Kein Zugriff auf die Mitgliedsvorschau.')),
      );
    }
    final members = ref.watch(membersProvider);
    return PageScaffold(
      title: 'Ansicht als Mitglied',
      subtitle:
          'Die App schreibgeschützt aus Sicht eines Elternteils, Spielers oder Mitglieds des Trainerteams prüfen.',
      denseMobileHeader: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.yellowSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.gold.withValues(alpha: .22)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_rounded, color: AppColors.gold),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Du siehst echte freigegebene Inhalte und Berechtigungen des gewählten Kontos. Änderungen, Antworten und andere Schreibaktionen sind in dieser Vorschau technisch gesperrt.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              labelText: 'Mitglied suchen',
              hintText: 'Name, E-Mail, Rolle oder Mannschaft',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => const _PreviewMessage(
              icon: Icons.cloud_off_rounded,
              text: 'Die Mitglieder konnten gerade nicht geladen werden.',
            ),
            data: (values) {
              final filtered = values.where((member) {
                if (member.id == current!.id ||
                    member.status != AccountStatus.approved) {
                  return false;
                }
                if (_query.isEmpty) return true;
                final teams = member.assignedTeams
                    .map((team) => '${team.ageGroupCode} ${team.teamName}')
                    .join(' ');
                return '${member.name} ${member.email} ${member.roleLabel} $teams'
                    .toLowerCase()
                    .contains(_query);
              }).toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              if (filtered.isEmpty) {
                return const _PreviewMessage(
                  icon: Icons.person_search_rounded,
                  text: 'Kein passendes freigegebenes Mitglied gefunden.',
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final member = filtered[index];
                  final teams = member.assignedTeams
                      .map((team) => team.ageGroupCode.isEmpty
                          ? team.teamName
                          : '${team.ageGroupCode} · ${team.teamName}')
                      .toSet()
                      .join('  ·  ');
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.yellowSoft,
                        foregroundColor: AppColors.black,
                        child: Text(_initials(member.name)),
                      ),
                      title: Text(
                        member.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text([
                        member.roleLabel,
                        if (teams.isNotEmpty) teams,
                        member.email,
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: _openingId == member.id
                          ? const SizedBox.square(
                              dimension: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : IconButton(
                              tooltip: 'Ansicht öffnen',
                              onPressed: () => _openPreview(member),
                              icon: const Icon(Icons.visibility_rounded),
                            ),
                      onTap: _openingId == null
                          ? () => _openPreview(member)
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openPreview(AppUser member) async {
    if (_openingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Ansicht von ${member.name} öffnen?'),
        content: Text(
          'Du wechselst in eine schreibgeschützte ${member.roleLabel}-Ansicht. Ein dauerhaft sichtbarer Hinweis führt dich zurück zur Systemadministration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Vorschau öffnen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _openingId = member.id);
    try {
      final target =
          await ref.read(authProvider.notifier).enterReadOnlyPreview(member.id);
      if (!mounted) return;
      context.go(target.isTrainer ? '/trainer' : '/parent');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((item) => item.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(icon, size: 38, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );
}
