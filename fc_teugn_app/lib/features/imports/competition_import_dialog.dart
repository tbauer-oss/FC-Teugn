import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/competition_import.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/widgets/adaptive_layout.dart';

const _maxImportBytes = 2 * 1024 * 1024;

@visibleForTesting
CompetitionImportFormat competitionImportFormatForFile(
  String fileName,
  String content,
) {
  final normalizedName = fileName.toLowerCase();
  final normalizedContent = content.trimLeft().toUpperCase();
  if (normalizedName.endsWith('.ics') ||
      normalizedContent.startsWith('BEGIN:VCALENDAR')) {
    return CompetitionImportFormat.ics;
  }
  return CompetitionImportFormat.csv;
}

@visibleForTesting
String decodeCompetitionImportBytes(Uint8List bytes) {
  String decoded;
  try {
    decoded = utf8.decode(bytes);
  } on FormatException {
    decoded = latin1.decode(bytes);
  }
  return decoded.startsWith('\uFEFF') ? decoded.substring(1) : decoded;
}

@visibleForTesting
bool looksLikeBfvIcs(String content) {
  final value = content.toLowerCase();
  return value.contains('begin:vcalendar') &&
      (value.contains('meisterschaften') ||
          value.contains('ical4j') ||
          value.contains('service.bfv.de'));
}

@visibleForTesting
Set<String> defaultCompetitionImportSelection(
  CompetitionImportPreview preview,
) =>
    preview.rows.where((row) => row.canBeSelected).map((row) => row.id).toSet();

