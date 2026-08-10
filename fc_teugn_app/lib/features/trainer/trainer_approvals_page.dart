import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'member_overview_filter.dart';

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
      denseMobileHeader: true,
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
              onPasswordHelp: currentUser?.role == UserRole.superAdmin
                  ? (user) => _createPasswordResetLink(context, ref, user)
                  : null,
              onDelete: currentUser?.role == UserRole.superAdmin
                  ? (user) => _deleteMemberAccount(context, ref, user)
                  : null,
              currentUserId: currentUser?.id,
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
                              'Mitglieder & Konten (${members.valueOrNull?.length ?? '–'})',
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
                          organization: organization,
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
                          onPasswordHelp:
                              currentUser?.role == UserRole.superAdmin
                                  ? (user) => _createPasswordResetLink(
                                        context,
                                        ref,
                                        user,
                                      )
                                  : null,
                          onDelete: currentUser?.role == UserRole.superAdmin
                              ? (user) =>
                                  _deleteMemberAccount(context, ref, user)
                              : null,
                          currentUserId: currentUser?.id,
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

  Future<void> _createPasswordResetLink(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sicheren Zugangslink erstellen?'),
        content: Text(
          'Für ${user.name} wird ein einmal nutzbarer Link erstellt. '
          'Er ist 60 Minuten gültig und ersetzt alle älteren Reset-Links.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.key_rounded),
            label: const Text('Link erstellen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref
          .read(repositoryProvider)
          .createMemberPasswordResetLink(user.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Zugangslink bereit'),
          content: SizedBox(
            width: 580,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sende diesen Link persönlich an ${user.name}, zum Beispiel '
                  'per WhatsApp. Er kann nur einmal verwendet werden.',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: SelectableText(result.url),
                ),
                const SizedBox(height: 10),
                Text(
                  'Gültig bis ${_date(result.expiresAt)} · '
                  '${TimeOfDay.fromDateTime(result.expiresAt).format(context)} Uhr',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result.url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Zugangslink wurde kopiert.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Link kopieren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fertig'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Der Zugangslink konnte nicht erstellt werden.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteMemberAccount(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final confirmation = TextEditingController();
    var canDelete = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.delete_forever_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Konto dauerhaft löschen?'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Das Konto von ${user.name} (${user.email}) wird unwiderruflich '
                  'gelöscht. Anmeldung, registrierte Geräte, Mannschafts- und '
                  'Kinderzuordnungen werden entfernt.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Historische Vereins- und Prüfprotokolle bleiben ausschließlich '
                  'anonymisiert erhalten, damit bestehende Spiel- und '
                  'Vereinschroniken nicht beschädigt werden.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmation,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Zur Bestätigung LÖSCHEN eingeben',
                  ),
                  onChanged: (value) {
                    final next = value.trim().toUpperCase() == 'LÖSCHEN';
                    if (next != canDelete) {
                      setDialogState(() => canDelete = next);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed:
                  canDelete ? () => Navigator.pop(dialogContext, true) : null,
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Konto endgültig löschen'),
            ),
          ],
        ),
      ),
    );
    confirmation.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(repositoryProvider).deleteMemberAccount(user.id);
      _refresh(ref);
      ref.invalidate(playersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Das Konto von ${user.name} wurde gelöscht.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Das Konto konnte nicht gelöscht werden. Das eigene oder letzte '
              'Systemadministrationskonto ist besonders geschützt.',
            ),
          ),
        );
      }
    }
  }

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
    required this.onPasswordHelp,
    required this.onDelete,
    required this.currentUserId,
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
  final ValueChanged<AppUser>? onPasswordHelp;
  final ValueChanged<AppUser>? onDelete;
  final String? currentUserId;

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
                'Konten (${widget.members.valueOrNull?.length ?? '–'})',
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
            organization: widget.organization,
            onRetry: widget.onRetryMembers,
            onEdit: widget.onEdit,
            onPermissions: widget.onPermissions,
            onPasswordHelp: widget.onPasswordHelp,
            onDelete: widget.onDelete,
            currentUserId: widget.currentUserId,
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
                  padding: EdgeInsets.all(mobile ? 10 : 14),
                  child: Wrap(
                    spacing: mobile ? 7 : 10,
                    runSpacing: mobile ? 7 : 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: mobile ? double.infinity : 250,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Name, E-Mail oder Kind',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      SizedBox(
                        width: mobile ? double.infinity : 190,
                        child: DropdownButtonFormField<UserRole?>(
                          initialValue: _role,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Rolle',
                            isDense: true,
                          ),
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
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Mannschaft',
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text(
                                  'Alle Mannschaften',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (final team in widget.organization!.teams)
                                DropdownMenuItem(
                                  value: team.id,
                                  child: Text(
                                    team.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _teamId = value),
                          ),
                        ),
                      Chip(
                        visualDensity: mobile
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                        label: Text('${filtered.length} Treffer'),
                      ),
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
                  final childName = user.registrationRequest?.childName?.trim();
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: compact ? 21 : 24,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: compact
                                  ? Theme.of(context).textTheme.titleMedium
                                  : Theme.of(context).textTheme.titleLarge,
                            ),
                            SizedBox(height: compact ? 1 : 3),
                            Text(
                              '${user.email} · ${user.roleLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (childName != null && childName.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.orange.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.child_care_rounded,
                                      size: 15,
                                      color: AppColors.navy,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'Kind: $childName',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
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
                        style: compact
                            ? FilledButton.styleFrom(
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              )
                            : null,
                        onPressed: widget.organization == null
                            ? null
                            : () => widget.onApprove(user),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Prüfen'),
                      ),
                    ],
                  );
                  return Padding(
                    padding: EdgeInsets.all(compact ? 11 : 18),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              identity,
                              const SizedBox(height: 7),
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

class _MemberList extends StatefulWidget {
  const _MemberList({
    required this.value,
    required this.organization,
    required this.onRetry,
    required this.onEdit,
    required this.onPermissions,
    required this.onPasswordHelp,
    required this.onDelete,
    required this.currentUserId,
    this.embedded = false,
  });

  final AsyncValue<List<AppUser>> value;
  final OrganizationContext? organization;
  final VoidCallback onRetry;
  final ValueChanged<AppUser>? onEdit;
  final ValueChanged<AppUser>? onPermissions;
  final ValueChanged<AppUser>? onPasswordHelp;
  final ValueChanged<AppUser>? onDelete;
  final String? currentUserId;
  final bool embedded;

  @override
  State<_MemberList> createState() => _MemberListState();
}

class _MemberListState extends State<_MemberList> {
  final _queryController = TextEditingController();
  String? _ageGroupCode;
  String? _teamId;
  MemberTypeFilter _type = MemberTypeFilter.all;
  AccountStatus? _status;
  RegistrationReviewStatus? _reviewStatus;
  MemberAssignmentFilter _assignment = MemberAssignmentFilter.all;
  MemberSortOrder _sort = MemberSortOrder.nameAscending;
  bool _filtersExpanded = false;

  int get _activeFilterCount => [
        _queryController.text.trim().isNotEmpty,
        _ageGroupCode != null,
        _teamId != null,
        _type != MemberTypeFilter.all,
        _status != null,
        _reviewStatus != null,
        _assignment != MemberAssignmentFilter.all,
        _sort != MemberSortOrder.nameAscending,
      ].where((active) => active).length;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _queryController.clear();
    setState(() {
      _ageGroupCode = null;
      _teamId = null;
      _type = MemberTypeFilter.all;
      _status = null;
      _reviewStatus = null;
      _assignment = MemberAssignmentFilter.all;
      _sort = MemberSortOrder.nameAscending;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
      loading: () => const Center(
        child: LogoLoadingPanel(message: 'Mitglieder werden geladen …'),
      ),
      error: (_, __) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Mitglieder nicht erreichbar',
        message: 'Die Mitgliederliste konnte nicht geladen werden.',
        action: FilledButton.icon(
          onPressed: widget.onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut laden'),
        ),
      ),
      data: (users) {
        if (users.isEmpty) {
          return const EmptyState(
            icon: Icons.group_off_outlined,
            title: 'Noch keine Mitglieder',
            message: 'Alle vorhandenen Konten werden hier angezeigt.',
          );
        }
        final filtered = filterMembersForOverview(
          users,
          query: _queryController.text,
          ageGroupCode: _ageGroupCode,
          teamId: _teamId,
          type: _type,
          status: _status,
          reviewStatus: _reviewStatus,
          assignment: _assignment,
          sort: _sort,
        );
        return ListView.separated(
          shrinkWrap: widget.embedded,
          physics:
              widget.embedded ? const NeverScrollableScrollPhysics() : null,
          itemCount: 1 + (filtered.isEmpty ? 1 : filtered.length),
          separatorBuilder: (_, __) => const SizedBox(height: 7),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildFilterPanel(context, users, filtered.length);
            }
            if (filtered.isEmpty) {
              return EmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'Keine passenden Mitglieder',
                message: 'Die gewählten Filter ergeben aktuell keine Treffer.',
                action: OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Filter zurücksetzen'),
                ),
              );
            }
            return _buildMemberCard(context, filtered[index - 1]);
          },
        );
      },
    );
  }

  Widget _buildFilterPanel(
    BuildContext context,
    List<AppUser> users,
    int filteredCount,
  ) {
    final organization = widget.organization;
    final statusCounts = {
      for (final status in AccountStatus.values)
        status: users.where((user) => user.status == status).length,
    };
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = constraints.maxWidth < 700;
          final showAdvanced = !mobile || _filtersExpanded;
          final teams = (organization?.teams ?? const <TeamSummary>[])
              .where(
                (team) =>
                    _ageGroupCode == null ||
                    team.ageGroup.code == _ageGroupCode,
              )
              .toList();
          return Padding(
            padding: EdgeInsets.all(mobile ? 10 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mitglieder filtern',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '$filteredCount von ${users.length} Konten',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (mobile)
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _filtersExpanded = !_filtersExpanded,
                        ),
                        icon: Icon(
                          _filtersExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text(
                          _activeFilterCount == 0
                              ? 'Filter'
                              : 'Filter ($_activeFilterCount)',
                        ),
                      ),
                    IconButton(
                      tooltip: 'Alle Filter zurücksetzen',
                      onPressed: _activeFilterCount == 0 ? null : _resetFilters,
                      icon: const Icon(Icons.restart_alt_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('member-search-field'),
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Name, E-Mail, Kind oder Mannschaft',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statusChoice(
                        label: 'Alle',
                        count: users.length,
                        value: null,
                      ),
                      for (final status in AccountStatus.values) ...[
                        const SizedBox(width: 6),
                        _statusChoice(
                          label: _accountStatusLabel(status),
                          count: statusCounts[status] ?? 0,
                          value: status,
                        ),
                      ],
                    ],
                  ),
                ),
                if (showAdvanced) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterDropdown<String?>(
                        width: mobile ? constraints.maxWidth : 180,
                        key: ValueKey('member-age-$_ageGroupCode'),
                        label: 'Jugend',
                        value: _ageGroupCode,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Alle Jugenden'),
                          ),
                          for (final ageGroup in organization?.ageGroups ??
                              const <AgeGroupSummary>[])
                            DropdownMenuItem(
                              value: ageGroup.code,
                              child: Text('${ageGroup.code}-Jugend'),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _ageGroupCode = value;
                          _teamId = null;
                        }),
                      ),
                      _filterDropdown<String?>(
                        width: mobile ? constraints.maxWidth : 210,
                        key: ValueKey('member-team-$_teamId-$_ageGroupCode'),
                        label: 'Mannschaft',
                        value: _teamId,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Alle Mannschaften'),
                          ),
                          for (final team in teams)
                            DropdownMenuItem(
                              value: team.id,
                              child: Text(
                                team.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _teamId = value),
                      ),
                      _filterDropdown<MemberTypeFilter>(
                        width: mobile ? constraints.maxWidth : 205,
                        key: ValueKey('member-type-${_type.name}'),
                        label: 'Mitgliedstyp',
                        value: _type,
                        items: [
                          for (final type in MemberTypeFilter.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(_memberTypeLabel(type)),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _type = value ?? MemberTypeFilter.all,
                        ),
                      ),
                      _filterDropdown<MemberAssignmentFilter>(
                        width: mobile ? constraints.maxWidth : 210,
                        key: ValueKey(
                          'member-assignment-${_assignment.name}',
                        ),
                        label: 'Zuordnung',
                        value: _assignment,
                        items: [
                          for (final assignment
                              in MemberAssignmentFilter.values)
                            DropdownMenuItem(
                              value: assignment,
                              child: Text(_assignmentLabel(assignment)),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () =>
                              _assignment = value ?? MemberAssignmentFilter.all,
                        ),
                      ),
                      _filterDropdown<RegistrationReviewStatus?>(
                        width: mobile ? constraints.maxWidth : 195,
                        key: ValueKey('member-review-$_reviewStatus'),
                        label: 'Prüfstatus',
                        value: _reviewStatus,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Alle Prüfstände'),
                          ),
                          for (final status in RegistrationReviewStatus.values)
                            DropdownMenuItem(
                              value: status,
                              child: Text(_reviewStatusLabel(status)),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _reviewStatus = value),
                      ),
                      _filterDropdown<MemberSortOrder>(
                        width: mobile ? constraints.maxWidth : 190,
                        key: ValueKey('member-sort-${_sort.name}'),
                        label: 'Sortierung',
                        value: _sort,
                        items: [
                          for (final sort in MemberSortOrder.values)
                            DropdownMenuItem(
                              value: sort,
                              child: Text(_sortLabel(sort)),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _sort = value ?? MemberSortOrder.nameAscending,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterDropdown<T>({
    required double width,
    required Key key,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      SizedBox(
        width: width,
        child: DropdownButtonFormField<T>(
          key: key,
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: items,
          onChanged: onChanged,
        ),
      );

  Widget _statusChoice({
    required String label,
    required int count,
    required AccountStatus? value,
  }) =>
      ChoiceChip(
        visualDensity: VisualDensity.compact,
        selected: _status == value,
        label: Text('$label ($count)'),
        onSelected: (_) => setState(() => _status = value),
      );

  Widget _buildMemberCard(BuildContext context, AppUser user) {
    final currentUserId = widget.currentUserId;
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final details = <String>[
            user.roleLabel,
            for (final membership in user.memberships.take(3))
              '${membership.ageGroupCode}-Jugend ${membership.teamName} '
                  '(${_teamRoleLabel(membership.role)})',
            for (final link in user.parentPlayers.take(2))
              '${guardianRelationshipLabel(link.relationship)} von '
                  '${link.playerName}',
          ];
          final hiddenDetails =
              user.memberships.length > 3 ? user.memberships.length - 3 : 0;
          final statusChip = Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              _accountStatusIcon(user.status),
              size: 15,
              color: _accountStatusColor(context, user.status),
            ),
            label: Text(_accountStatusLabel(user.status)),
          );
          final canDelete =
              widget.onDelete != null && user.id != currentUserId;
          final actions = <Widget>[
            if (widget.onPermissions != null)
              _memberActionButton(
                tooltip: 'Individuelle Rechte festlegen',
                icon: Icons.security_rounded,
                onPressed: () => widget.onPermissions!(user),
              ),
            if (widget.onPasswordHelp != null)
              _memberActionButton(
                tooltip: 'Sicheren Zugangslink erstellen',
                icon: Icons.key_rounded,
                onPressed: () => widget.onPasswordHelp!(user),
              ),
            _memberActionButton(
              tooltip: 'Rolle und Zuordnungen bearbeiten',
              icon: Icons.manage_accounts_outlined,
              onPressed:
                  widget.onEdit == null ? null : () => widget.onEdit!(user),
            ),
            if (canDelete)
              _memberActionButton(
                tooltip: 'Konto dauerhaft löschen',
                icon: Icons.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error,
                onPressed: () => widget.onDelete!(user),
              ),
          ];
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: compact ? 19 : 20,
                backgroundColor: AppColors.orange.withValues(alpha: .2),
                child: Text(
                  _initials(user.name),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        ...details,
                        if (hiddenDetails > 0) '+$hiddenDetails weitere',
                      ].join(' · '),
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          );
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 9 : 7,
            ),
            child: compact
                ? Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 6),
                          statusChip,
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: actions,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 10),
                      statusChip,
                      const SizedBox(width: 6),
                      ...actions,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _memberActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
  }) =>
      IconButton.filledTonal(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          maximumSize: const Size(36, 36),
          padding: const EdgeInsets.all(7),
          foregroundColor: color,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
      );

  String _accountStatusLabel(AccountStatus value) => switch (value) {
        AccountStatus.pending => 'Ausstehend',
        AccountStatus.approved => 'Freigegeben',
        AccountStatus.rejected => 'Abgelehnt',
        AccountStatus.blocked => 'Blockiert',
        AccountStatus.archived => 'Archiviert',
      };

  IconData _accountStatusIcon(AccountStatus value) => switch (value) {
        AccountStatus.pending => Icons.schedule_rounded,
        AccountStatus.approved => Icons.check_circle_rounded,
        AccountStatus.rejected => Icons.cancel_rounded,
        AccountStatus.blocked => Icons.block_rounded,
        AccountStatus.archived => Icons.archive_rounded,
      };

  Color _accountStatusColor(BuildContext context, AccountStatus value) =>
      switch (value) {
        AccountStatus.pending => Colors.orange.shade800,
        AccountStatus.approved => AppColors.teal,
        AccountStatus.rejected || AccountStatus.blocked =>
          Theme.of(context).colorScheme.error,
        AccountStatus.archived => AppColors.muted,
      };

  String _memberTypeLabel(MemberTypeFilter value) => switch (value) {
        MemberTypeFilter.all => 'Alle Mitgliedstypen',
        MemberTypeFilter.administration => 'Administration & Leitung',
        MemberTypeFilter.trainerTeam => 'Trainer- & Organisationsteam',
        MemberTypeFilter.parents => 'Eltern',
        MemberTypeFilter.players => 'Spieler',
        MemberTypeFilter.readOnly => 'Nur lesender Zugriff',
      };

  String _assignmentLabel(MemberAssignmentFilter value) => switch (value) {
        MemberAssignmentFilter.all => 'Alle Zuordnungen',
        MemberAssignmentFilter.team => 'Mit Mannschaft',
        MemberAssignmentFilter.child => 'Mit Kind-Zuordnung',
        MemberAssignmentFilter.withoutAssignment => 'Ohne Zuordnung',
      };

  String _reviewStatusLabel(RegistrationReviewStatus value) => switch (value) {
        RegistrationReviewStatus.newRequest => 'Neu',
        RegistrationReviewStatus.inReview => 'In Prüfung',
        RegistrationReviewStatus.needsInfo => 'Rückfrage offen',
        RegistrationReviewStatus.completed => 'Prüfung abgeschlossen',
      };

  String _sortLabel(MemberSortOrder value) => switch (value) {
        MemberSortOrder.nameAscending => 'Name A–Z',
        MemberSortOrder.nameDescending => 'Name Z–A',
        MemberSortOrder.newest => 'Neueste zuerst',
        MemberSortOrder.oldest => 'Älteste zuerst',
        MemberSortOrder.role => 'Mitgliedstyp',
        MemberSortOrder.status => 'Kontostatus',
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
      'MANAGE_EVENTS' ||
      'EVENT_DELETE' ||
      'RESPOND_ATTENDANCE' =>
        'Termine & Rückmeldungen',
      'MATCH_DELETE' ||
      'MATCH_CANCEL' ||
      'MATCH_RESCHEDULE' ||
      'LEAGUE_MATCH_CANCEL' ||
      'LEAGUE_MATCH_DELETE' ||
      'LEAGUE_MATCH_RESCHEDULE' ||
      'MANAGE_LINEUPS' ||
      'MANAGE_LIVE_TICKER' =>
        'Spielbetrieb & Liga',
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
