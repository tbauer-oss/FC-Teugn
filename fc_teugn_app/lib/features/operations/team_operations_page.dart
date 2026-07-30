import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/models/team_operations.dart';
import '../../core/providers.dart';

class TeamOperationsPage extends ConsumerStatefulWidget {
  const TeamOperationsPage({super.key});

  @override
  ConsumerState<TeamOperationsPage> createState() => _TeamOperationsPageState();
}

class _TeamOperationsPageState extends ConsumerState<TeamOperationsPage> {
  String? _selectedTeamId;

  void _refresh(String teamId) {
    ref.invalidate(teamOperationsProvider(teamId));
  }

  Future<void> _execute(
    String teamId,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      _refresh(teamId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final organization = ref.watch(organizationProvider);
    return organization.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: _errorMessage(error),
        onRetry: () => ref.invalidate(organizationProvider),
      ),
      data: (organization) {
        final teamId = _selectedTeamId ?? organization.currentTeam.id;
        final overview = ref.watch(teamOperationsProvider(teamId));
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              _PageHeader(
                organization: organization,
                selectedTeamId: teamId,
                onTeamChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedTeamId = value);
                  }
                },
              ),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.task_alt_rounded), text: 'Aufgaben'),
                  Tab(icon: Icon(Icons.inventory_2_rounded), text: 'Material'),
                  Tab(icon: Icon(Icons.checklist_rounded), text: 'Checklisten'),
                ],
              ),
              Expanded(
                child: overview.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _ErrorState(
                    message: _errorMessage(error),
                    onRetry: () => _refresh(teamId),
                  ),
                  data: (data) => TabBarView(
                    children: [
                      _TasksTab(
                        data: data,
                        onCreate: () => _createTask(teamId, data),
                        onStatus: (task, status) => _execute(
                          teamId,
                          () => ref
                              .read(repositoryProvider)
                              .updateTeamTaskStatus(task.id, status),
                          'Aufgabe aktualisiert.',
                        ),
                      ),
                      _EquipmentTab(
                        data: data,
                        onCreate: () => _createEquipment(teamId),
                        onAssign: (item) =>
                            _assignEquipment(teamId, data, item),
                        onReturn: (assignment) => _execute(
                          teamId,
                          () => ref
                              .read(repositoryProvider)
                              .returnEquipment(assignment.id),
                          'Material wurde zurückgenommen.',
                        ),
                      ),
                      _ChecklistsTab(
                        data: data,
                        onCreateTemplate: () =>
                            _createChecklistTemplate(teamId),
                        onStart: (template) => _execute(
                          teamId,
                          () => ref.read(repositoryProvider).startChecklist(
                                teamId: teamId,
                                templateId: template.id,
                              ),
                          'Checkliste wurde gestartet.',
                        ),
                        onToggle: (run, item, value) => _execute(
                          teamId,
                          () => ref.read(repositoryProvider).setChecklistItem(
                                runId: run.id,
                                itemId: item.id,
                                isCompleted: value,
                              ),
                          value ? 'Punkt erledigt.' : 'Punkt wieder geöffnet.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createTask(
    String teamId,
    TeamOperationsOverview data,
  ) async {
    final draft = await showDialog<_TaskDraft>(
      context: context,
      builder: (context) => _TaskDialog(members: data.members),
    );
    if (draft == null) return;
    await _execute(
      teamId,
      () => ref.read(repositoryProvider).createTeamTask(
            teamId: teamId,
            title: draft.title,
            category: draft.category,
            description: draft.description,
            assigneeUserId: draft.assigneeUserId,
            dueAt: draft.dueAt,
          ),
      'Aufgabe wurde angelegt.',
    );
  }

  Future<void> _createEquipment(String teamId) async {
    final draft = await showDialog<_EquipmentDraft>(
      context: context,
      builder: (context) => const _EquipmentDialog(),
    );
    if (draft == null) return;
    await _execute(
      teamId,
      () => ref.read(repositoryProvider).createEquipmentItem(
            teamId: teamId,
            name: draft.name,
            category: draft.category,
            quantity: draft.quantity,
            notes: draft.notes,
          ),
      'Material wurde angelegt.',
    );
  }

  Future<void> _assignEquipment(
    String teamId,
    TeamOperationsOverview data,
    EquipmentItemModel item,
  ) async {
    final draft = await showDialog<_AssignmentDraft>(
      context: context,
      builder: (context) => _AssignmentDialog(
        item: item,
        members: data.members,
        players: data.players,
      ),
    );
    if (draft == null) return;
    await _execute(
      teamId,
      () => ref.read(repositoryProvider).assignEquipment(
            equipmentItemId: item.id,
            quantity: draft.quantity,
            assignedToUserId:
                draft.personType == 'user' ? draft.personId : null,
            assignedToPlayerId:
                draft.personType == 'player' ? draft.personId : null,
            dueAt: draft.dueAt,
          ),
      'Material wurde ausgegeben.',
    );
  }

  Future<void> _createChecklistTemplate(String teamId) async {
    final draft = await showDialog<_ChecklistDraft>(
      context: context,
      builder: (context) => const _ChecklistDialog(),
    );
    if (draft == null) return;
    await _execute(
      teamId,
      () => ref.read(repositoryProvider).createChecklistTemplate(
            teamId: teamId,
            title: draft.title,
            category: draft.category,
            description: draft.description,
            items: draft.items,
          ),
      'Checklisten-Vorlage wurde gespeichert.',
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.organization,
    required this.selectedTeamId,
    required this.onTeamChanged,
  });

  final OrganizationContext organization;
  final String selectedTeamId;
  final ValueChanged<String?> onTeamChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.assignment_turned_in_rounded,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team-Organisation',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Aufgaben, Material und wiederverwendbare Abläufe',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        );
        final selector = organization.teams.length > 1
            ? DropdownButtonFormField<String>(
                initialValue: selectedTeamId,
                decoration: const InputDecoration(labelText: 'Mannschaft'),
                items: [
                  for (final team in organization.teams)
                    DropdownMenuItem(
                      value: team.id,
                      child: Text(
                        team.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onTeamChanged,
              )
            : null;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 24,
            compact ? 16 : 22,
            compact ? 14 : 24,
            12,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    if (selector != null) ...[
                      const SizedBox(height: 12),
                      selector,
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    if (selector != null) ...[
                      const SizedBox(width: 16),
                      SizedBox(width: 220, child: selector),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({
    required this.data,
    required this.onCreate,
    required this.onStatus,
  });

  final TeamOperationsOverview data;
  final VoidCallback onCreate;
  final void Function(TeamTaskModel task, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    return _TabCanvas(
      header: _SectionHeader(
        title: 'Offene Aufgaben',
        subtitle:
            '${data.tasks.where((task) => !task.isDone).length} offen · ${data.tasks.where((task) => task.isOverdue).length} überfällig',
        actionLabel: data.canManage ? 'Aufgabe anlegen' : null,
        onAction: data.canManage ? onCreate : null,
      ),
      empty: data.tasks.isEmpty,
      emptyIcon: Icons.task_alt_rounded,
      emptyTitle: 'Keine Aufgaben vorhanden',
      emptyText: data.canManage
          ? 'Lege beispielsweise Trikotwäsche, Fahrdienst oder Turnierdienst an.'
          : 'Dir wurde aktuell keine Aufgabe zugewiesen.',
      children: [
        for (final task in data.tasks)
          _OperationCard(
            width: 380,
            leading: Icon(
              task.isDone
                  ? Icons.check_circle_rounded
                  : task.isOverdue
                      ? Icons.warning_amber_rounded
                      : Icons.radio_button_unchecked_rounded,
              color: task.isDone
                  ? AppColors.teal
                  : task.isOverdue
                      ? Colors.red
                      : AppColors.blue,
            ),
            title: task.title,
            badge: _taskStatus(task.status),
            lines: [
              task.category,
              if (task.assignee != null)
                'Verantwortlich: ${task.assignee!.name}',
              if (task.dueAt != null) 'Fällig: ${_date(task.dueAt!)}',
              if (task.description?.isNotEmpty == true) task.description!,
            ],
            trailing: data.canManage
                ? PopupMenuButton<String>(
                    tooltip: 'Status ändern',
                    onSelected: (status) => onStatus(task, status),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'OPEN', child: Text('Offen')),
                      PopupMenuItem(
                        value: 'IN_PROGRESS',
                        child: Text('In Arbeit'),
                      ),
                      PopupMenuItem(value: 'DONE', child: Text('Erledigt')),
                      PopupMenuItem(
                        value: 'CANCELLED',
                        child: Text('Abgebrochen'),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}

class _EquipmentTab extends StatelessWidget {
  const _EquipmentTab({
    required this.data,
    required this.onCreate,
    required this.onAssign,
    required this.onReturn,
  });

  final TeamOperationsOverview data;
  final VoidCallback onCreate;
  final ValueChanged<EquipmentItemModel> onAssign;
  final ValueChanged<EquipmentAssignmentModel> onReturn;

  @override
  Widget build(BuildContext context) {
    return _TabCanvas(
      header: _SectionHeader(
        title: 'Materialbestand',
        subtitle:
            '${data.equipment.length} Positionen · ${data.equipment.fold<int>(0, (sum, item) => sum + item.availableQuantity)} verfügbar',
        actionLabel: data.canManage ? 'Material anlegen' : null,
        onAction: data.canManage ? onCreate : null,
      ),
      empty: data.equipment.isEmpty,
      emptyIcon: Icons.inventory_2_outlined,
      emptyTitle: 'Noch kein Material erfasst',
      emptyText: 'Trikotsätze, Bälle, Leibchen oder Erste-Hilfe-Taschen '
          'können mit Ausgabe und Rückgabe verwaltet werden.',
      children: [
        for (final item in data.equipment)
          _OperationCard(
            width: 430,
            leading: const Icon(
              Icons.sports_soccer_rounded,
              color: AppColors.blue,
            ),
            title: item.name,
            badge: '${item.availableQuantity}/${item.quantity} frei',
            lines: [
              '${item.category} · ${_equipmentStatus(item.status)}',
              if (item.notes?.isNotEmpty == true) item.notes!,
            ],
            actions: [
              if (data.canManage &&
                  item.availableQuantity > 0 &&
                  item.status == 'ACTIVE')
                TextButton.icon(
                  onPressed: () => onAssign(item),
                  icon: const Icon(Icons.output_rounded),
                  label: const Text('Ausgeben'),
                ),
              for (final assignment in item.assignments)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${assignment.quantity}× ${assignment.recipient.name}'
                          '${assignment.dueAt == null ? '' : ' · bis ${_date(assignment.dueAt!)}'}',
                          style: TextStyle(
                            color: assignment.isOverdue
                                ? Colors.red
                                : AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (data.canManage)
                        TextButton(
                          onPressed: () => onReturn(assignment),
                          child: const Text('Rückgabe'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ChecklistsTab extends StatelessWidget {
  const _ChecklistsTab({
    required this.data,
    required this.onCreateTemplate,
    required this.onStart,
    required this.onToggle,
  });

  final TeamOperationsOverview data;
  final VoidCallback onCreateTemplate;
  final ValueChanged<ChecklistTemplateModel> onStart;
  final void Function(
    ChecklistRunModel run,
    ChecklistRunItemModel item,
    bool value,
  ) onToggle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 24,
        compact ? 16 : 22,
        compact ? 14 : 24,
        40,
      ),
      children: [
        _SectionHeader(
          title: 'Laufende Checklisten',
          subtitle:
              '${data.checklistRuns.where((run) => run.status == 'ACTIVE').length} aktiv',
          actionLabel: data.canManage ? 'Vorlage anlegen' : null,
          onAction: data.canManage ? onCreateTemplate : null,
        ),
        const SizedBox(height: 16),
        if (data.checklistRuns.isEmpty)
          const _EmptyState(
            icon: Icons.checklist_rounded,
            title: 'Noch keine Checkliste gestartet',
            text:
                'Starte unten eine Vorlage für Spieltag, Turnier oder Auswärtsfahrt.',
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final run in data.checklistRuns)
                SizedBox(
                  width: compact ? double.infinity : 440,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  run.title,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              _Badge(
                                label: run.status == 'COMPLETED'
                                    ? 'Erledigt'
                                    : '${run.completedCount}/${run.items.length}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: run.progress,
                            minHeight: 7,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(height: 12),
                          for (final item in run.items)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: item.isCompleted,
                              onChanged:
                                  data.canManage && run.status == 'ACTIVE'
                                      ? (value) => onToggle(
                                            run,
                                            item,
                                            value ?? false,
                                          )
                                      : null,
                              title: Text(item.title),
                              subtitle: item.completedBy == null
                                  ? null
                                  : Text(
                                      'Erledigt von ${item.completedBy!.name}'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 28),
        const _SectionHeader(
          title: 'Vorlagen',
          subtitle: 'Wiederverwendbare Abläufe für den Mannschaftsalltag',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final template in data.checklistTemplates)
              _OperationCard(
                width: 360,
                leading: const Icon(
                  Icons.library_add_check_rounded,
                  color: AppColors.blue,
                ),
                title: template.title,
                badge: '${template.items.length} Punkte',
                lines: [
                  template.category,
                  if (template.description?.isNotEmpty == true)
                    template.description!,
                ],
                actions: [
                  if (data.canManage)
                    FilledButton.tonalIcon(
                      onPressed: () => onStart(template),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Starten'),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _TabCanvas extends StatelessWidget {
  const _TabCanvas({
    required this.header,
    required this.empty,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyText,
    required this.children,
  });

  final Widget header;
  final bool empty;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 24,
        compact ? 16 : 22,
        compact ? 14 : 24,
        40,
      ),
      children: [
        header,
        const SizedBox(height: 16),
        if (empty)
          _EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            text: emptyText,
          )
        else
          Wrap(spacing: 16, runSpacing: 16, children: children),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final labels = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          ],
        );
        final action = actionLabel == null
            ? null
            : FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labels,
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    action,
                  ],
                ],
              )
            : Row(
                children: [
                  Expanded(child: labels),
                  if (action != null) action,
                ],
              );
      },
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.width,
    required this.leading,
    required this.title,
    required this.badge,
    required this.lines,
    this.trailing,
    this.actions = const [],
  });

  final double width;
  final Widget leading;
  final String title;
  final String badge;
  final List<String> lines;
  final Widget? trailing;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SizedBox(
      width: compact ? double.infinity : width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _Badge(label: badge),
                  if (trailing != null) trailing!,
                ],
              ),
              if (lines.isNotEmpty) const SizedBox(height: 12),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.blue,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 44, color: AppColors.blue),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.red),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Erneut laden'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({required this.members});

  final List<OperationsPerson> members;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'SONSTIGES';
  String? _assigneeUserId;
  DateTime? _dueAt;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aufgabe anlegen'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titel *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: const [
                  DropdownMenuItem(
                    value: 'TRIKOTWAESCHE',
                    child: Text('Trikotwäsche'),
                  ),
                  DropdownMenuItem(
                    value: 'FAHRDIENST',
                    child: Text('Fahrdienst'),
                  ),
                  DropdownMenuItem(
                    value: 'TURNIERDIENST',
                    child: Text('Turnierdienst'),
                  ),
                  DropdownMenuItem(
                    value: 'VERPFLEGUNG',
                    child: Text('Verpflegung'),
                  ),
                  DropdownMenuItem(
                    value: 'AUFBAU',
                    child: Text('Auf- und Abbau'),
                  ),
                  DropdownMenuItem(
                    value: 'SONSTIGES',
                    child: Text('Sonstiges'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'SONSTIGES'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _assigneeUserId,
                decoration:
                    const InputDecoration(labelText: 'Verantwortliche Person'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Noch offen'),
                  ),
                  for (final member in widget.members)
                    DropdownMenuItem<String?>(
                      value: member.id,
                      child: Text(member.name),
                    ),
                ],
                onChanged: (value) => setState(() => _assigneeUserId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Beschreibung'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text(
                  _dueAt == null
                      ? 'Keine Frist'
                      : 'Fällig am ${_date(_dueAt!)}',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final value = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (value != null) setState(() => _dueAt = value);
                  },
                  child: const Text('Auswählen'),
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
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              _TaskDraft(
                title: title,
                category: _category,
                description: _description.text.trim(),
                assigneeUserId: _assigneeUserId,
                dueAt: _dueAt,
              ),
            );
          },
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}

class _EquipmentDialog extends StatefulWidget {
  const _EquipmentDialog();

  @override
  State<_EquipmentDialog> createState() => _EquipmentDialogState();
}

class _EquipmentDialogState extends State<_EquipmentDialog> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  String _category = 'SONSTIGES';

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Material anlegen'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Bezeichnung *'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Kategorie'),
              items: const [
                DropdownMenuItem(value: 'TRIKOT', child: Text('Trikotsatz')),
                DropdownMenuItem(value: 'BALL', child: Text('Bälle')),
                DropdownMenuItem(value: 'LEIBCHEN', child: Text('Leibchen')),
                DropdownMenuItem(value: 'HUETCHEN', child: Text('Hütchen')),
                DropdownMenuItem(
                  value: 'TORWART',
                  child: Text('Torwartausrüstung'),
                ),
                DropdownMenuItem(
                  value: 'ERSTE_HILFE',
                  child: Text('Erste Hilfe'),
                ),
                DropdownMenuItem(
                  value: 'SONSTIGES',
                  child: Text('Sonstiges'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? 'SONSTIGES'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bestand *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notiz'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final quantity = int.tryParse(_quantity.text) ?? 0;
            if (name.isEmpty || quantity < 1) return;
            Navigator.pop(
              context,
              _EquipmentDraft(
                name: name,
                category: _category,
                quantity: quantity,
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({
    required this.item,
    required this.members,
    required this.players,
  });

  final EquipmentItemModel item;
  final List<OperationsPerson> members;
  final List<OperationsPerson> players;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  String? _target;
  final _quantity = TextEditingController(text: '1');
  DateTime? _dueAt;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.item.name} ausgeben'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _target,
              decoration: const InputDecoration(labelText: 'Empfänger *'),
              items: [
                for (final member in widget.members)
                  DropdownMenuItem(
                    value: 'user:${member.id}',
                    child: Text('${member.name} · Mitglied'),
                  ),
                for (final player in widget.players)
                  DropdownMenuItem(
                    value: 'player:${player.id}',
                    child: Text('${player.name} · Spieler'),
                  ),
              ],
              onChanged: (value) => setState(() => _target = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Menge',
                helperText: '${widget.item.availableQuantity} verfügbar',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.assignment_return_rounded),
              title: Text(
                _dueAt == null
                    ? 'Keine Rückgabefrist'
                    : 'Rückgabe bis ${_date(_dueAt!)}',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (value != null) setState(() => _dueAt = value);
                },
                child: const Text('Auswählen'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final quantity = int.tryParse(_quantity.text) ?? 0;
            final parts = _target?.split(':');
            if (parts?.length != 2 ||
                quantity < 1 ||
                quantity > widget.item.availableQuantity) {
              return;
            }
            Navigator.pop(
              context,
              _AssignmentDraft(
                personType: parts![0],
                personId: parts[1],
                quantity: quantity,
                dueAt: _dueAt,
              ),
            );
          },
          child: const Text('Ausgeben'),
        ),
      ],
    );
  }
}

class _ChecklistDialog extends StatefulWidget {
  const _ChecklistDialog();

  @override
  State<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends State<_ChecklistDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _items = TextEditingController();
  String _category = 'SPIELTAG';

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _items.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Checklisten-Vorlage'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titel *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: const [
                  DropdownMenuItem(
                    value: 'SPIELTAG',
                    child: Text('Spieltag'),
                  ),
                  DropdownMenuItem(
                    value: 'TURNIER',
                    child: Text('Turnier'),
                  ),
                  DropdownMenuItem(
                    value: 'AUSWAERTSFAHRT',
                    child: Text('Auswärtsfahrt'),
                  ),
                  DropdownMenuItem(
                    value: 'SAISONSTART',
                    child: Text('Saisonstart'),
                  ),
                  DropdownMenuItem(
                    value: 'SAISONABSCHLUSS',
                    child: Text('Saisonabschluss'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'SPIELTAG'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Beschreibung'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _items,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Punkte *',
                  helperText: 'Ein Punkt pro Zeile',
                  alignLabelWithHint: true,
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
            final title = _title.text.trim();
            final items = _items.text
                .split('\n')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList();
            if (title.isEmpty || items.isEmpty) return;
            Navigator.pop(
              context,
              _ChecklistDraft(
                title: title,
                category: _category,
                description: _description.text.trim(),
                items: items,
              ),
            );
          },
          child: const Text('Vorlage speichern'),
        ),
      ],
    );
  }
}

class _TaskDraft {
  const _TaskDraft({
    required this.title,
    required this.category,
    required this.description,
    this.assigneeUserId,
    this.dueAt,
  });

  final String title;
  final String category;
  final String description;
  final String? assigneeUserId;
  final DateTime? dueAt;
}

class _EquipmentDraft {
  const _EquipmentDraft({
    required this.name,
    required this.category,
    required this.quantity,
    required this.notes,
  });

  final String name;
  final String category;
  final int quantity;
  final String notes;
}

class _AssignmentDraft {
  const _AssignmentDraft({
    required this.personType,
    required this.personId,
    required this.quantity,
    this.dueAt,
  });

  final String personType;
  final String personId;
  final int quantity;
  final DateTime? dueAt;
}

class _ChecklistDraft {
  const _ChecklistDraft({
    required this.title,
    required this.category,
    required this.description,
    required this.items,
  });

  final String title;
  final String category;
  final String description;
  final List<String> items;
}

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _taskStatus(String value) => switch (value) {
      'IN_PROGRESS' => 'In Arbeit',
      'DONE' => 'Erledigt',
      'CANCELLED' => 'Abgebrochen',
      _ => 'Offen',
    };

String _equipmentStatus(String value) => switch (value) {
      'MAINTENANCE' => 'Wartung',
      'LOST' => 'Verloren',
      'RETIRED' => 'Ausgemustert',
      _ => 'Aktiv',
    };

String _errorMessage(Object error) {
  final text = error.toString();
  final match = RegExp(r'message:\s*([^,}]+)').firstMatch(text);
  return match?.group(1)?.trim() ?? 'Aktion konnte nicht abgeschlossen werden.';
}
