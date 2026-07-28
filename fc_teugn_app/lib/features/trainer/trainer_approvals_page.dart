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
                    onNeedsInfo: (user) => _reviewWithoutApproval(
                      context,
                      ref,
                      user,
                      status: AccountStatus.pending,
                      reviewStatus: RegistrationReviewStatus.needsInfo,
                      title: 'Rückfrage markieren',
                    ),
                    onReject: (user) => _reviewWithoutApproval(
                      context,
                      ref,
                      user,
                      status: AccountStatus.rejected,
                      reviewStatus: RegistrationReviewStatus.completed,
                      title: 'Registrierung ablehnen',
                    ),
                    onDetails: (user) => _showDetails(context, user),
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
            relationship: decision.relationship,
            adminNote: decision.adminNote,
            reviewStatus: RegistrationReviewStatus.completed,
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

  Future<void> _reviewWithoutApproval(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
    {
    required AccountStatus status,
    required RegistrationReviewStatus reviewStatus,
    required String title,
    }
  ) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: note,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Interne Notiz / Begründung *',
              hintText: 'Was muss geklärt werden?',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note.text.trim().isNotEmpty),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    try {
      if (confirmed != true) return;
      await ref.read(repositoryProvider).approveUser(
            user.id,
            status: status,
            adminNote:
                status == AccountStatus.rejected ? note.text.trim() : null,
            applicantMessage: reviewStatus ==
                    RegistrationReviewStatus.needsInfo
                ? note.text.trim()
                : null,
            reviewStatus: reviewStatus,
          );
      _refresh(ref);
    } finally {
      note.dispose();
    }
  }

  Future<void> _showDetails(BuildContext context, AppUser user) {
    final request = user.registrationRequest;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Registrierung · ${user.name}'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: 'E-Mail', value: user.email),
                _DetailRow(label: 'Telefon', value: user.phone ?? 'Nicht angegeben'),
                _DetailRow(
                  label: 'Gewünschte Rolle',
                  value: request == null
                      ? user.roleLabel
                      : _roleLabel(request.requestedRole),
                ),
                if (request?.childName != null)
                  _DetailRow(label: 'Kind', value: request!.childName!),
                if (request?.relationship != null)
                  _DetailRow(
                    label: 'Beziehung',
                    value: _relationshipLabel(request!.relationship!),
                  ),
                _DetailRow(
                  label: 'Mannschaften',
                  value: (request?.requestedTeams ?? user.memberships)
                      .map((item) => '${item.ageGroupCode} · ${item.teamName}')
                      .join(', '),
                ),
                _DetailRow(
                  label: 'Push-Einwilligung',
                  value: request?.pushOptIn == true ? 'Erteilt' : 'Nicht erteilt',
                ),
                if (request?.adminNote?.isNotEmpty == true)
                  _DetailRow(label: 'Adminnotiz', value: request!.adminNote!),
                if (request?.applicantMessage?.isNotEmpty == true)
                  _DetailRow(
                    label: 'Nachricht an Mitglied',
                    value: request!.applicantMessage!,
                  ),
                const SizedBox(height: 18),
                Text(
                  'Änderungshistorie',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (request == null || request.history.isEmpty)
                  const Text('Für diesen Bestandsaccount liegt keine Registrierungshistorie vor.')
                else
                  for (final item in request.history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(
                        item.note?.isNotEmpty == true
                            ? item.note!
                            : 'Status aktualisiert',
                      ),
                      subtitle: Text(
                        '${_date(item.createdAt)} · ${item.actorName ?? 'System'}',
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(pendingUsersProvider);
    ref.invalidate(membersProvider);
    ref.invalidate(organizationProvider);
  }
}

class _PendingList extends StatefulWidget {
  const _PendingList({
    required this.value,
    required this.organization,
    required this.onApprove,
    required this.onNeedsInfo,
    required this.onReject,
    required this.onDetails,
  });

  final AsyncValue<List<AppUser>> value;
  final OrganizationContext? organization;
  final ValueChanged<AppUser> onApprove;
  final ValueChanged<AppUser> onNeedsInfo;
  final ValueChanged<AppUser> onReject;
  final ValueChanged<AppUser> onDetails;

  @override
  State<_PendingList> createState() => _PendingListState();
}

class _PendingListState extends State<_PendingList> {
  String _query = '';
  UserRole? _role;
  String? _teamId;

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
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
        final query = _query.toLowerCase();
        final filtered = users.where((user) {
          final request = user.registrationRequest;
          final matchesQuery = query.isEmpty ||
              user.name.toLowerCase().contains(query) ||
              user.email.toLowerCase().contains(query) ||
              (request?.childName?.toLowerCase().contains(query) ?? false);
          final matchesRole =
              _role == null || request?.requestedRole == _role || user.role == _role;
          final requestedTeams = request?.requestedTeams ?? user.memberships;
          final matchesTeam =
              _teamId == null || requestedTeams.any((team) => team.teamId == _teamId);
          return matchesQuery && matchesRole && matchesTeam;
        }).toList();
        return ListView.separated(
          itemCount: filtered.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 250,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Name, E-Mail oder Kind',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<UserRole?>(
                          initialValue: _role,
                          decoration: const InputDecoration(labelText: 'Rolle'),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Alle Rollen')),
                            DropdownMenuItem(
                              value: UserRole.parent,
                              child: Text('Eltern'),
                            ),
                            DropdownMenuItem(
                              value: UserRole.player,
                              child: Text('Spieler'),
                            ),
                            DropdownMenuItem(
                              value: UserRole.coach,
                              child: Text('Trainer'),
                            ),
                            DropdownMenuItem(
                              value: UserRole.assistantCoach,
                              child: Text('Co-Trainer'),
                            ),
                            DropdownMenuItem(
                              value: UserRole.teamManager,
                              child: Text('Organisation'),
                            ),
                          ],
                          onChanged: (value) => setState(() => _role = value),
                        ),
                      ),
                      if (widget.organization != null)
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String?>(
                            initialValue: _teamId,
                            decoration:
                                const InputDecoration(labelText: 'Mannschaft'),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Alle Mannschaften'),
                              ),
                              for (final team in widget.organization!.teams)
                                DropdownMenuItem(
                                  value: team.id,
                                  child: Text(team.displayName),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _teamId = value),
                          ),
                        ),
                      Chip(label: Text('${filtered.length} Treffer')),
                    ],
                  ),
                ),
              );
            }
            final user = filtered[index - 1];
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
                    PopupMenuButton<String>(
                      tooltip: 'Aktionen',
                      onSelected: (value) {
                        if (value == 'details') widget.onDetails(user);
                        if (value == 'question') widget.onNeedsInfo(user);
                        if (value == 'reject') widget.onReject(user);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'details',
                          child: Text('Details & Historie'),
                        ),
                        PopupMenuItem(
                          value: 'question',
                          child: Text('Rückfrage markieren'),
                        ),
                        PopupMenuItem(
                          value: 'reject',
                          child: Text('Ablehnen'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed:
                          widget.organization == null
                              ? null
                              : () => widget.onApprove(user),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Prüfen'),
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
        AccountStatus.rejected => 'Abgelehnt',
        AccountStatus.blocked => 'Blockiert',
        AccountStatus.archived => 'Archiviert',
      };
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({
    required this.user,
    required this.organization,
    required this.players,
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
  late final TextEditingController adminNote;
  late String relationship;

  @override
  void initState() {
    super.initState();
    role = widget.user.role;
    teamIds = widget.user.memberships.isEmpty
        ? {widget.organization.currentTeam.id}
        : widget.user.memberships.map((item) => item.teamId).toSet();
    adminNote = TextEditingController(
      text: widget.user.registrationRequest?.adminNote,
    );
    relationship =
        widget.user.registrationRequest?.relationship ?? 'GUARDIAN';
  }

  @override
  void dispose() {
    adminNote.dispose();
    super.dispose();
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
              if (role == UserRole.player || role == UserRole.parent) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: playerId,
                  decoration: InputDecoration(
                    labelText: role == UserRole.parent
                        ? 'Kind / Spielerprofil *'
                        : 'Verknüpftes Spielerprofil *',
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
                if (role == UserRole.parent) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: relationship,
                    decoration: const InputDecoration(
                      labelText: 'Beziehung zum Kind',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'MOTHER', child: Text('Mutter')),
                      DropdownMenuItem(value: 'FATHER', child: Text('Vater')),
                      DropdownMenuItem(
                        value: 'GUARDIAN',
                        child: Text('Sorgeberechtigte Person'),
                      ),
                      DropdownMenuItem(value: 'OTHER', child: Text('Andere')),
                    ],
                    onChanged: (value) =>
                        setState(() => relationship = value!),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              TextField(
                controller: adminNote,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Interne Prüfnotiz',
                ),
              ),
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
                  ((role == UserRole.player || role == UserRole.parent) &&
                      playerId == null)
              ? null
              : () => Navigator.pop(
                    context,
                    _ApprovalDecision(
                      role: role,
                      teamIds: teamIds.toList(),
                      playerId: playerId,
                      relationship:
                          role == UserRole.parent ? relationship : null,
                      adminNote: adminNote.text.trim(),
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
    this.relationship,
    this.adminNote,
  });

  final UserRole role;
  final List<String> teamIds;
  final String? playerId;
  final String? relationship;
  final String? adminNote;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
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

String _relationshipLabel(String value) => switch (value) {
      'MOTHER' => 'Mutter',
      'FATHER' => 'Vater',
      'GUARDIAN' => 'Sorgeberechtigte Person',
      _ => 'Andere Beziehung',
    };
