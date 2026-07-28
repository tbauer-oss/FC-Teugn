import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/training.dart';
import '../../core/providers.dart';
import '../shared/page_scaffold.dart';

class TrainingsPage extends ConsumerStatefulWidget {
  const TrainingsPage({super.key});

  @override
  ConsumerState<TrainingsPage> createState() => _TrainingsPageState();
}

class _TrainingsPageState extends ConsumerState<TrainingsPage> {
  List<TrainingModel>? _trainings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(repositoryProvider).trainings();
      if (mounted) setState(() => _trainings = items);
    } catch (_) {
      if (mounted) setState(() => _error = 'Trainings konnten nicht geladen werden.');
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'Trainingsplanung',
        subtitle: 'Einheiten vorbereiten, Übungen kombinieren und Anwesenheit erfassen.',
        child: _error != null
            ? EmptyState(
                icon: Icons.fitness_center_rounded,
                title: 'Trainingsplanung nicht erreichbar',
                message: _error!,
              )
            : _trainings == null
                ? const Center(child: CircularProgressIndicator())
                : _buildList(context),
      );

  Widget _buildList(BuildContext context) {
    final upcoming = _trainings!
        .where((item) => item.startAt.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .toList();
    if (upcoming.isEmpty) {
      return const EmptyState(
        icon: Icons.event_available_outlined,
        title: 'Keine Trainingstermine geplant',
        message: 'Lege zuerst im Kalender einen Trainingstermin an.',
      );
    }
    return ListView(
      children: [
        for (final training in upcoming)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.push('/trainer/training/${training.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      _DateTile(date: training.startAt.toLocal()),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              training.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              training.location,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                Chip(
                                  avatar: Icon(
                                    training.plan == null
                                        ? Icons.edit_calendar_outlined
                                        : Icons.check_circle_outline_rounded,
                                    size: 17,
                                  ),
                                  label: Text(
                                    training.plan == null
                                        ? 'Noch nicht geplant'
                                        : '${training.plan!.items.length} Bausteine · ${training.plan!.durationMinutes} Min.',
                                  ),
                                ),
                                if (training.plan?.focusAreas.isNotEmpty == true)
                                  for (final focus in training.plan!.focusAreas.take(3))
                                    Chip(label: Text(focus)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Container(
        width: 66,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.teal.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '${date.day}.${date.month}.',
              style: const TextStyle(
                color: AppColors.teal,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            Text(
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      );
}

class TrainingPlannerPage extends ConsumerStatefulWidget {
  const TrainingPlannerPage({required this.trainingId, super.key});
  final String trainingId;

  @override
  ConsumerState<TrainingPlannerPage> createState() => _TrainingPlannerPageState();
}

class _TrainingPlannerPageState extends ConsumerState<TrainingPlannerPage> {
  TrainingModel? _training;
  List<TrainingExerciseModel> _exercises = const [];
  List<TrainingPlanItemModel> _items = [];
  Map<String, TrainingAttendanceStatus> _attendance = {};
  final _focus = TextEditingController();
  final _goals = TextEditingController();
  final _coaches = TextEditingController();
  final _materials = TextEditingController();
  final _pitch = TextEditingController();
  final _feedback = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    _goals.dispose();
    _coaches.dispose();
    _materials.dispose();
    _pitch.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(repositoryProvider);
      final values = await Future.wait([
        repository.training(widget.trainingId),
        repository.trainingExercises(),
      ]);
      final training = values.first as TrainingModel;
      if (!mounted) return;
      setState(() {
        _training = training;
        _exercises = values[1] as List<TrainingExerciseModel>;
        _items = training.plan?.items.toList() ?? [];
        _focus.text = training.plan?.focusAreas.join(', ') ?? '';
        _goals.text = training.plan?.learningGoals ?? '';
        _coaches.text = training.plan?.coaches ?? '';
        _materials.text = training.plan?.materials ?? '';
        _pitch.text = training.plan?.pitchSetup ?? '';
        _feedback.text = training.plan?.feedback ?? '';
        _attendance = {
          for (final entry in training.attendance)
            if (entry.status != null) entry.playerId: entry.status!,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Die Trainingseinheit konnte nicht geladen werden.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PageScaffold(
        title: 'Training',
        subtitle: 'Einheit wird geladen …',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_training == null || _error != null) {
      return PageScaffold(
        title: 'Training',
        subtitle: 'Planung nicht verfügbar',
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Training nicht erreichbar',
          message: _error!,
        ),
      );
    }
    final date = _training!.startAt.toLocal();
    return DefaultTabController(
      length: 3,
      child: PageScaffold(
        title: _training!.title,
        subtitle:
            '${date.day}.${date.month}.${date.year} · ${_training!.location}',
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.view_timeline_rounded), text: 'Einheitsplan'),
                Tab(icon: Icon(Icons.auto_stories_outlined), text: 'Übungsbibliothek'),
                Tab(icon: Icon(Icons.fact_check_outlined), text: 'Anwesenheit'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: MediaQuery.sizeOf(context).height - 250,
              child: TabBarView(
                children: [
                  _planTab(),
                  _exerciseTab(),
                  _attendanceTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planTab() => ListView(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 390,
                child: TextField(
                  controller: _focus,
                  decoration: const InputDecoration(
                    labelText: 'Schwerpunkte',
                    hintText: 'Passspiel, Ballkontrolle, Umschalten',
                    prefixIcon: Icon(Icons.center_focus_strong_rounded),
                  ),
                ),
              ),
              SizedBox(
                width: 390,
                child: TextField(
                  controller: _coaches,
                  decoration: const InputDecoration(
                    labelText: 'Trainerteam',
                    prefixIcon: Icon(Icons.sports_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _goals,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Lernziele',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 390,
                child: TextField(
                  controller: _materials,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Material',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 390,
                child: TextField(
                  controller: _pitch,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Platzaufteilung / Aufbau',
                    prefixIcon: Icon(Icons.grid_on_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('Ablauf', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _addCustomItem,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Freier Baustein'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _exercises.isEmpty ? null : _addFromLibrary,
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Aus Bibliothek'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text('Noch keine Trainingsbausteine hinzugefügt.'),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _items.removeAt(oldIndex);
                  _items.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  key: ValueKey('$index-${item.title}'),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _phaseColor(item.phase).withValues(alpha: .12),
                      child: Text(
                        '${item.durationMinutes}',
                        style: TextStyle(
                          color: _phaseColor(item.phase),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(item.title),
                    subtitle: Text(_phaseLabel(item.phase)),
                    trailing: IconButton(
                      onPressed: () => setState(() => _items.removeAt(index)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _feedback,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Trainerfeedback nach der Einheit',
              prefixIcon: Icon(Icons.rate_review_outlined),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _savePlan,
              icon: const Icon(Icons.save_rounded),
              label: Text(
                _saving
                    ? 'Wird gespeichert …'
                    : 'Trainingsplan speichern',
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      );

  Widget _exerciseTab() => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_exercises.length} Übungen im Mannschaftsbereich',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _createExercise,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Neue Übung'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _exercises.isEmpty
                ? const EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: 'Übungsbibliothek ist leer',
                    message: 'Lege wiederverwendbare Übungen für dein Trainerteam an.',
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 430,
                      mainAxisExtent: 245,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = _exercises[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Chip(label: Text(exercise.category)),
                                  const Spacer(),
                                  if (exercise.isFavorite)
                                    const Icon(Icons.star_rounded, color: AppColors.orange),
                                ],
                              ),
                              Text(
                                exercise.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                exercise.instructions,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 18),
                                  Text(' ${exercise.durationMinutes} Min.'),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _appendExercise(exercise),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Einplanen'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );

  Widget _attendanceTab() => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_attendance.length} von ${_training!.roster.length} erfasst',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _saveAttendance,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Anwesenheit speichern'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final player in _training!.roster)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(player.shirtNumber?.toString() ?? 'FC'),
                      ),
                      title: Text(player.name),
                      trailing: DropdownButton<TrainingAttendanceStatus>(
                        value: _attendance[player.id],
                        hint: const Text('Status wählen'),
                        items: TrainingAttendanceStatus.values
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(_attendanceLabel(status)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _attendance[player.id] = value);
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  void _appendExercise(TrainingExerciseModel exercise) => setState(
        () => _items.add(
          TrainingPlanItemModel(
            title: exercise.title,
            phase: TrainingPhase.mainPart,
            durationMinutes: exercise.durationMinutes,
            exerciseId: exercise.id,
          ),
        ),
      );

  Future<void> _addFromLibrary() async {
    final exercise = await showModalBottomSheet<TrainingExerciseModel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final exercise in _exercises)
              ListTile(
                leading: const Icon(Icons.sports_soccer_rounded),
                title: Text(exercise.title),
                subtitle: Text('${exercise.category} · ${exercise.durationMinutes} Min.'),
                onTap: () => Navigator.pop(context, exercise),
              ),
          ],
        ),
      ),
    );
    if (exercise != null) _appendExercise(exercise);
  }

  Future<void> _addCustomItem() async {
    final title = TextEditingController();
    final duration = TextEditingController(text: '10');
    var phase = TrainingPhase.mainPart;
    final item = await showDialog<TrainingPlanItemModel>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Trainingsbaustein'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TrainingPhase>(
                  initialValue: phase,
                  decoration: const InputDecoration(labelText: 'Phase'),
                  items: TrainingPhase.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_phaseLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => phase = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dauer in Minuten'),
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
                if (title.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  TrainingPlanItemModel(
                    title: title.text.trim(),
                    phase: phase,
                    durationMinutes: int.tryParse(duration.text) ?? 10,
                  ),
                );
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    duration.dispose();
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _createExercise() async {
    final title = TextEditingController();
    final category = TextEditingController(text: 'Technik');
    final duration = TextEditingController(text: '15');
    final setup = TextEditingController();
    final instructions = TextEditingController();
    final materials = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neue Übung'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: category,
                        decoration: const InputDecoration(labelText: 'Kategorie'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: duration,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Dauer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: materials,
                  decoration: const InputDecoration(labelText: 'Material'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: setup,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Aufbau'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: instructions,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Ablauf'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty ||
                  setup.text.trim().isEmpty ||
                  instructions.text.trim().isEmpty) {
                return;
              }
              try {
                await ref.read(repositoryProvider).saveTrainingExercise(
                      teamId: _training!.teamId,
                      title: title.text.trim(),
                      category: category.text.trim(),
                      durationMinutes: int.tryParse(duration.text) ?? 15,
                      setup: setup.text.trim(),
                      instructions: instructions.text.trim(),
                      materials: materials.text.trim(),
                    );
                if (context.mounted) Navigator.pop(context, true);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Übung konnte nicht gespeichert werden.')),
                  );
                }
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    title.dispose();
    category.dispose();
    duration.dispose();
    setup.dispose();
    instructions.dispose();
    materials.dispose();
    if (saved == true) await _load();
  }

  Future<void> _savePlan() async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveTrainingPlan(
            trainingId: widget.trainingId,
            focusAreas: _focus.text
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(),
            durationMinutes: _items.fold(
              0,
              (sum, item) => sum + item.durationMinutes,
            ),
            items: _items,
            learningGoals: _goals.text,
            coaches: _coaches.text,
            materials: _materials.text,
            pitchSetup: _pitch.text,
            feedback: _feedback.text,
          );
      await _load();
      if (mounted) _message('Trainingsplan wurde gespeichert.');
    } catch (_) {
      if (mounted) _message('Trainingsplan konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAttendance() async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveTrainingAttendance(
            trainingId: widget.trainingId,
            entries: _attendance,
          );
      await _load();
      if (mounted) _message('Anwesenheit wurde gespeichert.');
    } catch (_) {
      if (mounted) _message('Anwesenheit konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
}

String _phaseLabel(TrainingPhase phase) => switch (phase) {
      TrainingPhase.warmUp => 'Aufwärmen',
      TrainingPhase.mainPart => 'Hauptteil',
      TrainingPhase.gameForm => 'Spielform',
      TrainingPhase.coolDown => 'Abschluss',
    };

Color _phaseColor(TrainingPhase phase) => switch (phase) {
      TrainingPhase.warmUp => AppColors.orange,
      TrainingPhase.mainPart => AppColors.blue,
      TrainingPhase.gameForm => AppColors.teal,
      TrainingPhase.coolDown => Colors.blueGrey,
    };

String _attendanceLabel(TrainingAttendanceStatus status) => switch (status) {
      TrainingAttendanceStatus.present => 'Anwesend',
      TrainingAttendanceStatus.excused => 'Entschuldigt',
      TrainingAttendanceStatus.unexcused => 'Unentschuldigt',
      TrainingAttendanceStatus.injured => 'Verletzt',
      TrainingAttendanceStatus.late => 'Verspätet',
      TrainingAttendanceStatus.leftEarly => 'Früher gegangen',
    };