@visibleForTesting
bool isCompetitionImportPlaceholder(CompetitionImportRow row) {
  final opponent = row.opponent?.trim().toLowerCase() ?? '';
  return opponent.startsWith('spielfrei') ||
      opponent.startsWith('freilos') ||
      opponent == 'pause' ||
      opponent == 'kein spiel';
}

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
  late String _teamId = widget.organization.currentTeam.id;
  CompetitionImportFormat _format = CompetitionImportFormat.ics;
  String _provider = 'BFV_ICS';
  CompetitionImportPreview? _preview;
  Set<String> _selectedRowIds = <String>{};
  String? _fileName;
  int? _fileSize;
  bool _busy = false;
  bool _sourceWins = false;
  bool _manualInput = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdaptiveDialogScaffold(
        title: 'Spielplan importieren',
        subtitle: _preview == null
            ? 'ICS- oder CSV-Datei auswählen und Spiele vor dem Speichern prüfen.'
            : 'Erkannte Spiele, Gegnerzuordnung und Änderungen kontrollieren.',
        maxWidth: 820,
        preferInlineActions: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImportSteps(previewReady: _preview != null),
            const SizedBox(height: 16),
            if (_preview == null) ...[
              _ImportSourceSection(
                organization: widget.organization,
                teamId: _teamId,
                fileName: _fileName,
                fileSize: _fileSize,
                busy: _busy,
                onTeamChanged: (value) => setState(() => _teamId = value),
                onSelectFile: _selectFile,
                onRemoveFile: _removeFile,
              ),
              const SizedBox(height: 12),
              if (_fileName == null)
                _ManualImportSection(
                  expanded: _manualInput,
                  format: _format,
                  provider: _provider,
                  controller: _content,
                  onExpandedChanged: (value) =>
                      setState(() => _manualInput = value),
                  onFormatChanged: (value) => setState(() {
                    _format = value;
                    _provider = value == CompetitionImportFormat.ics
                        ? 'BFV_ICS'
                        : 'BFV_CSV';
                  }),
                  onProviderChanged: (value) =>
                      setState(() => _provider = value),
                  onContentChanged: () => setState(() {}),
                ),
            ] else ...[
              _SelectedImportSource(
                fileName: _fileName,
                format: _format,
                provider: _provider,
              ),
              const SizedBox(height: 12),
              _PreviewSummary(
                preview: _preview!,
                selectedCount: _selectedRowIds.length,
                selectableCount:
                    defaultCompetitionImportSelection(_preview!).length,
                onSelectAll: _selectAllRows,
                onClearSelection: _clearRowSelection,
              ),
              const SizedBox(height: 12),
              for (final row in _preview!.rows) ...[
                _ImportRowTile(
                  row: row,
                  selected: _selectedRowIds.contains(row.id),
                  onSelected: row.canBeSelected
                      ? (selected) => _setRowSelected(row.id, selected)
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              if (_preview!.conflictCount > 0) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Bei Konflikten Quelldaten übernehmen'),
                  subtitle: const Text(
                    'Nur aktivieren, wenn lokale Änderungen wirklich durch die '
                    'Datei ersetzt werden sollen.',
                  ),
                  value: _sourceWins,
                  onChanged: (value) =>
                      setState(() => _sourceWins = value ?? false),
                ),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const AdaptiveButtonLabel('Abbrechen'),
          ),
          if (_preview != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : _backToSource,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const AdaptiveButtonLabel('Datei ändern'),
            ),
          FilledButton.icon(
            onPressed: _busy ||
                    (_preview == null && !_hasSource) ||
                    (_preview != null && _selectedRowIds.isEmpty)
                ? null
                : _preview == null
                    ? _createPreview
                    : _apply,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _preview == null
                        ? Icons.fact_check_rounded
                        : Icons.cloud_upload_rounded,
                  ),
            label: AdaptiveButtonLabel(
              _busy
                  ? 'Bitte warten …'
                  : _preview == null
                      ? 'Spiele prüfen'
                      : _importButtonLabel(_selectedRowIds.length),
            ),
          ),
        ],
      );

  bool get _hasSource => _content.text.trim().isNotEmpty;

  Future<void> _selectFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ics', 'csv'],
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (file.size > _maxImportBytes) {
      _showMessage(
          'Die Datei ist größer als 2 MB und kann nicht importiert werden.');
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      _showMessage('Die Datei ist leer oder konnte nicht gelesen werden.');
      return;
    }
    final content = decodeCompetitionImportBytes(bytes);
    if (content.trim().isEmpty) {
      _showMessage('Die Datei enthält keine lesbaren Spielplandaten.');
      return;
    }
    final format = competitionImportFormatForFile(file.name, content);
    setState(() {
      _content.text = content;
      _fileName = file.name;
      _fileSize = file.size;
      _format = format;
      _provider = format == CompetitionImportFormat.ics
          ? (looksLikeBfvIcs(content) ? 'BFV_ICS' : 'ICS')
          : 'BFV_CSV';
      _manualInput = false;
    });
  }

  void _removeFile() => setState(() {
        _content.clear();
        _fileName = null;
        _fileSize = null;
      });

  void _backToSource() => setState(() {
        _preview = null;
        _selectedRowIds = <String>{};
        _sourceWins = false;
      });

  void _setRowSelected(String rowId, bool selected) => setState(() {
        final next = {..._selectedRowIds};
        if (selected) {
          next.add(rowId);
        } else {
          next.remove(rowId);
        }
        _selectedRowIds = next;
      });

  void _selectAllRows() => setState(() {
        _selectedRowIds = defaultCompetitionImportSelection(_preview!);
      });

  void _clearRowSelection() => setState(() {
        _selectedRowIds = <String>{};
      });

  Future<void> _createPreview() async {
    setState(() => _busy = true);
    try {
      final preview =
          await ref.read(repositoryProvider).previewCompetitionImport(
                teamId: _teamId,
                format: _format,
                provider: _provider,
                content: _content.text,
                fileName: _fileName,
              );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _selectedRowIds = defaultCompetitionImportSelection(preview);
      });
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error, 'Importvorschau'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_selectedRowIds.isEmpty) {
      _showMessage('Wähle mindestens einen Termin für den Import aus.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).applyCompetitionImport(
            _preview!.id,
            sourceWinsConflicts: _sourceWins,
            selectedRowIds: _selectedRowIds,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(_errorMessage(error, 'Spielplanimport'));
      setState(() => _busy = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  String _errorMessage(Object error, String action) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        if (message is List) return message.join(' ');
        return message.toString();
      }
    }
    return '$action konnte nicht abgeschlossen werden. Bitte Datei prüfen und erneut versuchen.';
  }
}

class _ImportSteps extends StatelessWidget {
  const _ImportSteps({required this.previewReady});

  final bool previewReady;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _StepBadge(number: 1, label: 'Datei', active: !previewReady),
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
          _StepBadge(number: 2, label: 'Prüfen', active: previewReady),
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
          const _StepBadge(number: 3, label: 'Speichern'),
        ],
      );
}

class _StepBadge extends StatelessWidget {
  const _StepBadge(
      {required this.number, required this.label, this.active = false});

  final int number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Schritt $number: $label',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor:
                  active ? AppColors.yellow : context.appColors.surfaceMuted,
              foregroundColor: AppColors.black,
              child: Text('$number',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 3),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}

class _ImportSourceSection extends StatelessWidget {
  const _ImportSourceSection({
    required this.organization,
    required this.teamId,
    required this.fileName,
    required this.fileSize,
    required this.busy,
    required this.onTeamChanged,
    required this.onSelectFile,
    required this.onRemoveFile,
  });

