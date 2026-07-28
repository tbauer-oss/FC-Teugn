import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';

class OrganizationAdminTools extends ConsumerStatefulWidget {
  const OrganizationAdminTools({super.key, required this.organization});

  final OrganizationContext organization;

  @override
  ConsumerState<OrganizationAdminTools> createState() =>
      _OrganizationAdminToolsState();
}

class _OrganizationAdminToolsState
    extends ConsumerState<OrganizationAdminTools> {
  bool _loading = true;
  List<RuleProfileModel> _profiles = const [];
  List<SeasonTransitionModel> _transitions = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repository = ref.read(repositoryProvider);
      final values = await Future.wait([
        repository.ruleProfiles(),
        repository.seasonTransitions(),
      ]);
      if (!mounted) return;
      setState(() {
        _profiles = values[0] as List<RuleProfileModel>;
        _transitions = values[1] as List<SeasonTransitionModel>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vereinsadministration',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Regelwerke versionieren und den Saisonwechsel kontrolliert vorbereiten.',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Neu laden',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final cards = [
              Expanded(
                child: _AdminPanel(
                  icon: Icons.rule_folder_outlined,
                  title: 'Regelprofile',
                  subtitle: 'Versioniert, nachvollziehbar und freigabepflichtig',
                  actionLabel: 'Neues Regelprofil',
                  onAction: _createRuleProfile,
                  child: _loading
                      ? const LinearProgressIndicator()
                      : _RuleProfileList(
                          profiles: _profiles,
                          onApprove: _approveRuleProfile,
                        ),
                ),
              ),
              Expanded(
                child: _AdminPanel(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Geführter Saisonwechsel',
                  subtitle: 'Vorschau vor jeder Änderung – keine Altdatenlöschung',
                  actionLabel: 'Saison vorbereiten',
                  onAction: _prepareSeason,
                  child: _loading
                      ? const LinearProgressIndicator()
                      : _SeasonTransitionList(transitions: _transitions),
                ),
              ),
            ];
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [cards[0], const SizedBox(width: 16), cards[1]],
              );
            }
            return Column(
              children: [
                SizedBox(width: double.infinity, child: cards[0].child),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: cards[1].child),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _createRuleProfile() async {
    final draft = await showDialog<_RuleProfileDraft>(
      context: context,
      builder: (context) =>
          _RuleProfileDialog(organization: widget.organization),
    );
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).createRuleProfile(
            teamId: draft.teamId,
            name: draft.name,
            validFrom: draft.validFrom,
            gameFormat: draft.gameFormat,
            teamSize: draft.teamSize,
            maxSquadSize: draft.maxSquadSize,
            periodCount: draft.periodCount,
            periodMinutes: draft.periodMinutes,
            sourceNote: draft.sourceNote,
            festivalMode: draft.festivalMode,
            showResults: draft.showResults,
            showTable: draft.showTable,
          );
      await _reload();
      _message('Regelprofil wurde als neuer Entwurf gespeichert.');
    } on DioException catch (error) {
      _message(_dioMessage(error, 'Regelprofil konnte nicht gespeichert werden.'));
    }
  }

  Future<void> _approveRuleProfile(RuleProfileModel profile) async {
    try {
      await ref.read(repositoryProvider).approveRuleProfile(profile.id);
      await _reload();
      _message('${profile.name} · Version ${profile.version} ist freigegeben.');
    } on DioException catch (error) {
      _message(_dioMessage(error, 'Freigabe fehlgeschlagen.'));
    }
  }

  Future<void> _prepareSeason() async {
    final draft = await showDialog<_SeasonDraft>(
      context: context,
      builder: (context) =>
          _SeasonDraftDialog(current: widget.organization.season),
    );
    if (draft == null) return;
    try {
      final preview =
          await ref.read(repositoryProvider).previewSeasonTransition(
                name: draft.name,
                startDate: draft.start,
                endDate: draft.end,
              );
      if (!mounted) return;
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => _SeasonPreviewDialog(transition: preview),
      );
      if (apply != true) {
        await _reload();
        return;
      }
      await ref.read(repositoryProvider).applySeasonTransition(preview.id);
      ref.invalidate(organizationProvider);
      await _reload();
      _message('Saison ${draft.name} wurde vollständig angelegt und aktiviert.');
    } on DioException catch (error) {
      _message(_dioMessage(error, 'Saisonwechsel konnte nicht ausgeführt werden.'));
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AdminPanel extends StatelessWidget {
  const _AdminPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: AppColors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleProfileList extends StatelessWidget {
  const _RuleProfileList({required this.profiles, required this.onApprove});

  final List<RuleProfileModel> profiles;
  final ValueChanged<RuleProfileModel> onApprove;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return const _InlineEmpty(
        message: 'Noch keine Regelprofile hinterlegt.',
      );
    }
    return Column(
      children: [
        for (final profile in profiles.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${profile.ageGroupCode} · ${profile.teamName} · ${profile.name}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${profile.gameFormat} · ${profile.teamSize} Spieler · '
                          '${profile.periodCount} × ${profile.periodMinutes} Min. · V${profile.version}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (profile.approved)
                    const Chip(
                      avatar: Icon(Icons.verified_rounded, size: 16),
                      label: Text('Freigegeben'),
                    )
                  else
                    TextButton(
                      onPressed: () => onApprove(profile),
                      child: const Text('Freigeben'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SeasonTransitionList extends StatelessWidget {
  const _SeasonTransitionList({required this.transitions});

  final List<SeasonTransitionModel> transitions;

  @override
  Widget build(BuildContext context) {
    if (transitions.isEmpty) {
      return const _InlineEmpty(
        message: 'Noch kein Saisonwechsel vorbereitet.',
      );
    }
    return Column(
      children: [
        for (final transition in transitions.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: _statusColor(transition.status).withValues(alpha: .12),
              child: Icon(
                transition.status == 'APPLIED'
                    ? Icons.check_rounded
                    : transition.status == 'FAILED'
                        ? Icons.error_outline_rounded
                        : Icons.visibility_outlined,
                color: _statusColor(transition.status),
              ),
            ),
            title: Text(
              transition.targetSeasonName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${_statusLabel(transition.status)} · ${_date(transition.createdAt)}',
            ),
          ),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

class _RuleProfileDialog extends StatefulWidget {
  const _RuleProfileDialog({required this.organization});
  final OrganizationContext organization;

  @override
  State<_RuleProfileDialog> createState() => _RuleProfileDialogState();
}

class _RuleProfileDialogState extends State<_RuleProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'BFV-Spielbetrieb');
  final _format = TextEditingController(text: 'Kleinfeld');
  final _teamSize = TextEditingController(text: '7');
  final _squadSize = TextEditingController(text: '12');
  final _periodCount = TextEditingController(text: '2');
  final _periodMinutes = TextEditingController(text: '25');
  final _source = TextEditingController(text: 'BFV-Jugendordnung');
  late String _teamId = widget.organization.currentTeam.id;
  late DateTime _validFrom = widget.organization.season.startDate;
  bool _festival = false;
  bool _showResults = true;
  bool _showTable = true;

  @override
  void dispose() {
    _name.dispose();
    _format.dispose();
    _teamSize.dispose();
    _squadSize.dispose();
    _periodCount.dispose();
    _periodMinutes.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Regelprofil anlegen'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _teamId,
                  decoration: const InputDecoration(labelText: 'Mannschaft'),
                  items: [
                    for (final team in widget.organization.teams)
                      DropdownMenuItem(
                        value: team.id,
                        child: Text(team.displayName),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _teamId = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Profilname'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _format,
                  decoration: const InputDecoration(labelText: 'Spielform'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _numberField(_teamSize, 'Teamgröße')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_squadSize, 'Max. Kader')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _numberField(_periodCount, 'Abschnitte')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_periodMinutes, 'Minuten je Abschnitt')),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _source,
                  decoration: const InputDecoration(
                    labelText: 'Quelle / Beschluss',
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Festivalmodus'),
                  value: _festival,
                  onChanged: (value) => setState(() => _festival = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ergebnisse anzeigen'),
                  value: _showResults,
                  onChanged: (value) =>
                      setState(() => _showResults = value ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tabelle anzeigen'),
                  value: _showTable,
                  onChanged: (value) =>
                      setState(() => _showTable = value ?? true),
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
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _RuleProfileDraft(
                teamId: _teamId,
                name: _name.text.trim(),
                validFrom: _validFrom,
                gameFormat: _format.text.trim(),
                teamSize: int.parse(_teamSize.text),
                maxSquadSize: int.tryParse(_squadSize.text),
                periodCount: int.parse(_periodCount.text),
                periodMinutes: int.parse(_periodMinutes.text),
                sourceNote: _source.text.trim(),
                festivalMode: _festival,
                showResults: _showResults,
                showTable: _showTable,
              ),
            );
          },
          child: const Text('Als Entwurf speichern'),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = int.tryParse(value ?? '');
        return number == null || number < 1 ? 'Positive Zahl nötig' : null;
      },
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;
}

class _SeasonDraftDialog extends StatefulWidget {
  const _SeasonDraftDialog({required this.current});
  final SeasonSummary current;

  @override
  State<_SeasonDraftDialog> createState() => _SeasonDraftDialogState();
}

class _SeasonDraftDialogState extends State<_SeasonDraftDialog> {
  late final TextEditingController _name;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = DateTime(
      widget.current.startDate.year + 1,
      widget.current.startDate.month,
      widget.current.startDate.day,
    );
    _end = DateTime(
      widget.current.endDate.year + 1,
      widget.current.endDate.month,
      widget.current.endDate.day,
    );
    _name = TextEditingController(
      text: '${_start.year}/${(_end.year % 100).toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Saison vorbereiten'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Zuerst wird nur eine prüfbare Vorschau erstellt. Teams rücken automatisch eine Altersklasse weiter; bestehende Termine und Statistiken bleiben unverändert.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Saisonname'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.event_rounded),
                    label: Text('Beginn ${_date(_start)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.event_available_rounded),
                    label: Text('Ende ${_date(_end)}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _name.text.trim().isEmpty || _end.isBefore(_start)
              ? null
              : () => Navigator.pop(
                    context,
                    _SeasonDraft(
                      name: _name.text.trim(),
                      start: _start,
                      end: _end,
                    ),
                  ),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Vorschau erstellen'),
        ),
      ],
    );
  }

  Future<void> _pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(widget.current.startDate.year),
      lastDate: DateTime(widget.current.endDate.year + 5),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }
}

class _SeasonPreviewDialog extends StatelessWidget {
  const _SeasonPreviewDialog({required this.transition});
  final SeasonTransitionModel transition;

  @override
  Widget build(BuildContext context) {
    final totals =
        transition.preview['totals'] as Map<String, dynamic>? ?? const {};
    final teams = transition.preview['teams'] as List<dynamic>? ?? const [];
    final warnings =
        transition.preview['warnings'] as List<dynamic>? ?? const [];
    return AlertDialog(
      title: Text('Vorschau · ${transition.targetSeasonName}'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PreviewMetric('${totals['teams'] ?? 0}', 'Teams'),
                  _PreviewMetric(
                    '${totals['playersToMove'] ?? 0}',
                    'Spieler wechseln',
                  ),
                  _PreviewMetric(
                    '${totals['playersToArchive'] ?? 0}',
                    'Archiviert',
                  ),
                  _PreviewMetric(
                    '${totals['membershipsToCopy'] ?? 0}',
                    'Zuordnungen',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (final raw in teams)
                Builder(
                  builder: (context) {
                    final team = raw as Map<String, dynamic>;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.arrow_forward_rounded),
                      title: Text(
                        '${team['sourceAgeGroupCode']} · ${team['sourceName']}  →  '
                        '${team['targetAgeGroupCode']} · ${team['targetName']}',
                      ),
                      subtitle: Text(
                        '${team['activePlayerCount']} aktive Spieler · '
                        '${team['staffCount']} Mitgliedschaften',
                      ),
                    );
                  },
                ),
              for (final warning in warnings)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(warning.toString()),
                ),
              const SizedBox(height: 12),
              const Text(
                'Mit der Ausführung wird die neue Saison aktiv. Historische Mannschaften, Termine, Ergebnisse und Sorgeberechtigten-Verknüpfungen bleiben erhalten.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nur Vorschau speichern'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Geprüft ausführen'),
        ),
      ],
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RuleProfileDraft {
  const _RuleProfileDraft({
    required this.teamId,
    required this.name,
    required this.validFrom,
    required this.gameFormat,
    required this.teamSize,
    required this.maxSquadSize,
    required this.periodCount,
    required this.periodMinutes,
    required this.sourceNote,
    required this.festivalMode,
    required this.showResults,
    required this.showTable,
  });
  final String teamId;
  final String name;
  final DateTime validFrom;
  final String gameFormat;
  final int teamSize;
  final int? maxSquadSize;
  final int periodCount;
  final int periodMinutes;
  final String sourceNote;
  final bool festivalMode;
  final bool showResults;
  final bool showTable;
}

class _SeasonDraft {
  const _SeasonDraft({
    required this.name,
    required this.start,
    required this.end,
  });
  final String name;
  final DateTime start;
  final DateTime end;
}

String _dioMessage(DioException error, String fallback) {
  final data = error.response?.data;
  return data is Map<String, dynamic>
      ? data['message'] as String? ?? fallback
      : fallback;
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

String _statusLabel(String status) => switch (status) {
      'APPLIED' => 'Ausgeführt',
      'FAILED' => 'Fehlgeschlagen',
      _ => 'Vorschau',
    };
Color _statusColor(String status) => switch (status) {
      'APPLIED' => AppColors.teal,
      'FAILED' => Colors.red,
      _ => AppColors.blue,
    };
