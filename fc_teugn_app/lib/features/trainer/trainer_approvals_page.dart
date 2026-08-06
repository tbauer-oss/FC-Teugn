import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/data_repository.dart';
import '../../core/models/organization.dart';
import '../../core/models/player.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/role_permissions.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class TrainerApprovalsPage extends ConsumerWidget {
  const TrainerApprovalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingUsersProvider);
    final members = ref.watch(membersProvider);
    final organization = ref.watch(organizationProvider).valueOrNull;
    final players =
        ref.watch(playersProvider).valueOrNull ?? const <PlayerModel>[];
    final currentUser = ref.watch(authProvider).user;
    final mobile = MediaQuery.sizeOf(context).width < 600;

    return PageScaffold(
      title: 'Mitglieder & Freigaben',
      subtitle:
          'Anfragen prüfen, Rollen festlegen und Zugriffe gezielt Mannschaften zuordnen.',
      action: FilledButton.icon(
        onPressed: organization == null
            ? null
            : () => _createMember(
                  context,
                  ref,
                  organization,
                  players,
                  currentUser?.role == UserRole.superAdmin,
                ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Mitglied anlegen'),
      ),
      child: mobile
          ? _MobileMemberTabs(
              pending: pending,
              members: members,
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
              onRetryPending: () => ref.invalidate(pendingUsersProvider),
              onRetryMembers: () => ref.invalidate(membersProvider),
              onEdit: organization == null
                  ? null
                  : (user) => _editMember(
                        context,
                        ref,
                        user,
                        organization,
                        players,
                        currentUser?.role == UserRole.superAdmin,
                      ),
              onPermissions: currentUser?.role == UserRole.superAdmin
                  ? (user) => _showPermissions(context, ref, user)
                  : null,
            )
          : DefaultTabController(
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
                              'Offene Anfragen (${pending.valueOrNull?.length ?? '–'})',
                        ),
                        Tab(
                          text:
                              'Mitglieder (${members.valueOrNull?.length ?? '–'})',
                        ),
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
                          onApprove: (user) => _approve(
                            context,
                            ref,
                            user,
                            organization,
                            players,
                          ),
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
                          onRetry: () => ref.invalidate(pendingUsersProvider),
                        ),
                        _MemberList(
                          value: members,
                          onRetry: () => ref.invalidate(membersProvider),
                          onEdit: organization == null
                              ? null
                              : (user) => _editMember(
                                    context,
                                    ref,
                                    user,
                                    organization,
                                    players,
                                    currentUser?.role == UserRole.superAdmin,
                                  ),
                          onPermissions: currentUser?.role ==
                                  UserRole.superAdmin
                              ? (user) => _showPermissions(context, ref, user)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _createMember(
    BuildContext context,
    WidgetRef ref,
    OrganizationContext organization,
    List<PlayerModel> players,
    bool actorIsSuperAdmin,
  ) async {
    final draft = await showDialog<_MemberDraft>(
      context: context,
      builder: (context) => _CreateMemberDialog(
        organization: organization,
        players: players,
        actorIsSuperAdmin: actorIsSuperAdmin,
      ),
    );
    if (draft == null || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).createMember(
            name: draft.name,
            email: draft.email,
            phone: draft.phone,
            password: draft.password,
            role: draft.role,
            teamIds: draft.teamIds,
            playerId: draft.playerId,
          );
      _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${draft.name} wurde angelegt.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mitglied konnte nicht angelegt werden. '
              'Prüfe E-Mail-Adresse, Passwort und Mannschaftszuordnung.',
            ),
          ),
        );
      }
    }
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
        actorIsSuperAdmin:
            ref.read(authProvider).user?.role == UserRole.superAdmin,
      ),
    );
    if (decision == null) return;
    try {
      await ref.read(repositoryProvider).approveUser(
            user.id,
            status: decision.status,
            role: decision.role,
            teamIds: decision.teamIds,
            teamRoles: decision.teamRoles,
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
          const SnackBar(
              content: Text('Freigabe konnte nicht gespeichert werden.')),
        );
      }
    }
  }

  Future<void> _editMember(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
    OrganizationContext organization,
    List<PlayerModel> players,
    bool actorIsSuperAdmin,
  ) async {
    final decision = await showDialog<_ApprovalDecision>(
      context: context,
      builder: (context) => _ApprovalDialog(
        user: user,
        organization: organization,
        players: players,
        actorIsSuperAdmin: actorIsSuperAdmin,
        editing: true,
      ),
    );
    if (decision == null) return;
    try {
      await ref.read(repositoryProvider).approveUser(
            user.id,
            status: decision.status,
            role: decision.role,
            teamIds: decision.teamIds,
            teamRoles: decision.teamRoles,
            playerId: decision.playerId,
            relationship: decision.relationship,
            adminNote: decision.adminNote,
          );
      _refresh(ref);
      ref.invalidate(playersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} wurde aktualisiert.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mitgliedseinstellungen konnten nicht gespeichert werden.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showPermissions(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) =>
      showDialog<void>(
        context: context,
        builder: (context) => MemberPermissionsDialog(
          user: user,
          repository: ref.read(repositoryProvider),
        ),
      );

  Future<void> _reviewWithoutApproval(
    BuildContext context,
    WidgetRef ref,
    AppUser user, {
    required AccountStatus status,
    required RegistrationReviewStatus reviewStatus,
    required String title,
  }) async {
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
            onPressed: () =>
                Navigator.pop(context, note.text.trim().isNotEmpty),
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
            applicantMessage: reviewStatus == RegistrationReviewStatus.needsInfo
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
                _DetailRow(
                    label: 'Telefon', value: user.phone ?? 'Nicht angegeben'),
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
                    value: guardianRelationshipLabel(request!.relationship!),
                  ),
                _DetailRow(
                  label: 'Mannschaften',
                  value: (request?.requestedTeams ?? user.memberships)
                      .map((item) => '${item.ageGroupCode} · ${item.teamName}')
                      .join(', '),
                ),
                _DetailRow(
                  label: 'Push-Einwilligung',
                  value:
                      request?.pushOptIn == true ? 'Erteilt' : 'Nicht erteilt',
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
                  const Text(
                      'Für diesen Bestandsaccount liegt keine Registrierungshistorie vor.')
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

class _MobileMemberTabs extends StatefulWidget {
  const _MobileMemberTabs({
    required this.pending,
    required this.members,
    required this.organization,
    required this.onApprove,
    required this.onNeedsInfo,
    required this.onReject,
    required this.onDetails,
    required this.onRetryPending,
    required this.onRetryMembers,
    required this.onEdit,
    required this.onPermissions,
  });

  final AsyncValue<List<AppUser>> pending;
  final AsyncValue<List<AppUser>> members;
  final OrganizationContext? organization;
  final ValueChanged<AppUser> onApprove;
  final ValueChanged<AppUser> onNeedsInfo;
  final ValueChanged<AppUser> onReject;
  final ValueChanged<AppUser> onDetails;
  final VoidCallback onRetryPending;
  final VoidCallback onRetryMembers;
  final ValueChanged<AppUser>? onEdit;
  final ValueChanged<AppUser>? onPermissions;

  @override
  State<_MobileMemberTabs> createState() => _MobileMemberTabsState();
}

class _MobileMemberTabsState extends State<_MobileMemberTabs> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: [
            ButtonSegment(
              value: 0,
              label: Text(
                'Anfragen (${widget.pending.valueOrNull?.length ?? '–'})',
              ),
            ),
            ButtonSegment(
              value: 1,
              label: Text(
                'Mitglieder (${widget.members.valueOrNull?.length ?? '–'})',
              ),
            ),
          ],
          selected: {_selectedIndex},
          onSelectionChanged: (selection) {
            setState(() => _selectedIndex = selection.first);
          },
        ),
        const SizedBox(height: 14),
        if (_selectedIndex == 0)
          _PendingList(
            value: widget.pending,
            organization: widget.organization,
            onApprove: widget.onApprove,
            onNeedsInfo: widget.onNeedsInfo,
            onReject: widget.onReject,
            onDetails: widget.onDetails,
            onRetry: widget.onRetryPending,
            embedded: true,
          )
        else
          _MemberList(
            value: widget.members,
            onRetry: widget.onRetryMembers,
            onEdit: widget.onEdit,
            onPermissions: widget.onPermissions,
            embedded: true,
          ),
      ],
    );
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
    required this.onRetry,
    this.embedded = false,
  });

  final AsyncValue<List<AppUser>> value;
  final OrganizationContext? organization;
  final ValueChanged<AppUser> onApprove;
  final ValueChanged<AppUser> onNeedsInfo;
  final ValueChanged<AppUser> onReject;
  final ValueChanged<AppUser> onDetails;
  final VoidCallback onRetry;
  final bool embedded;

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
      loading: () => const Center(
        child: LogoLoadingPanel(message: 'Freigaben werden geladen …'),
      ),
      error: (_, __) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Freigaben nicht erreichbar',
        message: 'Die offenen Anfragen konnten nicht geladen werden.',
        action: FilledButton.icon(
          onPressed: widget.onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut laden'),
        ),
      ),
      data: (users) {
        final mobile = MediaQuery.sizeOf(context).width < 600;
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
          final matchesRole = _role == null ||
              request?.requestedRole == _role ||
              user.role == _role;
          final requestedTeams = request?.requestedTeams ?? user.memberships;
          final matchesTeam = _teamId == null ||
              requestedTeams.any((team) => team.teamId == _teamId);
          return matchesQuery && matchesRole && matchesTeam;
        }).toList();
        return ListView.separated(
          shrinkWrap: widget.embedded,
          physics:
              widget.embedded ? const NeverScrollableScrollPhysics() : null,
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
                        width: mobile ? double.infinity : 250,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Name, E-Mail oder Kind',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      SizedBox(
                        width: mobile ? double.infinity : 190,
                        child: DropdownButtonFormField<UserRole?>(
                          initialValue: _role,
                          decoration: const InputDecoration(labelText: 'Rolle'),
                          items: const [
                            DropdownMenuItem(
                                value: null, child: Text('Alle Rollen')),
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
                          width: mobile ? double.infinity : 220,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            AppColors.orange.withValues(alpha: .18),
                        child: Text(
                          _initials(user.name),
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${user.email}\n${user.roleLabel}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (user.createdAt != null)
                              Text(
                                'Registriert am ${_date(user.createdAt!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
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
                      FilledButton.icon(
                        onPressed: widget.organization == null
                            ? null
                            : () => widget.onApprove(user),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Prüfen'),
                      ),
                    ],
                  );
                  return Padding(
                    padding: EdgeInsets.all(compact ? 14 : 18),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              identity,
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: identity),
                              const SizedBox(width: 12),
                              actions,
                            ],
                          ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.value,
    required this.onRetry,
    required this.onEdit,
    required this.onPermissions,
    this.embedded = false,
  });

  final AsyncValue<List<AppUser>> value;
  final VoidCallback onRetry;
  final ValueChanged<AppUser>? onEdit;
  final ValueChanged<AppUser>? onPermissions;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(
        child: LogoLoadingPanel(message: 'Mitglieder werden geladen …'),
      ),
      error: (_, __) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Mitglieder nicht erreichbar',
        message: 'Die Mitgliederliste konnte nicht geladen werden.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut laden'),
        ),
      ),
      data: (users) {
        if (users.isEmpty) {
          return const EmptyState(
            icon: Icons.group_off_outlined,
            title: 'Noch keine Mitglieder',
            message: 'Freigegebene Mitglieder werden hier angezeigt.',
          );
        }
        return ListView.separated(
          shrinkWrap: embedded,
          physics: embedded ? const NeverScrollableScrollPhysics() : null,
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = users[index];
            final approved = user.status == AccountStatus.approved;
            return Card(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final status = Chip(
                    avatar: Icon(
                      approved
                          ? Icons.check_circle_rounded
                          : Icons.block_rounded,
                      size: 16,
                      color: approved ? AppColors.teal : Colors.redAccent,
                    ),
                    label: Text(
                      approved ? 'Freigegeben' : _status(user.status),
                    ),
                  );
                  final edit = IconButton.filledTonal(
                    tooltip: 'Rolle, Mannschaften und Rechte bearbeiten',
                    onPressed: onEdit == null ? null : () => onEdit!(user),
                    icon: const Icon(Icons.manage_accounts_outlined),
                  );
                  final permissions = IconButton.filledTonal(
                    tooltip: 'Individuelle Rechte festlegen',
                    onPressed: onPermissions == null
                        ? null
                        : () => onPermissions!(user),
                    icon: const Icon(Icons.security_rounded),
                  );
                  final memberships = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.badge_outlined, size: 15),
                        label: Text(user.roleLabel),
                      ),
                      for (final membership in user.memberships)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.groups_outlined, size: 15),
                          label: Text(
                            '${membership.ageGroupCode} · '
                            '${membership.teamName} · '
                            '${_teamRoleLabel(membership.role)}',
                          ),
                        ),
                      for (final link in user.parentPlayers)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.family_restroom_rounded,
                            size: 15,
                          ),
                          label: Text(
                            '${guardianRelationshipLabel(link.relationship)} von '
                            '${link.playerName}'
                            '${link.ageGroupCode.isEmpty ? '' : ' · ${link.ageGroupCode}'}',
                          ),
                        ),
                    ],
                  );
                  return Padding(
                    padding: EdgeInsets.all(compact ? 14 : 10),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    child: Text(_initials(user.name)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        Text(
                                          user.email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.muted,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (onPermissions != null) permissions,
                                  edit,
                                ],
                              ),
                              const SizedBox(height: 10),
                              memberships,
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: status,
                              ),
                            ],
                          )
                        : ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              child: Text(_initials(user.name)),
                            ),
                            title: Text(user.name),
                            subtitle: Text(
                              [
                                user.roleLabel,
                                if (user.memberships.isNotEmpty)
                                  user.memberships
                                      .map(
                                        (item) =>
                                            '${item.ageGroupCode}-Jugend ${item.teamName} (${_teamRoleLabel(item.role)})',
                                      )
                                      .join(', '),
                              ].join(' · '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                status,
                                const SizedBox(width: 8),
                                if (onPermissions != null) ...[
                                  permissions,
                                  const SizedBox(width: 8),
                                ],
                                edit,
                              ],
                            ),
                          ),
                  );
                },
              ),
            );
          },
        );
      },
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