  final OrganizationContext organization;
  final String teamId;
  final String? fileName;
  final int? fileSize;
  final bool busy;
  final ValueChanged<String> onTeamChanged;
  final VoidCallback onSelectFile;
  final VoidCallback onRemoveFile;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('1. Zielmannschaft',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: teamId,
              decoration: const InputDecoration(labelText: 'Mannschaft'),
              items: organization.teams
                  .map((team) => DropdownMenuItem(
                        value: team.id,
                        child: Text(team.displayName),
                      ))
                  .toList(),
              onChanged: busy ? null : (value) => onTeamChanged(value!),
            ),
            const SizedBox(height: 14),
            Text('2. Spielplandatei',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'BfV-ICS wird automatisch erkannt. Lange und umgebrochene Einträge '
              'sowie E7-Mannschaftsbezeichnungen werden korrekt aufbereitet.',
            ),
            const SizedBox(height: 10),
            if (fileName == null)
              FilledButton.icon(
                onPressed: busy ? null : onSelectFile,
                icon: const Icon(Icons.upload_file_rounded),
                label:
                    const AdaptiveButtonLabel('ICS- oder CSV-Datei auswählen'),
              )
            else
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.yellowSoft,
                  child: Icon(Icons.event_available_rounded,
                      color: AppColors.black),
                ),
                title: Text(fileName!,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${((fileSize ?? 0) / 1024).toStringAsFixed(1)} KB · bereit zur Prüfung'),
                trailing: IconButton(
                  tooltip: 'Datei entfernen',
                  onPressed: busy ? null : onRemoveFile,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
          ],
        ),
      );
}

class _ManualImportSection extends StatelessWidget {
  const _ManualImportSection({
    required this.expanded,
    required this.format,
    required this.provider,
    required this.controller,
    required this.onExpandedChanged,
    required this.onFormatChanged,
    required this.onProviderChanged,
    required this.onContentChanged,
  });

  final bool expanded;
  final CompetitionImportFormat format;
  final String provider;
  final TextEditingController controller;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<CompetitionImportFormat> onFormatChanged;
  final ValueChanged<String> onProviderChanged;
  final VoidCallback onContentChanged;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpandedChanged,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        leading: const Icon(Icons.tune_rounded),
        title: const Text('Erweitert: Inhalt manuell einfügen'),
        subtitle: const Text('Nur nötig, wenn keine Datei vorliegt.'),
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final fields = [
              DropdownButtonFormField<CompetitionImportFormat>(
                initialValue: format,
                decoration: const InputDecoration(labelText: 'Dateiformat'),
                items: const [
                  DropdownMenuItem(
                      value: CompetitionImportFormat.ics,
                      child: Text('ICS-Kalender')),
                  DropdownMenuItem(
                      value: CompetitionImportFormat.csv,
                      child: Text('CSV-Tabelle')),
                ],
                onChanged: (value) => onFormatChanged(value!),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(format),
                initialValue: provider,
                decoration: const InputDecoration(labelText: 'Quelle'),
                items: (format == CompetitionImportFormat.ics
                        ? const ['BFV_ICS', 'ICS']
                        : const ['BFV_CSV', 'DFBNET_CSV', 'GENERIC_CSV'])
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_providerLabel(value)),
                        ))
                    .toList(),
                onChanged: (value) => onProviderChanged(value!),
              ),
            ];
            return narrow
                ? Column(
                    children: [fields[0], const SizedBox(height: 8), fields[1]])
                : Row(children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[1])
                  ]);
          }),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: (_) => onContentChanged(),
            minLines: 6,
            maxLines: 12,
            decoration: InputDecoration(
              labelText: format == CompetitionImportFormat.ics
                  ? 'ICS-Inhalt'
                  : 'CSV-Inhalt',
              alignLabelWithHint: true,
              hintText: format == CompetitionImportFormat.ics
                  ? 'BEGIN:VCALENDAR\nBEGIN:VEVENT\n…'
                  : 'Datum;Uhrzeit;Gegner;Heimspiel;Wettbewerb;Ort',
            ),
          ),
        ],
      );
}

class _SelectedImportSource extends StatelessWidget {
  const _SelectedImportSource(
      {required this.fileName, required this.format, required this.provider});

