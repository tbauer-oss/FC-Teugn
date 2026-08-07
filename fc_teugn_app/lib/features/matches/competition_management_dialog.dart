import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';

import '../../core/app_theme.dart';
import '../../core/data_repository.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';
import '../shared/context_help.dart';
import 'bfv_sync_tab.dart';

class CompetitionManagementDialog extends StatefulWidget {
  const CompetitionManagementDialog({
    super.key,
    required this.repository,
    required this.organization,
    this.isSystemAdmin = false,
    this.onOrganizationChanged,
  });

  final DataRepository repository;
  final OrganizationContext organization;
  final bool isSystemAdmin;
  final VoidCallback? onOrganizationChanged;

  @override
  State<CompetitionManagementDialog> createState() =>
      _CompetitionManagementDialogState();
}

class _CompetitionManagementDialogState
    extends State<CompetitionManagementDialog> {
  late String ageGroupId;
  List<OpponentModel>? opponents;
  List<LeagueModel>? leagues;
  String? error;

  @override
  void initState() {
    super.initState();
    ageGroupId = widget.organization.workingContext.ageGroupId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      opponents = null;
      leagues = null;
      error = null;
    });
    try {
      final values = await Future.wait([
        widget.repository.opponents(ageGroupId),
        widget.repository.leagues(ageGroupId),
      ]);
      if (!mounted) return;
      setState(() {
        opponents = values[0] as List<OpponentModel>;
        leagues = values[1] as List<LeagueModel>;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Ligadaten konnten nicht geladen werden.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Dialog.fullscreen(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Liga & Gegner'),
            actions: const [
              ContextHelpButton(
                pageTitle: 'Liga & Gegner',
                pageSubtitle:
                    'Gegner-Pool, Ligen und automatische BfV-Spielplansynchronisation verwalten.',
              ),
              SizedBox(width: 8),
            ],
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.shield_outlined), text: 'Gegner'),
                Tab(icon: Icon(Icons.emoji_events_outlined), text: 'Ligen'),
                Tab(icon: Icon(Icons.sync_rounded), text: 'BfV'),
              ],
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DropdownButtonFormField<String>(
                  initialValue: ageGroupId,
                  decoration: const InputDecoration(labelText: 'Jugend'),
                  items: [
                    for (final ageGroup in widget.organization.ageGroups.where(
                      (item) => widget.organization.teams
                          .any((team) => team.ageGroup.id == item.id),
                    ))
                      DropdownMenuItem(
                        value: ageGroup.id,
                        child: Text(ageGroup.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    ageGroupId = value;
                    _load();
                  },
                ),
              ),
              Expanded(
                child: error != null
                    ? Center(
                        child: FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(error!),
                        ),
                      )
                    : opponents == null || leagues == null
                        ? const Center(
                            child: LogoLoadingPanel(
                              message: 'Ligadaten werden geladen …',
                              compact: true,
                            ),
                          )
                        : TabBarView(
                            children: [
                              _opponentTab(height),
                              _leagueTab(height),
                              BfvSyncTab(
                                key: ValueKey(ageGroupId),
                                repository: widget.repository,
                                allTeams: widget.organization.teams,
                                isSystemAdmin: widget.isSystemAdmin,
                                onConfigurationChanged:
                                    widget.onOrganizationChanged,
                                teams: widget.organization.teams
                                    .where((team) =>
                                        team.ageGroup.id == ageGroupId)
                                    .toList(),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opponentTab(double height) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _editOpponent(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Gegner anlegen'),
            ),
          ),
          const SizedBox(height: 12),
          if (opponents!.isEmpty)
            const _CompetitionEmpty(
              icon: Icons.shield_outlined,
              text: 'Noch keine Gegner für diese Jugend gespeichert.',
            )
          else
            for (final opponent in opponents!)
              Card(
                child: ListTile(
                  leading:
                      _Logo(url: opponent.logoUrl, label: opponent.clubName),
                  title: Text(opponent.displayName),
                  subtitle: Text(
                    [opponent.venue, opponent.address]
                        .whereType<String>()
                        .where((item) => item.isNotEmpty)
                        .join(' · '),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Wappen hochladen',
                        onPressed: () => _uploadLogo(opponent),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                      IconButton(
                        tooltip: 'Bearbeiten',
                        onPressed: () => _editOpponent(opponent),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );

  Widget _leagueTab(double height) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: opponents!.isEmpty ? null : _createLeague,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Liga anlegen'),
            ),
          ),
          const SizedBox(height: 12),
          if (leagues!.isEmpty)
            const _CompetitionEmpty(
              icon: Icons.emoji_events_outlined,
              text: 'Noch keine Liga für diese Jugend angelegt.',
            )
          else
            for (final league in leagues!)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: Text(
                    league.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${league.entries.length} Mannschaften · ${league.matches.length} Partien',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  children: [
                    _StandingsTable(rows: league.standings),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Partien',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _editLeagueMatch(league),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Partie'),
                        ),
                      ],
                    ),
                    for (final match in league.matches)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${match.homeName} – ${match.awayName}'),
                        subtitle: match.startsAt == null
                            ? const Text('Termin offen')
                            : Text(_dateTime(match.startsAt!)),
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 2,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                match.homeGoals == null
                                    ? '– : –'
                                    : '${match.homeGoals} : ${match.awayGoals}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (widget.organization
                                .can('LEAGUE_MATCH_RESCHEDULE'))
                              IconButton(
                                tooltip: 'Partie bearbeiten / verlegen',
                                onPressed: () =>
                                    _editLeagueMatch(league, match),
                                icon: const Icon(Icons.edit_calendar_outlined),
                              ),
                            if (widget.organization.can('LEAGUE_MATCH_DELETE'))
                              IconButton(
                                tooltip: 'Ligapartie endgültig löschen',
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () =>
                                    _deleteLeagueMatch(league, match),
                                icon: const Icon(Icons.delete_forever_outlined),
                              ),
                          ],
                        ),
                        onTap:
                            widget.organization.can('LEAGUE_MATCH_RESCHEDULE')
                                ? () => _editLeagueMatch(league, match)
                                : null,
                      ),
                  ],
                ),
              ),
        ],
      );

  Future<void> _editOpponent([OpponentModel? value]) async {
    final draft = await showDialog<OpponentEditorDraft>(
      context: context,
      builder: (context) => OpponentEditorDialog(
        value: value,
      ),
    );
    if (draft == null) return;
    await widget.repository.saveOpponent(
      id: value?.id,
      ageGroupId: ageGroupId,
      clubName: draft.clubName,
      teamDesignation: draft.teamDesignation,
      venue: draft.venue,
      address: draft.address,
    );
    await _load();
  }

  Future<void> _uploadLogo(OpponentModel opponent) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null) return;
    await widget.repository.uploadOpponentLogo(
      opponentId: opponent.id,
      bytes: file!.bytes!,
      fileName: file.name,
    );
    await _load();
  }

  Future<void> _createLeague() async {
    final name = TextEditingController();
    final selectedOpponents = opponents!.map((item) => item.id).toSet();
    final ownTeams = widget.organization.teams
        .where((team) => team.ageGroup.id == ageGroupId && team.isActive)
        .toList();
    final selectedTeams = ownTeams.map((team) => team.id).toSet();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Liga anlegen'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Liganame *')),
                  const SizedBox(height: 16),
                  const Text('Eigene Mannschaften',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final team in ownTeams)
                        FilterChip(
                          label: Text(team.displayName),
                          selected: selectedTeams.contains(team.id),
                          onSelected: (selected) => update(() => selected
                              ? selectedTeams.add(team.id)
                              : selectedTeams.remove(team.id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Gegner',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final opponent in opponents!)
                        FilterChip(
                          label: Text(opponent.displayName),
                          selected: selectedOpponents.contains(opponent.id),
                          onSelected: (selected) => update(() => selected
                              ? selectedOpponents.add(opponent.id)
                              : selectedOpponents.remove(opponent.id)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Liga speichern')),
          ],
        ),
      ),
    );
    try {
      if (save == true &&
          name.text.trim().isNotEmpty &&
          selectedTeams.isNotEmpty) {
        await widget.repository.saveLeague(
          name: name.text.trim(),
          seasonId: widget.organization.season.id,
          ageGroupId: ageGroupId,
          teamId: selectedTeams.first,
          ownTeamIds: selectedTeams.toList(),
          opponentIds: selectedOpponents.toList(),
        );
        await _load();
      }
    } finally {
      name.dispose();
    }
  }

  Future<void> _editLeagueMatch(LeagueModel league,
      [LeagueMatchModel? value]) async {
    String? homeId = value?.homeEntryId ?? league.entries.firstOrNull?.id;
    String? awayId =
        value?.awayEntryId ?? league.entries.skip(1).firstOrNull?.id;
    DateTime? startsAt = value?.startsAt;
    final homeGoals = TextEditingController(text: value?.homeGoals?.toString());
    final awayGoals = TextEditingController(text: value?.awayGoals?.toString());
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(value == null ? 'Partie anlegen' : 'Partie bearbeiten'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                    initialValue: homeId,
                    decoration: const InputDecoration(labelText: 'Heim'),
                    items: [
                      for (final entry in league.entries)
                        DropdownMenuItem(
                            value: entry.id, child: Text(entry.displayName))
                    ],
                    onChanged: (id) => update(() => homeId = id)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    initialValue: awayId,
                    decoration: const InputDecoration(labelText: 'Auswärts'),
                    items: [
                      for (final entry in league.entries)
                        DropdownMenuItem(
                            value: entry.id, child: Text(entry.displayName))
                    ],
                    onChanged: (id) => update(() => awayId = id)),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Spieltermin'),
                  subtitle: Text(
                      startsAt == null ? 'Noch offen' : _dateTime(startsAt!)),
                  trailing: const Icon(Icons.calendar_month_rounded),
                  onTap: () async {
                    final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2040),
                        initialDate: startsAt ?? DateTime.now());
                    if (date != null) update(() => startsAt = date);
                  },
                ),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: homeGoals,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Heimtore'))),
                  const Padding(padding: EdgeInsets.all(10), child: Text(':')),
                  Expanded(
                      child: TextField(
                          controller: awayGoals,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Auswärtstore'))),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: homeId == awayId
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Speichern')),
          ],
        ),
      ),
    );
    try {
      if (save == true && homeId != null && awayId != null) {
        await widget.repository.saveLeagueMatch(
          leagueId: league.id,
          matchId: value?.id,
          homeEntryId: homeId!,
          awayEntryId: awayId!,
          startsAt: startsAt,
          homeGoals: int.tryParse(homeGoals.text),
          awayGoals: int.tryParse(awayGoals.text),
        );
        await _load();
      }
    } finally {
      homeGoals.dispose();
      awayGoals.dispose();
    }
  }

  Future<void> _deleteLeagueMatch(
    LeagueModel league,
    LeagueMatchModel match,
  ) async {
    var deleteLinkedEvent =
        match.eventId != null && widget.organization.can('MATCH_DELETE');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: const Text('Ligapartie endgültig löschen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '„${match.homeName} – ${match.awayName}“ wird aus '
                '„${league.name}“ entfernt. Die Tabelle wird direkt neu berechnet.',
              ),
              if (match.eventId != null &&
                  widget.organization.can('MATCH_DELETE')) ...[
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deleteLinkedEvent,
                  title: const Text('Verknüpften Spieltag ebenfalls löschen'),
                  subtitle: const Text(
                    'Kader, Aufstellung, Liveticker und Rückmeldungen werden dann dauerhaft entfernt.',
                  ),
                  onChanged: (value) =>
                      update(() => deleteLinkedEvent = value ?? false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Endgültig löschen'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteLeagueMatch(
        leagueId: league.id,
        matchId: match.id,
        deleteLinkedEvent: deleteLinkedEvent,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Ligapartie wurde gelöscht und Tabelle aktualisiert.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ligapartie konnte nicht gelöscht werden.')),
        );
      }
    }
  }
}