class MemberPermissionsDialog extends StatefulWidget {
  const MemberPermissionsDialog({
    super.key,
    required this.user,
    required this.repository,
  });

  final AppUser user;
  final DataRepository repository;

  @override
  State<MemberPermissionsDialog> createState() =>
      _MemberPermissionsDialogState();
}

class _MemberPermissionsDialogState extends State<MemberPermissionsDialog> {
  late Future<MemberPermissionProfile> profile;
  String? _savingPermission;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    profile = widget.repository.memberPermissions(widget.user.id);
  }

  @override
  Widget build(BuildContext context) => AdaptiveDialogScaffold(
        title: 'Individuelle Rechte · ${widget.user.name}',
        subtitle:
            'Rollenstandard, individuelle Freigaben und Entzüge transparent verwalten.',
        content: FutureBuilder<MemberPermissionProfile>(
          future: profile,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 220,
                child: Center(
                  child: LogoLoadingPanel(
                    message: 'Berechtigungen werden geladen …',
                    compact: true,
                  ),
                ),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Text('Rechte konnten nicht geladen werden.');
            }
            final value = snapshot.data!;
            final grouped = _groupPermissions(allRolePermissions);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Die Rolle bleibt die Vorgabe. Einzelne Rechte können '
                  'zusätzlich erlaubt oder ausdrücklich entzogen werden; '
                  'ein Entzug hat Vorrang.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final entry in grouped.entries) ...[
                  _PermissionSection(
                    title: entry.key,
                    permissions: entry.value,
                    profile: value,
                    savingPermission: _savingPermission,
                    onChanged: _updatePermission,
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: _resetting || _savingPermission != null ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(
              _resetting ? 'Wird zurückgesetzt …' : 'Alle auf Rollenstandard',
              textAlign: TextAlign.center,
            ),
          ),
          FilledButton(
            onPressed: _resetting || _savingPermission != null
                ? null
                : () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      );

  Future<void> _updatePermission(
    RolePermission permission,
    String state,
  ) async {
    if (_savingPermission != null || _resetting) return;
    setState(() => _savingPermission = permission.code);
    try {
      final updated = await widget.repository.updateMemberPermission(
        userId: widget.user.id,
        permission: permission.code,
        state: state,
      );
      if (!mounted) return;
      setState(() => profile = Future.value(updated));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Das individuelle Recht konnte nicht gespeichert werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPermission = null);
    }
  }

  Future<void> _reset() async {
    setState(() => _resetting = true);
    try {
      final updated =
          await widget.repository.resetMemberPermissions(widget.user.id);
      if (!mounted) return;
      setState(() => profile = Future.value(updated));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Rechte konnten nicht zurückgesetzt werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    required this.permissions,
    required this.profile,
    required this.savingPermission,
    required this.onChanged,
  });

  final String title;
  final List<RolePermission> permissions;
  final MemberPermissionProfile profile;
  final String? savingPermission;
  final Future<void> Function(RolePermission, String) onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: ValueKey('permission-category-$title'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 6),
          for (final permission in permissions)
            _PermissionRow(
              permission: permission,
              profile: profile,
              saving: savingPermission == permission.code,
              disabled: savingPermission != null,
              onChanged: (state) => onChanged(permission, state),
            ),
        ],
      );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.profile,
    required this.saving,
    required this.disabled,
    required this.onChanged,
  });

  final RolePermission permission;
  final MemberPermissionProfile profile;
  final bool saving;
  final bool disabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final effective =
              profile.effectivePermissions.contains(permission.code);
          final roleDefault = profile.rolePermissions.contains(permission.code);
          final selector = DropdownButtonFormField<String>(
            key: ValueKey('permission-selector-${permission.code}'),
            initialValue: profile.overrides[permission.code] ?? 'DEFAULT',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Individuelle Einstellung',
              suffixIcon: saving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            items: const [
              DropdownMenuItem(
                value: 'DEFAULT',
                child: Text('Rollenstandard'),
              ),
              DropdownMenuItem(
                value: 'ALLOW',
                child: Text('Zusätzlich erlauben'),
              ),
              DropdownMenuItem(
                value: 'DENY',
                child: Text('Entziehen'),
              ),
            ],
            onChanged: disabled
                ? null
                : (state) {
                    if (state != null) onChanged(state);
                  },
          );
          final description = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                effective ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: effective ? AppColors.success : Colors.redAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      permission.label,
                      key: ValueKey('permission-label-${permission.code}'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${roleDefault ? 'Durch Rolle vorgesehen' : 'Nicht in der Rolle enthalten'} '
                      '· ${effective ? 'wirksam' : 'nicht wirksam'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final stacked = constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.4;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: .55),
                ),
              ),
            ),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      description,
                      const SizedBox(height: 10),
                      selector,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: description),
                      const SizedBox(width: 18),
                      SizedBox(width: 230, child: selector),
                    ],
                  ),
          );
        },
      );
}

