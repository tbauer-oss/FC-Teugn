import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/competition_import.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';

class CompetitionImportDialog extends ConsumerStatefulWidget {
  const CompetitionImportDialog({super.key, required this.organization});

  final OrganizationContext organization;

  @override
  ConsumerState<CompetitionImportDialog> createState() =>
      _CompetitionImportDialogState();
}

class _CompetitionImportDialogState
    extends ConsumerState<CompetitionImportDialog> {
  final _content = TextEditingController();
  String _provider = 'BFV_CSV';
  late String _teamId = widget.organization.currentTeam.id;
  CompetitionImportFormat _format = CompetitionImportFormat.csv;
  CompetitionImportPreview? _preview;
  bool _busy = false;
  bool _sourceWins = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spielplan importieren'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Unterstützt BFV-/DFBnet-CSV-Exporte und ICS-Spielpläne. '
                        'Es wird keine inoffizielle SpielPLUS-API abgefragt. '
                        'Vor dem Speichern erscheint immer eine Konfliktvorschau.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _teamId,
                decoration: const InputDecoration(labelText: 'Mannschaft'),
                items: widget.organization.teams
                    .map(
                      (team) => DropdownMenuItem(
                        value: team.id,
                        child: Text(team.displayName),
                      ),
                    )
                    .toList(),
                onChanged: _preview == null
                    ? (value) => setState(() => _teamId = value!)
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<CompetitionImportFormat>(
                      initialValue: _format,
                      decoration:
                          const InputDecoration(labelText: 'Dateiformat'),
                      items: const [
                        DropdownMenuItem(
                          value: CompetitionImportFormat.csv,
                          child: Text('CSV (BFV/DFBnet oder eigene Vorlage)'),
                        ),
                        DropdownMenuItem(
                          value: CompetitionImportFormat.ics,
                          child: Text('ICS-Kalender'),
                        ),
                      ],
                      onChanged: _preview == null
                          ? (value) => setState(() {
                                _format = value!;
                                _provider =
                                    value == CompetitionImportFormat.csv
                                        ? 'BFV_CSV'
                                        : 'ICS';
                              })
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_format),
                      initialValue: _provider,
                      decoration:
                          const InputDecoration(labelText: 'Importquelle'),
                      items: (_format == CompetitionImportFormat.ics
                              ? const ['ICS']
                              : const [
                                  'BFV_CSV',
                                  'DFBNET_CSV',
                                  'GENERIC_CSV',
                                ])
                          .map(
                            (provider) => DropdownMenuItem(
                              value: provider,
                              child: Text(provider.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                      onChanged: _preview == null
                          ? (value) => setState(() => _provider = value!)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _content,
                onChanged: (_) => setState(() {}),
                enabled: _preview == null,
                minLines: 8,
                maxLines: 16,
                decoration: InputDecoration(
                  labelText: _format == CompetitionImportFormat.csv
                      ? 'CSV-Inhalt einfügen'
                      : 'ICS-Inhalt einfügen',
                  alignLabelWithHint: true,
                  hintText: _format == CompetitionImportFormat.csv
                      ? 'Spielkennung;Datum;Uhrzeit;Gegner;Heimspiel;Wettbewerb;Ort'
                      : 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:…',
                ),
              ),
              if (_preview != null) ...[
                const SizedBox(height: 20),
                _PreviewSummary(preview: _preview!),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _preview!.rows.length,
                    itemBuilder: (context, index) =>
                        _ImportRowTile(row: _preview!.rows[index]),
                  ),
                ),
                if (_preview!.conflictCount > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Bei Konflikten Quelldaten übernehmen',
                    ),
                    subtitle: const Text(
                      'Lokale Änderungen werden sonst sicher übersprungen.',
                    ),
                    value: _sourceWins,
                    onChanged: (value) =>
                        setState(() => _sourceWins = value ?? false),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        if (_preview != null)
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _preview = null;
                      _sourceWins = false;
                    }),
            child: const Text('Zurück'),
          ),
        FilledButton.icon(
          onPressed: _busy ||
                  (_preview == null && _content.text.trim().isEmpty)
              ? null
              : _preview == null
                  ? _createPreview
                  : _apply,
          icon: Icon(
            _preview == null
                ? Icons.fact_check_rounded
                : Icons.cloud_upload_rounded,
          ),
          label: Text(_busy
              ? 'Bitte warten …'
              : _preview == null
                  ? 'Vorschau prüfen'
                  : 'Import anwenden'),
        ),
      ],
    );
  }

  Future<void> _createPreview() async {
    setState(() => _busy = true);
    try {
      final preview = await ref
          .read(repositoryProvider)
          .previewCompetitionImport(
            teamId: _teamId,
            format: _format,
            provider: _provider,
            content: _content.text,
          );
      if (mounted) setState(() => _preview = preview);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importvorschau konnte nicht erstellt werden.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).applyCompetitionImport(
            _preview!.id,
            sourceWinsConflicts: _sourceWins,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spielplanimport ist fehlgeschlagen.')),
      );
      setState(() => _busy = false);
    }
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview});

  final CompetitionImportPreview preview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _CountChip('Neu', preview.createCount, AppColors.teal),
        _CountChip('Aktualisieren', preview.updateCount, AppColors.blue),
        _CountChip('Unverändert', preview.skipCount, AppColors.muted),
        _CountChip('Konflikte', preview.conflictCount, AppColors.orange),
        _CountChip('Ungültig', preview.invalidCount, Colors.redAccent),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text('$count'),
        ),
        label: Text(label),
      );
}

class _ImportRowTile extends StatelessWidget {
  const _ImportRowTile({required this.row});

  final CompetitionImportRow row;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (row.action) {
      CompetitionImportAction.create =>
        (Icons.add_circle_rounded, AppColors.teal, 'Neu'),
      CompetitionImportAction.update =>
        (Icons.sync_rounded, AppColors.blue, 'Aktualisieren'),
      CompetitionImportAction.skip =>
        (Icons.done_rounded, AppColors.muted, 'Unverändert'),
      CompetitionImportAction.conflict =>
        (Icons.warning_rounded, AppColors.orange, 'Konflikt'),
      CompetitionImportAction.invalid =>
        (Icons.error_rounded, Colors.redAccent, 'Ungültig'),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        row.opponent ?? 'Zeile ${row.rowNumber}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if (row.startAt != null) _dateTime(row.startAt!.toLocal()),
          ...row.messages,
        ].join(' · '),
      ),
      trailing: Text(label, style: TextStyle(color: color)),
    );
  }
}

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
