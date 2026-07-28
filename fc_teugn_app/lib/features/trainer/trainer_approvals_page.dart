import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class TrainerApprovalsPage extends ConsumerWidget {
  const TrainerApprovalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingUsersProvider);
    final members = ref.watch(membersProvider);
    final organization = ref.watch(organizationProvider).value;
    final players = ref.watch(playersProvider).value ?? const <PlayerModel>[];

    return PageScaffold(
      title: 'Mitglieder & Freigaben',
      subtitle:
          'Anfragen prüfen, Rollen festlegen und Zugriffe gezielt Mannschaften zuordnen.',
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Card(
              child: TabBar(
                padding: const EdgeInsets.all(6),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(
                    text:
                        'Offene Anfragen (${pending.value?.length ?? '–'})',
                  ),
                  Tab(text: 'Mitglieder (${members.value?.length ?? '–'})'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 620,
              child: TabBarView(
                children: [
                  _PendingList(
                    value: pending,
                    organization: organization,
                    onApprove: (user) =>
                        _approve(context, ref, user, organization, players),
                    onBlock: (user) => _block(context, ref, user),
                  ),
                  _MemberList(value: members),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
    OrganizationContext? organization,
    List<PlayerModel> players,
  ) async {
    if (organization == null) return;
    final decision = await showDialog<_ApprovalDecision>(
      context: context,
      builder: (context) => _ApprovalDialog(
        user: user,
        organization: organization,
        players: players,
      ),
    );
    if (decision == null) return;
    try {
      await ref.read(repositoryProvider).approveUser(
            user.id,
            role: decision.role,
            teamIds: decision.teamIds,
            playerId: decision.playerId,
          );
      _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} wurde freigegeben.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Freigabe konnte nicht gespeichert werden.')),
        );
      }
    }
  }

  Future<void> _block(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anfrage blockieren?'),
        content: Text(
          '${user.name} kann sich danach nicht mehr in der App anmelden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Blockieren'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(repositoryProvider)
        .approveUser(user.id, status: AccountStatus.blocked);
    _refresh(ref);
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(pendingUsersProvider);
    ref.invalidate(membersProvider);
    ref.invalidate(organizationProvider);
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.value,
    required this.organization,
    required this.players,
    required this.onApprove,
    required this.onBlock,
  });

  final AsyncValue<List<AppUser>> value;
  final OrganizationContext? organization;
  final ValueChanged<AppUser> onApprove;
  final ValueChanged<AppUser> onBlock;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Freigaben nicht erreichbar',
        message: 'Die offenen Anfragen konnten nicht geladen werden.',
      ),
      data: (users) {
        if (users.isEmpty) {
          return const EmptyState(
            icon: Icons.verified_user_rounded,
            title: 'Alles erledigt',
            message: 'Aktuell warten keine neuen Mitglieder auf eine Freigabe.',
          );
        }
        return ListView.separated(
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.orange.withValues(alpha: .18),
                      child: Text(
                        _initials(user.name),
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text('${user.email} · ${user.roleLabel}'),
                          if (user.createdAt != null)
                            Text(
                              'Registriert am ${_date(user.createdAt!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => onBlock(user),
                      child: const Text('Blockieren'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: organization == null
                          ? null
                          : () => onApprove(user),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Prüfen & freigeben'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({required this.value});

  final AsyncValue<List<AppUser>> value;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Mitglieder nicht erreichbar',
        message: 'Die Mitgliederliste konnte nicht geladen werden.',
      ),
      data: (users) => ListView.separated(
        itemCount: users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final user = users[index];
          final approved = user.status == AccountStatus.approved;
          return Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: CircleAvatar(child: Text(_initials(user.name))),
              title: Text(user.name),
              subtitle: Text(
                [
                  user.roleLabel,
                  if (user.memberships.isNotEmpty)
                    user.memberships
                        .map((item) =>
                            '${item.ageGroupCode}-Jugend ${item.teamName}')
                        .join(', '),
                ].join(' · '),
              ),
              trailing: Chip(
                avatar: Icon(
                  approved ? Icons.check_circle_rounded : Icons.block_rounded,
                  size: 16,
                  color: approved ? AppColors.teal : Colors.redAccent,
                ),
                label: Text(approved ? 'Freigegeben' : _status(user.status)),
              ),
            ),
          );
        },
      ),
    );
  }

  String _status(AccountStatus value) => switch (value) {
        AccountStatus.pending => 'Ausstehend',
        AccountStatus.approved => 'Freigegeben',
        AccountStatus.blocked => 'Blockiert',
      };
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({
    required this.user,
    required this.organization,
  });

  final AppUser user;
  final OrganizationContext organization;
  final List<PlayerModel> players;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late UserRole role;
  late Set<String> teamIds;
  String? playerId;

  @override
  void initState() {
    super.initState();
    role = widget.user.role;
    teamIds = widget.user.memberships.isEmpty
        ? {widget.organization.currentTeam.id}
        : widget.user.memberships.map((item) => item.teamId).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final canManageOrganization =
        widget.organization.can('MANAGE_ORGANIZATION');
    final roles = canManageOrganization
        ? const [
            UserRole.clubAdmin,
            UserRole.youthDirector,
            UserRole.coach,
            UserRole.assistantCoach,
            UserRole.teamManager,
            UserRole.parent,
            UserRole.player,
            UserRole.readOnly,
          ]
        : const [UserRole.parent, UserRole.player, UserRole.readOnly];
    if (!roles.contains(role)) role = roles.first;

    return AlertDialog(
      title: Text('${widget.user.name} freigeben'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rolle',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration:
                    const InputDecoration(labelText: 'Freigegebene Rolle'),
                items: [
                  for (final item in roles)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_roleLabel(item)),
                    ),
                ],
                onChanged: (value) => setState(() => role = value!),
              ),
              const SizedBox(height: 20),
              Text(
                'Mannschaften',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Mindestens eine Mannschaft auswählen. Die erste Auswahl wird zum Standardteam.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final team in widget.organization.teams)
                    FilterChip(
                      selected: teamIds.contains(team.id),
                      label: Text(team.displayName),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          teamIds.add(team.id);
                        } else if (teamIds.length > 1) {
                          teamIds.remove(team.id);
                        }
                      }),
                    ),
                ],
              ),
              if (role == UserRole.player) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: playerId,
                  decoration: const InputDecoration(
                    labelText: 'Verknüpftes Spielerprofil *',
                  ),
                  items: [
                    for (final player in widget.players.where(
                      (player) => teamIds.contains(player.teamId),
                    ))
                      DropdownMenuItem(
                        value: player.id,
                        child: Text(player.fullName),
                      ),
                  ],
                  onChanged: (value) => setState(() => playerId = value),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Rolle und Mannschaftszugriffe werden serverseitig geprüft und im Audit-Log dokumentiert.',
                      ),
                    ),
                  ],
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
        FilledButton.icon(
          onPressed: teamIds.isEmpty ||
                  (role == UserRole.player && playerId == null)
              ? null
              : () => Navigator.pop(
                    context,
                    _ApprovalDecision(
                      role: role,
                      teamIds: teamIds.toList(),
                      playerId: playerId,
                    ),
                  ),
          icon: const Icon(Icons.verified_user_rounded),
          label: const Text('Freigeben'),
        ),
      ],
    );
  }

  String _roleLabel(UserRole value) => switch (value) {
        UserRole.superAdmin => 'Systemadministration',
        UserRole.clubAdmin => 'Vereinsadministration',
        UserRole.youthDirector => 'Jugendleitung',
        UserRole.coach || UserRole.trainer => 'Trainer/in',
        UserRole.assistantCoach => 'Co-Trainer/in',
        UserRole.teamManager => 'Teamorganisation',
        UserRole.trainerAdmin => 'Trainer-Administration',
        UserRole.parent => 'Elternteil',
        UserRole.player => 'Spieler/in',
        UserRole.readOnly => 'Lesender Zugriff',
      };
}

class _ApprovalDecision {
  const _ApprovalDecision({
    required this.role,
    required this.teamIds,
    this.playerId,
  });

  final UserRole role;
  final List<String> teamIds;
  final String? playerId;
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
