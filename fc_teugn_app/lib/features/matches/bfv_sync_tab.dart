import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/data_repository.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';

String? normalizedBfvWidgetTeamId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  final fromWidgetCode = RegExp(
    r'''zeigeMannschaftKomplett\(\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(normalized);
  return (fromWidgetCode?.group(1) ?? normalized).trim();
}

bool isValidBfvWidgetTeamId(String? value) =>
    value == null || RegExp(r'^[A-Za-z0-9_-]{6,160}$').hasMatch(value);

class BfvSyncTab extends StatefulWidget {
  const BfvSyncTab({
    super.key,
    required this.repository,
    required this.teams,
    this.allTeams = const [],
    this.isSystemAdmin = false,
    this.onConfigurationChanged,
  });

  final DataRepository repository;
  final List<TeamSummary> teams;
  final List<TeamSummary> allTeams;
  final bool isSystemAdmin;
  final VoidCallback? onConfigurationChanged;

  @override
  State<BfvSyncTab> createState() => _BfvSyncTabState();
}

class _BfvSyncTabState extends State<BfvSyncTab> {
  final teamPageController = TextEditingController();
  final icalController = TextEditingController();
  final widgetTeamIdController = TextEditingController();
  String? teamId;
  BfvSyncConfigModel? config;
  bool enabled = true;
  int interval = 30;
  bool busy = false;
  String? error;
  int? centralConfiguredCount;

  @override
  void initState() {
    super.initState();
    teamId = widget.teams.isEmpty ? null : widget.teams.first.id;
    _load();
  }

  @override
  void didUpdateWidget(covariant BfvSyncTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.teams.any((team) => team.id == teamId)) {
      teamId = widget.teams.isEmpty ? null : widget.teams.first.id;
      _load();
    }
  }

  @override
  void dispose() {
    teamPageController.dispose();
    icalController.dispose();
    widgetTeamIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final selected = teamId;
    if (selected == null) return;
    setState(() {
      config = null;
      error = null;
    });
    try {
      final value = await widget.repository.bfvSyncConfig(selected);
      if (!mounted || selected != teamId) return;
      _apply(value);
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = 'BfV-Einstellungen konnten nicht geladen werden.');
      }
    }
  }

  void _apply(BfvSyncConfigModel value) {
    config = value;
    enabled = value.enabled;
    interval = value.syncIntervalMinutes;
    teamPageController.text = value.teamPageUrl ?? '';
    icalController.text = value.icalUrl ?? '';
    widgetTeamIdController.text = value.widgetTeamId ?? '';
    setState(() {});
  }

  Future<BfvSyncConfigModel?> _save({bool showMessage = true}) async {
    final selected = teamId;
    if (selected == null) return null;
    setState(() => busy = true);
    try {
      final value = await widget.repository.saveBfvSyncConfig(
        teamId: selected,
        teamPageUrl: teamPageController.text.trim(),
        icalUrl: icalController.text.trim(),
        officialViewUrl: teamPageController.text.trim(),
        widgetTeamId: widgetTeamIdController.text.trim(),
        enabled: enabled,
        syncIntervalMinutes: interval,
      );
      if (!mounted) return value;
      _apply(value);
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('BfV-Verknüpfung gespeichert.')),
        );
      }
      widget.onConfigurationChanged?.call();
      return value;
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_message(exception,
                  'BfV-Verknüpfung konnte nicht gespeichert werden.'))),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sync() async {
    final selected = teamId;
    if (selected == null || await _save(showMessage: false) == null) return;
    setState(() => busy = true);
    try {
      final value = await widget.repository.runBfvSync(selected);
      if (!mounted) return;
      _apply(value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${value.lastCreatedCount} neu, ${value.lastUpdatedCount} aktualisiert, '
            '${value.lastSkippedCount} unverändert.',
          ),
        ),
      );
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  _message(exception, 'BfV-Abgleich ist fehlgeschlagen.'))),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _message(Object exception, String fallback) {
    final value = exception.toString();
    final marker = RegExp(r'message:\s*([^,}\]]+)').firstMatch(value);
    return marker?.group(1)?.trim() ?? fallback;
  }

  void _openOfficialView() {
    final widgetTeamId = widgetTeamIdController.text.trim();
    final selectedTeam = widget.teams
        .where((team) => team.id == teamId)
        .map((team) => team.displayName)
        .firstOrNull;
    final route = Uri(
      path: '/bfv-browser',
      queryParameters: {
        'teamName': selectedTeam ?? 'BfV',
        if (widgetTeamId.isNotEmpty)
          'teamId': widgetTeamId
        else
          'teamUrl': teamPageController.text.trim(),
      },
    );
    context.push(route.toString());
  }

  Future<void> _openCentralWidgetManagement() async {
    final configuredCount = await showDialog<int>(
      context: context,
      builder: (context) => _BfvWidgetTeamManagerDialog(
        repository: widget.repository,
        teams: widget.allTeams,
      ),
    );
    if (configuredCount == null || !mounted) return;
    setState(() => centralConfiguredCount = configuredCount);
    widget.onConfigurationChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teams.isEmpty) {
      return const Center(
          child: Text('Für diese Jugend ist keine Mannschaft verfügbar.'));
    }
    if (config == null && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(error!),
        ),
      );
    }
    final status = config!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (widget.isSystemAdmin && widget.allTeams.isNotEmpty) ...[
          _CentralWidgetManagementCard(
            onOpen: () => _openCentralWidgetManagement(),
            configuredCount: centralConfiguredCount ??
                widget.allTeams
                    .where((team) => team.bfvTeamId?.trim().isNotEmpty == true)
                    .length,
            teamCount: widget.allTeams.length,
          ),
          const SizedBox(height: 16),
        ],
        _IntroCard(
            onOpen: _openOfficialView,
            canOpen: widgetTeamIdController.text.trim().isNotEmpty ||
                teamPageController.text.trim().isNotEmpty),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: teamId,
          decoration: const InputDecoration(labelText: 'Mannschaft'),
          items: [
            for (final team in widget.teams)
              DropdownMenuItem(value: team.id, child: Text(team.name)),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value == null || value == teamId) return;
                  setState(() => teamId = value);
                  _load();
                },
        ),
        const SizedBox(height: 16),
        _StatusCard(config: status),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Offizielle BfV-Verknüpfung',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text(
                    'Die iCal-Adresse importiert eure eigenen Spiele. Die Widget-Mannschaftskennung zeigt zusätzlich die offizielle Tabelle und sämtliche Ligaspiele direkt in einer eigenen App-Ansicht.'),
                const SizedBox(height: 16),
                TextField(
                  controller: teamPageController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'BfV-Mannschaftsseite',
                    hintText: 'https://www.bfv.de/mannschaften/…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: icalController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'BfV-iCal-Adresse für eigene Spiele',
                    hintText: 'https://service.bfv.de/rest/icsexport/…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widgetTeamIdController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'BfV-Widget-Mannschaftskennung',
                    hintText: 'z. B. 011MI…',
                    helperText:
                        'Steht im Widget-Code direkt hinter zeigeMannschaftKomplett(…).',
                  ),
                ),
                const SizedBox(height: 8),
                const _WidgetDomainHint(),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged:
                      busy ? null : (value) => setState(() => enabled = value),
                  title: const Text('Automatisch synchronisieren'),
                  subtitle: const Text(
                      'Eigene Spiele werden regelmäßig aktualisiert.'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: interval,
                  decoration: const InputDecoration(labelText: 'Abgleich'),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('Alle 30 Minuten')),
                    DropdownMenuItem(value: 60, child: Text('Stündlich')),
                    DropdownMenuItem(value: 120, child: Text('Alle 2 Stunden')),
                    DropdownMenuItem(value: 360, child: Text('Alle 6 Stunden')),
                    DropdownMenuItem(
                        value: 720, child: Text('Alle 12 Stunden')),
                    DropdownMenuItem(value: 1440, child: Text('Täglich')),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => interval = value ?? 30),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _save(),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Speichern'),
                    ),
                    FilledButton.icon(
                      onPressed: busy || icalController.text.trim().isEmpty
                          ? null
                          : _sync,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync_rounded),
                      label: const Text('Jetzt synchronisieren'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CentralWidgetManagementCard extends StatelessWidget {
  const _CentralWidgetManagementCard({
    required this.onOpen,
    required this.configuredCount,
    required this.teamCount,
  });

  final VoidCallback onOpen;
  final int configuredCount;
  final int teamCount;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alle Mannschaftskennungen zentral verwalten',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$configuredCount von $teamCount Mannschaften sind mit '
                      'dem BfV-Widget verbunden. Alle Kennungen lassen sich '
                      'gemeinsam bearbeiten und speichern.',
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.table_rows_rounded),
                label: const Text(
                  'Alle Kennungen bearbeiten',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
}

class _BfvWidgetTeamManagerDialog extends StatefulWidget {
  const _BfvWidgetTeamManagerDialog({
    required this.repository,
    required this.teams,
  });

  final DataRepository repository;
  final List<TeamSummary> teams;

  @override
  State<_BfvWidgetTeamManagerDialog> createState() =>
      _BfvWidgetTeamManagerDialogState();
}

class _BfvWidgetTeamManagerDialogState
    extends State<_BfvWidgetTeamManagerDialog> {
  late final List<TeamSummary> teams;
  final controllers = <String, TextEditingController>{};
  final originalValues = <String, String?>{};
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    teams = widget.teams.where((team) => team.isActive).toList()
      ..sort((a, b) {
        final ageGroup = a.ageGroup.sortOrder.compareTo(b.ageGroup.sortOrder);
        return ageGroup != 0 ? ageGroup : a.teamNumber.compareTo(b.teamNumber);
      });
    for (final team in teams) {
      final value = normalizedBfvWidgetTeamId(team.bfvTeamId ?? '');
      originalValues[team.id] = value;
      controllers[team.id] = TextEditingController(text: value ?? '');
    }
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get changed => teams.any(
        (team) =>
            normalizedBfvWidgetTeamId(controllers[team.id]!.text) !=
            originalValues[team.id],
      );

  int get configuredCount => teams
      .where(
        (team) =>
            normalizedBfvWidgetTeamId(
              controllers[team.id]!.text,
            ) !=
            null,
      )
      .length;

  Future<void> _save() async {
    final values = <String, String?>{};
    final ownersByWidgetId = <String, TeamSummary>{};
    for (final team in teams) {
      final value = normalizedBfvWidgetTeamId(controllers[team.id]!.text);
      if (!isValidBfvWidgetTeamId(value)) {
        setState(() => error =
            'Die Kennung bei ${team.displayName} ist ungültig. Bitte die '
                'Kennung oder den vollständigen Widget-Code einfügen.');
        return;
      }
      if (value != null && ownersByWidgetId.containsKey(value)) {
        setState(() => error =
            'Die gleiche Kennung wurde für ${ownersByWidgetId[value]!.displayName} '
                'und ${team.displayName} eingetragen.');
        return;
      }
      if (value != null) ownersByWidgetId[value] = team;
      values[team.id] = value;
    }

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.saveBfvWidgetTeamIds(values);
      if (!mounted) return;
      Navigator.of(context).pop(configuredCount);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Die Mannschaftskennungen konnten nicht gespeichert werden.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              tooltip: 'Schließen',
              icon: const Icon(Icons.close_rounded),
            ),
            title: const Text('BfV-Mannschaftskennungen'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alle Mannschaften auf einen Blick',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Trage je Mannschaft die Kennung aus '
                      'zeigeMannschaftKomplett(…) ein. Du kannst auch den '
                      'vollständigen BfV-Widget-Code einfügen – die Kennung '
                      'wird beim Speichern automatisch erkannt.',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$configuredCount von ${teams.length} konfiguriert',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth >= 900
                      ? (constraints.maxWidth - 14) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final team in teams)
                        SizedBox(
                          width: cardWidth,
                          child: _BfvWidgetTeamField(
                            team: team,
                            controller: controllers[team.id]!,
                            enabled: !busy,
                            onChanged: () => setState(() => error = null),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton.icon(
                    onPressed: busy || !changed ? null : _save,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text(
                      'Alle Kennungen speichern',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _BfvWidgetTeamField extends StatelessWidget {
  const _BfvWidgetTeamField({
    required this.team,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TeamSummary team;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final configured = normalizedBfvWidgetTeamId(controller.text) != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.groups_rounded),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        team.ageGroup.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  configured
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: configured ? Colors.green : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Widget-Mannschaftskennung',
                hintText: 'Kennung oder Widget-Code einfügen',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.onOpen, required this.canOpen});
  final VoidCallback onOpen;
  final bool canOpen;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BfV automatisch – App bleibt übersichtlich',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                    SizedBox(height: 6),
                    Text(
                        'Eigene Spiele landen aus dem offiziellen iCal direkt im Spielbetrieb. Tabelle und sämtliche Ligaspiele zeigt das offizielle BfV-Widget in einer modernen App-Ansicht – eine manuelle Liga ist dafür nicht mehr nötig.'),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: canOpen ? onOpen : null,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Tabelle & Ligaspiele'),
              ),
            ],
          ),
        ),
      );
}

class _WidgetDomainHint extends StatelessWidget {
  const _WidgetDomainHint();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Einmalig im BfV-Widgetgenerator die Domain '
                'fcteugnapp.vercel.app freigeben. Beim ersten Öffnen bestätigt '
                'der Anwender das Laden der offiziellen BfV-Inhalte.',
              ),
            ),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.config});
  final BfvSyncConfigModel config;

  @override
  Widget build(BuildContext context) {
    final success = config.lastStatus.startsWith('SUCCESS');
    final configured = config.icalUrl?.isNotEmpty == true;
    final color = success
        ? Colors.green
        : config.lastStatus == 'ERROR'
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary;
    String formatDate(DateTime value) {
      String two(int part) => part.toString().padLeft(2, '0');
      return '${two(value.day)}.${two(value.month)}.${value.year}, '
          '${two(value.hour)}:${two(value.minute)}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    success
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_sync_rounded,
                    color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !configured
                        ? 'Noch nicht eingerichtet'
                        : success
                            ? 'BfV-Spielplan synchronisiert'
                            : config.lastStatus == 'ERROR'
                                ? 'Letzter Abgleich fehlgeschlagen'
                                : 'Bereit für den ersten Abgleich',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (config.lastSuccessAt != null) ...[
              const SizedBox(height: 6),
              Text(
                  'Zuletzt erfolgreich: ${formatDate(config.lastSuccessAt!)} Uhr'),
            ],
            if (config.lastMessage?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(config.lastMessage!,
                  style: TextStyle(
                      color: config.lastStatus == 'ERROR' ? color : null)),
            ],
            if (config.lastAttemptAt != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${config.lastCreatedCount} neu')),
                  Chip(label: Text('${config.lastUpdatedCount} aktualisiert')),
                  Chip(label: Text('${config.lastSkippedCount} unverändert')),
                  if (config.lastConflictCount > 0)
                    Chip(
                        label: Text(
                            '${config.lastConflictCount} geschützt ausgelassen')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