Map<String, List<RolePermission>> _groupPermissions(
  List<RolePermission> permissions,
) {
  final grouped = <String, List<RolePermission>>{};
  for (final permission in permissions) {
    grouped
        .putIfAbsent(_permissionCategory(permission.code), () => [])
        .add(permission);
  }
  return grouped;
}

String _permissionCategory(String code) => switch (code) {
      'VIEW_TEAM' ||
      'MANAGE_TEAM' ||
      'MANAGE_ORGANIZATION' =>
        'Mannschaft & Verein',
      'MANAGE_MEMBERS' => 'Mitgliederverwaltung',
      'MANAGE_PLAYERS' ||
      'VIEW_SENSITIVE_PLAYER' ||
      'MANAGE_SENSITIVE_PLAYER' ||
      'MANAGE_DOCUMENTS' ||
      'MANAGE_DEVELOPMENT' =>
        'Spieler & Kader',
      'MANAGE_EVENTS' || 'RESPOND_ATTENDANCE' => 'Termine & Rückmeldungen',
      'MANAGE_LINEUPS' || 'MANAGE_LIVE_TICKER' => 'Spiele & Aufstellung',
      'VIEW_PLAYER_STATS' || 'MANAGE_STATISTICS' => 'Statistiken',
      'MANAGE_TRAINING' => 'Training & Plätze',
      'SEND_ANNOUNCEMENTS' => 'Nachrichten',
      'MANAGE_IMPORTS' => 'Datenimport',
      'VIEW_TEAM_OPERATIONS' || 'MANAGE_TEAM_OPERATIONS' => 'Organisation',
      _ => 'Weitere Rechte',
    };

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({
    required this.user,
    required this.organization,
    required this.players,
    required this.actorIsSuperAdmin,
    this.editing = false,
  });

  final AppUser user;
  final OrganizationContext organization;
  final List<PlayerModel> players;
  final bool actorIsSuperAdmin;
  final bool editing;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late UserRole role;
  late AccountStatus status;
  late Set<String> teamIds;
  late Map<String, UserRole> teamRoles;
  String? playerId;
  late final TextEditingController adminNote;
  late String relationship;

  @override
  void initState() {
    super.initState();
    role = widget.user.role;
    status = widget.editing ? widget.user.status : AccountStatus.approved;
    teamIds = widget.user.memberships.isEmpty
        ? {widget.organization.currentTeam.id}
        : widget.user.memberships.map((item) => item.teamId).toSet();
    teamRoles = {
      for (final membership in widget.user.memberships)
        membership.teamId: _teamFunction(membership.role),
    };
    for (final teamId in teamIds) {
      teamRoles.putIfAbsent(teamId, () => _teamFunction(role));
    }
    adminNote = TextEditingController(
      text: widget.user.registrationRequest?.adminNote,
    );
    relationship = widget.user.registrationRequest?.relationship ?? 'GUARDIAN';
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
        ? [
            if (widget.actorIsSuperAdmin) UserRole.superAdmin,
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
      title: Text(
        widget.editing
            ? '${widget.user.name} verwalten'
            : '${widget.user.name} freigeben',
      ),
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
                decoration: const InputDecoration(
                  labelText: 'Systemweite Hauptrolle',
                  helperText:
                      'Sie bestimmt die grundlegenden Rechte des Kontos.',
                ),
                items: [
                  for (final item in roles)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_roleLabel(item)),
                    ),
                ],
                onChanged: (value) => setState(() => role = value!),
              ),
              if (widget.editing) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<AccountStatus>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Kontostatus'),
                  items: const [
                    DropdownMenuItem(
                      value: AccountStatus.approved,
                      child: Text('Freigegeben'),
                    ),
                    DropdownMenuItem(
                      value: AccountStatus.pending,
                      child: Text('Ausstehend'),
                    ),
                    DropdownMenuItem(
                      value: AccountStatus.blocked,
                      child: Text('Gesperrt'),
                    ),
                    DropdownMenuItem(
                      value: AccountStatus.archived,
                      child: Text('Archiviert'),
                    ),
                    DropdownMenuItem(
                      value: AccountStatus.rejected,
                      child: Text('Abgelehnt'),
                    ),
                  ],
                  onChanged: (value) => setState(() => status = value!),
                ),
              ],
              const SizedBox(height: 16),
              _PermissionPreview(role: role),
              const SizedBox(height: 20),
              Text(
                'Mannschaften',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Mindestens eine Mannschaft auswählen. Die erste Auswahl wird '
                'zum Standardteam. Systemadministratoren besitzen unabhängig '
                'davon systemweiten Zugriff.',
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
                          teamRoles.putIfAbsent(
                            team.id,
                            () => _teamFunction(role),
                          );
                        } else if (teamIds.length > 1) {
                          teamIds.remove(team.id);
                          teamRoles.remove(team.id);
                        }
                      }),
                    ),
                ],
              ),
              if (canManageOrganization && teamIds.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Funktion je Mannschaft',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Hier werden Haupttrainer, Co-Trainer oder '
                  'Teamorganisation zugeordnet. Diese Funktion ergänzt die '
                  'Hauptrolle und ersetzt niemals die Systemadministration.',
                ),
                const SizedBox(height: 10),
                for (final team in widget.organization.teams.where(
                  (team) => teamIds.contains(team.id),
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<UserRole>(
                      key: ValueKey('team-function-${team.id}'),
                      initialValue: teamRoles[team.id] ?? _teamFunction(role),
                      decoration: InputDecoration(
                        labelText: team.displayName,
                        prefixIcon: const Icon(Icons.sports_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: UserRole.coach,
                          child: Text('Haupttrainer/in'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.assistantCoach,
                          child: Text('Co-Trainer/in'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.teamManager,
                          child: Text('Teamorganisation'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.parent,
                          child: Text('Elternteil'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.player,
                          child: Text('Spieler/in'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.readOnly,
                          child: Text('Nur Mannschaft ansehen'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => teamRoles[team.id] = value!),
                    ),
                  ),
              ],
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
              if (role != UserRole.player) ...[
                const SizedBox(height: 20),
                Text(
                  'Eltern-Zuordnung',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Optional: Auch Systemadministration, Vereinsfunktionäre '
                  'und Trainer können Eltern eines Spielers sein. Die '
                  'Hauptrolle und sämtliche Rechte bleiben unverändert.',
                ),
                if (widget.user.parentPlayers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final link in widget.user.parentPlayers)
                        Chip(
                          avatar: const Icon(
                            Icons.family_restroom_rounded,
                            size: 16,
                          ),
                          label: Text(
                            '${link.playerName} · '
                            '${guardianRelationshipLabel(link.relationship)}'
                            '${link.ageGroupCode.isEmpty ? '' : ' · ${link.ageGroupCode}'}',
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: playerId,
                  decoration: const InputDecoration(
                    labelText: 'Weiteres Kind / Spielerprofil (optional)',
                  ),
                  items: [
                    for (final player in widget.players.where(
                      (player) =>
                          teamIds.contains(player.teamId) &&
                          !widget.user.parentPlayers
                              .any((link) => link.playerId == player.id),
                    ))
                      DropdownMenuItem(
                        value: player.id,
                        child: Text(player.fullName),
                      ),
                  ],
                  onChanged: (value) => setState(() => playerId = value),
                ),
                if (playerId != null) ...[
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
                    ],
                    onChanged: (value) => setState(() => relationship = value!),
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
                  (role == UserRole.player &&
                      playerId == null &&
                      !widget.editing)
              ? null
              : () => Navigator.pop(
                    context,
                    _ApprovalDecision(
                      status: status,
                      role: role,
                      teamIds: teamIds.toList(),
                      teamRoles: {
                        for (final teamId in teamIds)
                          teamId: teamRoles[teamId] ?? _teamFunction(role),
                      },
                      playerId: playerId,
                      relationship: role != UserRole.player && playerId != null
                          ? relationship
                          : null,
                      adminNote: adminNote.text.trim(),
                    ),
                  ),
          icon: const Icon(Icons.verified_user_rounded),
          label: Text(widget.editing ? 'Änderungen speichern' : 'Freigeben'),
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

  UserRole _teamFunction(UserRole value) => switch (value) {
        UserRole.coach ||
        UserRole.trainer ||
        UserRole.trainerAdmin =>
          UserRole.coach,
        UserRole.assistantCoach => UserRole.assistantCoach,
        UserRole.teamManager => UserRole.teamManager,
        UserRole.parent => UserRole.parent,
        UserRole.player => UserRole.player,
        _ => UserRole.readOnly,
      };
}

class _PermissionPreview extends StatelessWidget {
  const _PermissionPreview({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final permissions = permissionsForUserRole(role);
    final viewCount = permissions
        .where((permission) => permission.kind == PermissionKind.view)
        .length;
    final editCount = permissions.length - viewCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.navy.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  role == UserRole.superAdmin
                      ? 'Uneingeschränkter Systemzugriff'
                      : '$viewCount Ansichts- und $editCount Bearbeitungsrechte',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final permission in permissions)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    permission.kind == PermissionKind.view
                        ? Icons.visibility_outlined
                        : Icons.edit_outlined,
                    size: 15,
                  ),
                  label: Text(permission.label),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Die Rolle ist die verbindliche Rechte-Vorgabe. '
            'Systemadministration umfasst immer alle Rechte.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CreateMemberDialog extends StatefulWidget {
  const _CreateMemberDialog({
    required this.organization,
    required this.players,
    required this.actorIsSuperAdmin,
  });

  final OrganizationContext organization;
  final List<PlayerModel> players;
  final bool actorIsSuperAdmin;

  @override
  State<_CreateMemberDialog> createState() => _CreateMemberDialogState();
}

class _CreateMemberDialogState extends State<_CreateMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _teamIds = <String>{};
  late UserRole _role;
  bool _obscurePassword = true;
  String? _playerId;

  @override
  void initState() {
    super.initState();
    _role = UserRole.parent;
    _teamIds.add(widget.organization.currentTeam.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = <UserRole>[
      if (widget.actorIsSuperAdmin) UserRole.superAdmin,
      UserRole.clubAdmin,
      UserRole.youthDirector,
      UserRole.coach,
      UserRole.assistantCoach,
      UserRole.teamManager,
      UserRole.parent,
      UserRole.player,
      UserRole.readOnly,
    ];
    return AlertDialog(
      title: const Text('Mitglied anlegen'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail-Adresse *',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Gültige E-Mail-Adresse angeben'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Startpasswort *',
                    helperText:
                        'Mindestens 10 Zeichen; sicher an das Mitglied übermitteln.',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.length ?? 0) < 10
                      ? 'Mindestens 10 Zeichen'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rolle *',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                  items: [
                    for (final role in roles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(_roleLabel(role)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _role = value;
                        if (value != UserRole.player) _playerId = null;
                      });
                    }
                  },
                ),
                if (_role == UserRole.player) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _playerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Spielerprofil *',
                      helperText:
                          'Der Zugang wird fest mit diesem Spielerprofil verbunden.',
                      prefixIcon: Icon(Icons.sports_soccer_rounded),
                    ),
                    items: [
                      for (final player in widget.players.where(
                        (player) => _teamIds.contains(player.teamId),
                      ))
                        DropdownMenuItem(
                          value: player.id,
                          child: Text(
                            '${player.fullName} · '
                            '${player.ageGroupCode ?? ''} ${player.teamName ?? ''}',
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _playerId = value),
                    validator: (value) =>
                        _role == UserRole.player && value == null
                            ? 'Spielerprofil auswählen'
                            : null,
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Jugenden und Mannschaften *',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final team in widget.organization.teams)
                      FilterChip(
                        selected: _teamIds.contains(team.id),
                        label: Text(team.displayName),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _teamIds.add(team.id);
                          } else if (_teamIds.length > 1) {
                            _teamIds.remove(team.id);
                            if (!widget.players.any(
                              (player) =>
                                  player.id == _playerId &&
                                  _teamIds.contains(player.teamId),
                            )) {
                              _playerId = null;
                            }
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate() || _teamIds.isEmpty) return;
            Navigator.pop(
              context,
              _MemberDraft(
                name: _name.text.trim(),
                email: _email.text.trim().toLowerCase(),
                phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                password: _password.text,
                role: _role,
                teamIds: _teamIds.toList(),
                playerId: _playerId,
              ),
            );
          },
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Mitglied anlegen'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;
}

class _MemberDraft {
  const _MemberDraft({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.teamIds,
    this.phone,
    this.playerId,
  });

  final String name;
  final String email;
  final String? phone;
  final String password;
  final UserRole role;
  final List<String> teamIds;
  final String? playerId;
}

class _ApprovalDecision {
  const _ApprovalDecision({
    required this.status,
    required this.role,
    required this.teamIds,
    required this.teamRoles,
    this.playerId,
    this.relationship,
    this.adminNote,
  });

  final AccountStatus status;
  final UserRole role;
  final List<String> teamIds;
  final Map<String, UserRole> teamRoles;
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
      UserRole.parent => 'Elternteil',
      UserRole.player => 'Spieler/in',
      UserRole.trainerAdmin => 'Trainer-Administration',
      UserRole.readOnly => 'Lesender Zugriff',
    };

String _teamRoleLabel(UserRole value) => switch (value) {
      UserRole.coach ||
      UserRole.trainer ||
      UserRole.trainerAdmin =>
        'Haupttrainer/in',
      UserRole.assistantCoach => 'Co-Trainer/in',
      UserRole.teamManager => 'Teamorganisation',
      UserRole.parent => 'Elternteil',
      UserRole.player => 'Spieler/in',
      _ => 'Nur Ansicht',
    };