class OpponentEditorDraft {
  const OpponentEditorDraft({
    required this.clubName,
    required this.teamDesignation,
    required this.venue,
    required this.address,
  });

  final String clubName;
  final String teamDesignation;
  final String venue;
  final String address;
}

class OpponentEditorDialog extends StatefulWidget {
  const OpponentEditorDialog({super.key, this.value});

  final OpponentModel? value;

  @override
  State<OpponentEditorDialog> createState() => _OpponentEditorDialogState();
}

class _OpponentEditorDialogState extends State<OpponentEditorDialog> {
  late final TextEditingController club;
  late final TextEditingController designation;
  late final TextEditingController venue;
  late final TextEditingController address;

  bool get canSave =>
      club.text.trim().isNotEmpty && designation.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    club = TextEditingController(text: widget.value?.clubName);
    designation = TextEditingController(text: widget.value?.teamDesignation);
    venue = TextEditingController(text: widget.value?.venue);
    address = TextEditingController(text: widget.value?.address);
  }

  @override
  void dispose() {
    club.dispose();
    designation.dispose();
    venue.dispose();
    address.dispose();
    super.dispose();
  }

  void refreshValidation(String _) => setState(() {});

  void save() {
    if (!canSave) return;
    Navigator.pop(
      context,
      OpponentEditorDraft(
        clubName: club.text.trim(),
        teamDesignation: designation.text.trim(),
        venue: venue.text.trim(),
        address: address.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.value == null ? 'Gegner anlegen' : 'Gegner bearbeiten',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: club,
                  onChanged: refreshValidation,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Verein *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: designation,
                  onChanged: refreshValidation,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Jugend / Mannschaft *',
                    hintText: 'z. B. E1',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: venue,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Spielstätte'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address,
                  textInputAction: TextInputAction.done,
                  onSubmitted: canSave ? (_) => save() : null,
                  decoration: const InputDecoration(labelText: 'Adresse'),
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
            onPressed: canSave ? save : null,
            child: const Text('Speichern'),
          ),
        ],
      );
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.rows});
  final List<LeagueStandingModel> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Mannschaft')),
            DataColumn(label: Text('Sp.')),
            DataColumn(label: Text('Tore')),
            DataColumn(label: Text('Diff.')),
            DataColumn(label: Text('Pkt.')),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                color: row.isOwnTeam
                    ? const WidgetStatePropertyAll(AppColors.yellowSoft)
                    : null,
                cells: [
                  DataCell(Text('${row.rank}.')),
                  DataCell(Text(row.name,
                      style: TextStyle(
                          fontWeight: row.isOwnTeam
                              ? FontWeight.w900
                              : FontWeight.w500))),
                  DataCell(Text('${row.games}')),
                  DataCell(Text('${row.goalsFor}:${row.goalsAgainst}')),
                  DataCell(Text('${row.goalDifference}')),
                  DataCell(Text('${row.points}',
                      style: const TextStyle(fontWeight: FontWeight.w900))),
                ],
              ),
          ],
        ),
      );
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.label});
  final String? url;
  final String label;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: AppColors.background,
        backgroundImage: url == null ? null : NetworkImage(url!),
        child: url == null
            ? Text(label.isEmpty ? '?' : label[0].toUpperCase())
            : null,
      );
}

class _CompetitionEmpty extends StatelessWidget {
  const _CompetitionEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(icon, size: 50, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(text)
        ]),
      );
}

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} Uhr';
