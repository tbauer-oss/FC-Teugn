import 'package:flutter/material.dart';
import '../../core/models/organization.dart';

typedef WorkingContextSelection = ({
  String ageGroupId,
  String? teamId,
  bool includeAll,
});

/// A direct choice, not a form: one tap switches to any permitted team.
class WorkingContextSwitcher extends StatefulWidget {
  const WorkingContextSwitcher({
    super.key,
    required this.organization,
    required this.onSelect,
  });

  final OrganizationContext organization;
  final Future<void> Function(WorkingContextSelection) onSelect;

  @override
  State<WorkingContextSwitcher> createState() => _WorkingContextSwitcherState();
}

class _WorkingContextSwitcherState extends State<WorkingContextSwitcher> {
  String _query = '';
  String? _pending;
  String? _error;

  Future<void> _select(WorkingContextSelection selection, String key) async {
    if (_pending != null) return;
    setState(() {
      _pending = key;
      _error = null;
    });
    try {
      await widget.onSelect(selection);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pending = null;
        _error = 'Wechsel nicht möglich. Bitte erneut versuchen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final organization = widget.organization;
    final teams = organization.teams.where((team) => team.isActive).toList();
    // Build groups from the authorized team list, including a group's name
    // even when the separate age-group summary has not been populated.
    final groups = {for (final team in teams) team.ageGroup.id: team.ageGroup}
        .values
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final current = organization.workingContext;
    final colors = Theme.of(context).colorScheme;
    var visibleCount = 0;
    final sections = <Widget>[];
    for (final group in groups) {
      final groupTeams = teams
          .where((team) => team.ageGroup.id == group.id)
          .toList()
        ..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
      final visible = groupTeams
          .where((team) =>
              '${group.name} ${team.displayName} ${team.seasonName}'
                  .toLowerCase()
                  .contains(_query))
          .toList();
      if (visible.isEmpty) continue;
      visibleCount += visible.length;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(group.name,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: colors.onSurfaceVariant)),
      ));
      for (final team in visible) {
        sections.add(_choice(
          key: team.id,
          title: team.displayName,
          subtitle: team.seasonName,
          icon: Icons.shield_outlined,
          selected: !current.includeAllTeams &&
              (current.teamIds.contains(team.id) ||
                  (current.teamIds.isEmpty &&
                      team.id == organization.currentTeam.id)),
          selection: (ageGroupId: group.id, teamId: team.id, includeAll: false),
        ));
      }
      if (groupTeams.length > 1) {
        sections.add(_choice(
          key: 'all-${group.id}',
          title: 'Alle Mannschaften',
          subtitle: '${group.name} · ${groupTeams.length} Teams',
          icon: Icons.groups_outlined,
          selected: current.includeAllTeams && current.ageGroupId == group.id,
          selection: (ageGroupId: group.id, teamId: null, includeAll: true),
        ));
      }
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        // Let the heading and search scroll too when a landscape keyboard
        // leaves too little room for a fixed header plus the team list.
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(children: [
                Expanded(
                    child: Text('Mannschaft wechseln',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed:
                      _pending == null ? () => Navigator.pop(context) : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            if (teams.length > 6)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  enabled: _pending == null,
                  decoration: const InputDecoration(
                    hintText: 'Mannschaft suchen',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            ...sections.map((section) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: section)),
            if (visibleCount == 0)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Keine Mannschaft gefunden.')),
          ],
        ),
      ),
    );
  }

  Widget _choice({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required WorkingContextSelection selection,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          key: ValueKey('switch-team-$key'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          selected: selected,
          selectedColor: colors.onPrimaryContainer,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: _pending == key
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded),
          onTap: _pending != null
              ? null
              : selected
                  ? () => Navigator.pop(context)
                  : () => _select(selection, key),
        ),
      ),
    );
  }
}
