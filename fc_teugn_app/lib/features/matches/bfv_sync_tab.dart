import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data_repository.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';

class BfvSyncTab extends StatefulWidget {
  const BfvSyncTab({
    super.key,
    required this.repository,
    required this.teams,
  });

  final DataRepository repository;
  final List<TeamSummary> teams;

  @override
  State<BfvSyncTab> createState() => _BfvSyncTabState();
}

class _BfvSyncTabState extends State<BfvSyncTab> {
  final teamPageController = TextEditingController();
  final icalController = TextEditingController();
  final viewController = TextEditingController();
  String? teamId;
  BfvSyncConfigModel? config;
  bool enabled = true;
  int interval = 30;
  bool busy = false;
  String? error;

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
    viewController.dispose();
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
    viewController.text = value.officialViewUrl ?? value.teamPageUrl ?? '';
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
        officialViewUrl: viewController.text.trim(),
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

  Future<void> _openOfficialView() async {
    final raw = viewController.text.trim().isNotEmpty
        ? viewController.text.trim()
        : teamPageController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Die offizielle BfV-Ansicht konnte nicht geöffnet werden.')),
        );
      }
    }
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
        _IntroCard(
            onOpen: _openOfficialView,
            canOpen: viewController.text.trim().isNotEmpty ||
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
                    'Die Adressen kopierst du auf der BfV-Mannschaftsseite über „iCal“ beziehungsweise „Widget“. Es werden ausschließlich offizielle bfv.de-Adressen akzeptiert.'),
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
                  controller: viewController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Offizielle Liga-/Widget-Ansicht',
                    helperText:
                        'Optional – sonst wird die Mannschaftsseite geöffnet.',
                  ),
                ),
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
                        'Eigene Spiele landen aus dem offiziellen iCal direkt im Spielbetrieb. Tabelle und sämtliche Ligaspiele öffnest du in der offiziellen BfV-Ansicht – eine manuelle Liga ist dafür nicht mehr nötig.'),
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