  final String? fileName;
  final CompetitionImportFormat format;
  final String provider;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.appInfo.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.description_rounded, color: context.appInfo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName ?? 'Manuell eingefügter Inhalt',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                      '${format.name.toUpperCase()} · ${_providerLabel(provider)}'),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({
    required this.preview,
    required this.selectedCount,
    required this.selectableCount,
    required this.onSelectAll,
    required this.onClearSelection,
  });

  final CompetitionImportPreview preview;
  final int selectedCount;
  final int selectableCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Importvorschau', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _CountChip('Neu', preview.createCount, context.appSuccess),
              _CountChip('Aktualisieren', preview.updateCount, context.appInfo),
              _CountChip('Unverändert', preview.skipCount,
                  context.appColors.textMuted),
              _CountChip(
                  'Konflikte', preview.conflictCount, context.appWarning),
              _CountChip('Ungültig', preview.invalidCount, Colors.redAccent),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: AppColors.yellowSoft.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final actions = Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed:
                          selectedCount == selectableCount ? null : onSelectAll,
                      icon: const Icon(Icons.select_all_rounded),
                      label: const Text('Alle auswählen'),
                    ),
                    TextButton.icon(
                      onPressed: selectedCount == 0 ? null : onClearSelection,
                      icon: const Icon(Icons.deselect_rounded),
                      label: const Text('Auswahl aufheben'),
                    ),
                  ],
                );
                final selection = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedCount von $selectableCount Terminen ausgewählt',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Alle übernehmbaren Termine sind zunächst ausgewählt.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
                if (constraints.maxWidth < 580) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [selection, const SizedBox(height: 6), actions],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: selection),
                    const SizedBox(width: 8),
                    actions,
                  ],
                );
              },
            ),
          ),
        ],
      );
}

class _CountChip extends StatelessWidget {
  const _CountChip(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text('$count'),
        ),
        label: Text(label),
      );
}

class _ImportRowTile extends StatelessWidget {
  const _ImportRowTile({
    required this.row,
    required this.selected,
    required this.onSelected,
  });

  final CompetitionImportRow row;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (row.action) {
      CompetitionImportAction.create => (
          Icons.add_circle_rounded,
          context.appSuccess,
          'Neu'
        ),
      CompetitionImportAction.update => (
          Icons.sync_rounded,
          context.appInfo,
          'Aktualisieren'
        ),
      CompetitionImportAction.skip => (
          Icons.done_rounded,
          context.appColors.textMuted,
          'Unverändert'
        ),
      CompetitionImportAction.conflict => (
          Icons.warning_rounded,
          context.appWarning,
          'Konflikt'
        ),
      CompetitionImportAction.invalid => (
          Icons.error_rounded,
          Colors.redAccent,
          'Ungültig'
        ),
    };
    final details = [
      if (row.startAt != null) _dateTime(row.startAt!.toLocal()),
      if (row.isHome != null) row.isHome! ? 'Heimspiel' : 'Auswärtsspiel',
      if ((row.competition ?? '').isNotEmpty) row.competition!,
      if ((row.location ?? '').isNotEmpty) row.location!,
    ];
    final placeholder = isCompetitionImportPlaceholder(row);
    return Semantics(
      container: true,
      toggled: row.canBeSelected ? selected : null,
      enabled: row.canBeSelected,
      label: row.canBeSelected
          ? '${row.opponent ?? 'Termin'} für Import auswählen'
          : '${row.opponent ?? 'Termin'} kann nicht ausgewählt werden',
      child: InkWell(
        onTap: onSelected == null ? null : () => onSelected!(!selected),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.yellowSoft.withValues(alpha: .18)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? context.appWarning
                  : Theme.of(context).dividerColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    key: ValueKey('competition-import-row-${row.id}'),
                    value: selected,
                    onChanged: onSelected == null
                        ? null
                        : (value) => onSelected!(value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 2),
                  Icon(icon, color: color),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      row.opponent ?? 'Zeile ${row.rowNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _StatusPill(label: label, color: color),
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(details.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (row.action != CompetitionImportAction.invalid) ...[
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      row.opponentId != null
                          ? Icons.link_rounded
                          : Icons.info_outline_rounded,
                      size: 17,
                      color: row.opponentId != null
                          ? context.appSuccess
                          : context.appColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        row.opponentId != null
                            ? 'Mit vorhandenem Gegner verknüpft'
                            : 'Noch keinem Gegnerstammsatz zugeordnet',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              if (row.messages.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(row.messages.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (placeholder) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.yellowSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Hinweis: „SPIELFREI“ ist kein echtes Spiel. Entferne den Haken, wenn dieser Eintrag nicht übernommen werden soll.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      );
}

String _providerLabel(String provider) => switch (provider) {
      'BFV_ICS' => 'BfV-Spielplan',
      'BFV_CSV' => 'BfV CSV',
      'DFBNET_CSV' => 'DFBnet CSV',
      'GENERIC_CSV' => 'Eigene CSV',
      _ => 'ICS-Kalender',
    };

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} Uhr';

String _importButtonLabel(int count) =>
    count == 1 ? '1 Spiel importieren' : '$count Spiele importieren';
