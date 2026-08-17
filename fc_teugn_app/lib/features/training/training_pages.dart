import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';
import '../../core/models/organization.dart';
import '../../core/models/pitch_occupancy.dart';
import '../../core/models/training.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../auth/auth_controller.dart';
import '../calendar/calendar_page.dart';
import '../shared/page_scaffold.dart';
import 'pitch_occupancy_board.dart';

enum _TrainingPageView { sessions, occupancy, indoorOccupancy }

class TrainingsPage extends ConsumerStatefulWidget {
  const TrainingsPage({super.key});

  @override
  ConsumerState<TrainingsPage> createState() => _TrainingsPageState();
}

class _TrainingsPageState extends ConsumerState<TrainingsPage> {
  List<TrainingModel>? _trainings;
  OrganizationContext? _organization;
  PitchOccupancyPlan? _occupancy;
  PitchOccupancyPlan? _indoorOccupancy;
  String? _trainingsError;
  String? _organizationError;
  String? _occupancyError;
  String? _indoorOccupancyError;
  bool _creating = false;
  _TrainingPageView _view = _TrainingPageView.sessions;

  bool get _canManageOccupancy => switch (ref.read(authProvider).user?.role) {
        UserRole.superAdmin ||
        UserRole.clubAdmin ||
        UserRole.youthDirector =>
          true,
        _ => false,
      };

  bool get _canManageTrainingSettings =>
      ref.read(authProvider).user?.isTrainer ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      ref.invalidate(trainingsProvider);
      ref.invalidate(organizationProvider);
      ref.invalidate(outdoorPitchOccupancyProvider);
      ref.invalidate(indoorPitchOccupancyProvider);
    }
    if (mounted) {
      setState(() {
        _trainings = null;
        _organization = null;
        _occupancy = null;
        _indoorOccupancy = null;
        _trainingsError = null;
        _organizationError = null;
        _occupancyError = null;
        _indoorOccupancyError = null;
      });
    }
    await Future.wait([
      _loadTrainings(),
      _loadOrganization(),
      _loadOccupancy(),
      _loadIndoorOccupancy(),
    ]);
  }

  Future<void> _loadTrainings() async {
    try {
      final trainings = await ref.read(trainingsProvider.future);
      if (mounted) {
        setState(() {
          _trainings = trainings;
          _trainingsError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _trainingsError = 'Trainings konnten nicht geladen werden.');
      }
    }
  }

  Future<void> _loadOrganization() async {
    try {
      final organization = await ref.read(organizationProvider.future);
      if (mounted) {
        setState(() {
          _organization = organization;
          _organizationError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _organizationError =
            'Mannschaftsdaten konnten nicht geladen werden.');
      }
    }
  }

  Future<void> _loadOccupancy() async {
    try {
      final occupancy = await ref.read(outdoorPitchOccupancyProvider.future);
      if (mounted) {
        setState(() {
          _occupancy = occupancy;
          _occupancyError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _occupancyError = 'Die Platzbelegung konnte nicht geladen werden.');
      }
    }
  }

  Future<void> _loadIndoorOccupancy() async {
    try {
      final occupancy = await ref.read(indoorPitchOccupancyProvider.future);
      if (mounted) {
        setState(() {
          _indoorOccupancy = occupancy;
          _indoorOccupancyError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _indoorOccupancyError =
            'Die Hallenbelegung konnte nicht geladen werden.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'Trainingsplanung',
        subtitle:
            'Einheiten vorbereiten, Übungen kombinieren und Anwesenheit erfassen.',
        action: _buildPageActions(),
        child: _buildContent(context),
      );

  Widget? _buildPageActions() {
    if (!_canManageOccupancy && _view == _TrainingPageView.occupancy) {
      return null;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final primary = switch (_view) {
          _TrainingPageView.sessions => FilledButton.icon(
              onPressed:
                  _organization == null || _creating ? null : _createTraining,
              icon: _creating
                  ? const LogoLoadingIndicator(
                      size: 22,
                      semanticsLabel: 'Training wird angelegt',
                    )
                  : const Icon(Icons.add_rounded),
              style: compact ? _compactFilledActionStyle() : null,
              label: _actionLabel(
                compact ? 'Training' : 'Trainingstermin anlegen',
              ),
            ),
          _TrainingPageView.indoorOccupancy when _canManageOccupancy =>
            FilledButton.icon(
              onPressed: _creating ? null : () => _editIndoorOccupancyEntry(),
              icon: const Icon(Icons.add_business_rounded),
              style: compact ? _compactFilledActionStyle() : null,
              label: _actionLabel(
                compact ? 'Fremdbelegung' : 'Fremdbelegung eintragen',
              ),
            ),
          _TrainingPageView.indoorOccupancy => FilledButton.icon(
              onPressed:
                  _organization == null || _creating ? null : _createTraining,
              icon: const Icon(Icons.add_rounded),
              style: compact ? _compactFilledActionStyle() : null,
              label: _actionLabel(
                compact ? 'Training' : 'Trainingstermin anlegen',
              ),
            ),
          _TrainingPageView.occupancy => null,
        };
        final manage = _canManageTrainingSettings
            ? OutlinedButton.icon(
                onPressed: _creating ? null : _manageTrainingTimes,
                icon: const Icon(Icons.edit_calendar_rounded),
                style: compact ? _compactOutlinedActionStyle() : null,
                label: _actionLabel(
                  compact ? 'Zeiten' : 'Trainingszeiten verwalten',
                ),
              )
            : null;
        if (!compact) {
          return Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (manage != null) manage,
              if (primary != null) primary
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (manage != null) Expanded(child: manage),
            if (manage != null && primary != null) const SizedBox(width: 8),
            if (primary != null) Expanded(flex: 2, child: primary),
          ],
        );
      },
    );
  }

  Widget _actionLabel(String text) => AdaptiveButtonLabel(text);

  ButtonStyle _compactFilledActionStyle() => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        tapTargetSize: MaterialTapTargetSize.padded,
      );

  ButtonStyle _compactOutlinedActionStyle() => OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        tapTargetSize: MaterialTapTargetSize.padded,
      );

  Widget _buildContent(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              return SizedBox(
                width: compact ? double.infinity : null,
                child: SegmentedButton<_TrainingPageView>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: compact
                        ? const VisualDensity(horizontal: -3, vertical: -2)
                        : VisualDensity.standard,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(
                        horizontal: compact ? 7 : 13,
                        vertical: compact ? 8 : 10,
                      ),
                    ),
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(
                        fontSize: compact ? 11 : 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: _TrainingPageView.sessions,
                      icon: const Icon(Icons.fitness_center_rounded, size: 17),
                      label: Text(compact ? 'Training' : 'Meine Trainings'),
                    ),
                    ButtonSegment(
                      value: _TrainingPageView.occupancy,
                      icon: const Icon(Icons.stadium_rounded, size: 17),
                      label: Text(compact ? 'Plätze' : 'Platzbelegung'),
                    ),
                    ButtonSegment(
                      value: _TrainingPageView.indoorOccupancy,
                      icon: const Icon(Icons.sports_handball_rounded, size: 17),
                      label: Text(compact ? 'Halle' : 'Hallenbelegung'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (selection) =>
                      setState(() => _view = selection.first),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSelectedView(context),
        ],
      );

  Widget _buildSelectedView(BuildContext context) {
    switch (_view) {
      case _TrainingPageView.sessions:
        if (_trainingsError != null) {
          return _resourceFailure(
            icon: Icons.fitness_center_rounded,
            title: 'Trainingstermine nicht erreichbar',
            message: _trainingsError!,
            onRetry: () async {
              ref.invalidate(trainingsProvider);
              await _loadTrainings();
            },
          );
        }
        if (_trainings == null) {
          return const Center(
            child: LogoLoadingPanel(message: 'Trainingsdaten werden geladen …'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_organizationError != null) ...[
              _contextWarning(),
              const SizedBox(height: 12),
            ],
            _buildList(context),
          ],
        );
      case _TrainingPageView.occupancy:
        if (_occupancyError != null) {
          return _resourceFailure(
            icon: Icons.stadium_rounded,
            title: 'Platzbelegung nicht erreichbar',
            message: _occupancyError!,
            onRetry: () async {
              ref.invalidate(outdoorPitchOccupancyProvider);
              await _loadOccupancy();
            },
          );
        }
        if (_occupancy == null) {
          return const Center(
            child: LogoLoadingPanel(message: 'Platzbelegung wird geladen …'),
          );
        }
        return PitchOccupancyBoard(
          plan: _occupancy!,
          onConflictApproval: _setConflictApproval,
        );
      case _TrainingPageView.indoorOccupancy:
        if (_indoorOccupancyError != null) {
          return _resourceFailure(
            icon: Icons.sports_handball_rounded,
            title: 'Hallenbelegung nicht erreichbar',
            message: _indoorOccupancyError!,
            onRetry: () async {
              ref.invalidate(indoorPitchOccupancyProvider);
              await _loadIndoorOccupancy();
            },
          );
        }
        if (_indoorOccupancy == null) {
          return const Center(
            child: LogoLoadingPanel(message: 'Hallenbelegung wird geladen …'),
          );
        }
        return PitchOccupancyBoard(
          plan: _indoorOccupancy!,
          onConflictApproval: _setConflictApproval,
          onEditSpecialEntry: _editIndoorOccupancyEntry,
          onDeleteSpecialEntry: _deleteIndoorOccupancyEntry,
        );
    }
  }

  Widget _resourceFailure({
    required IconData icon,
    required String title,
    required String message,
    required Future<void> Function() onRetry,
  }) =>
      EmptyState(
        icon: icon,
        title: title,
        message: '$message Bitte versuche es erneut.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Erneut laden'),
        ),
      );

  Widget _contextWarning() => Material(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Die Termine sind verfügbar. Mannschaftsdaten und Bearbeitungsfunktionen werden noch neu geladen.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Mannschaftsdaten neu laden',
                onPressed: _loadOrganization,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      );

  Widget _buildList(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final upcoming = _trainings!
        .where((item) => item.startAt
            .isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .toList();
    if (upcoming.isEmpty) {
      return Column(
        children: [
          if (_organization != null) ...[
            _RegularTrainingTimes(team: _organization!.currentTeam),
            const SizedBox(height: 16),
          ],
          EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Noch keine planbaren Trainingstermine',
            message:
                'Reguläre Trainingszeiten beschreiben den Wochenrhythmus. Lege daraus jetzt einen einzelnen Termin oder direkt eine Terminserie an.',
            action: FilledButton.icon(
              onPressed:
                  _organization == null || _creating ? null : _createTraining,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Training oder Serie anlegen'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_organization != null) ...[
          _RegularTrainingTimes(team: _organization!.currentTeam),
          SizedBox(height: compact ? 13 : 18),
        ],
        Row(
          children: [
            Text(
              'Kommende Einheiten',
              style: compact
                  ? Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)
                  : Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            Text(
              '${upcoming.length} Termine',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final training in upcoming)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 7 : 12),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.push('/trainer/training/${training.id}'),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 9 : 18),
                  child: Row(
                    children: [
                      _DateTile(date: training.startAt.toLocal()),
                      SizedBox(width: compact ? 8 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              training.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: compact
                                  ? Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900)
                                  : Theme.of(context).textTheme.titleLarge,
                            ),
                            SizedBox(height: compact ? 2 : 4),
                            Text(
                              [
                                if (training.teamNames.isNotEmpty)
                                  training.teamNames.join(' · '),
                                if (training.location.trim().isNotEmpty)
                                  training.location,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            SizedBox(height: compact ? 3 : 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                Chip(
                                  visualDensity: compact
                                      ? const VisualDensity(
                                          horizontal: -3,
                                          vertical: -3,
                                        )
                                      : VisualDensity.standard,
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
                                if (!compact &&
                                    training.plan?.coaches.isNotEmpty == true)
                                  Chip(
                                    avatar: const Icon(
                                      Icons.groups_2_outlined,
                                      size: 17,
                                    ),
                                    label: Text(
                                      training.plan!.coaches
                                          .map((coach) => coach.name)
                                          .join(', '),
                                    ),
                                  ),
                                if (!compact &&
                                    training.plan?.focusAreas.isNotEmpty ==
                                        true)
                                  for (final focus
                                      in training.plan!.focusAreas.take(3))
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

  Future<void> _createTraining() async {
    final organization = _organization;
    if (organization == null) return;
    final draft = await showDialog<EventWriteData>(
      context: context,
      builder: (context) => EventEditorDialog(
        repository: ref.read(repositoryProvider),
        teams: organization.teams,
        initialTeamId: organization.currentTeam.id,
        seasonName: organization.season.name,
        seasonEnd: organization.currentTeam.seasonEndDate ??
            organization.season.endDate,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _creating = true);
    try {
      await ref.read(repositoryProvider).createEvent(draft);
      ref.invalidate(eventsProvider);
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Trainingstermin wurde angelegt und kann jetzt geplant werden.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Der Trainingstermin konnte nicht angelegt werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _manageTrainingTimes() async {
    final organization = _organization;
    if (organization == null || !_canManageTrainingSettings) {
      return;
    }
    final draft = await showDialog<_TrainingScheduleDraft>(
      context: context,
      builder: (context) => _TrainingScheduleDialog(
        teams: organization.teams.where((team) => team.isActive).toList(),
        initialTeamId: organization.currentTeam.id,
        season: organization.season,
        allowRecreational:
            ref.read(authProvider).user?.role == UserRole.superAdmin,
        allowSeniors: _canManageOccupancy,
        recreationalSchedule: _occupancy?.recreationalSchedule,
        seniorSchedule: _occupancy?.seniorSchedule,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final repository = ref.read(repositoryProvider);
      if (draft.isRecreational) {
        await repository.updateRecreationalPitchOccupancy(
          seasonId: organization.season.id,
          trainingTimes: draft.trainingTimes,
          trainingLocation: draft.trainingLocation,
        );
      } else if (draft.isSenior) {
        await repository.updateSeniorPitchOccupancy(
          seasonId: organization.season.id,
          trainingTimes: draft.trainingTimes,
          matchdayTimes: draft.matchdayTimes,
          trainingLocation: draft.trainingLocation,
        );
      } else {
        await repository.updateTrainingSchedule(
          teamId: draft.teamId,
          trainingTimes: draft.trainingTimes,
          trainingPartnerIds: draft.trainingPartnerIds,
          matchdayTimes: draft.matchdayTimes,
          trainingLocation: draft.trainingLocation,
          defaultReminderMinutes: draft.defaultReminderMinutes,
          secondaryReminderMinutes: draft.secondaryReminderMinutes,
          defaultReminderPushEnabled: draft.defaultReminderPushEnabled,
        );
        ref.invalidate(eventsProvider);
        ref.invalidate(personalResponsesProvider);
      }
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trainingszeiten wurden gespeichert.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trainingszeiten konnten nicht gespeichert werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _setConflictApproval(
    PitchOccupancyConflict conflict,
    bool approved,
  ) async {
    final plan = _view == _TrainingPageView.indoorOccupancy
        ? _indoorOccupancy
        : _occupancy;
    if (plan == null || !_canManageOccupancy) return;
    try {
      await ref.read(repositoryProvider).setPitchOccupancyConflictApproval(
            seasonId: plan.seasonId,
            conflictKey: conflict.key,
            approved: approved,
          );
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Konfliktbewertung wurde gespeichert.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Bestätigung konnte nicht gespeichert werden.'),
          ),
        );
      }
    }
  }

  Future<void> _editIndoorOccupancyEntry([
    IndoorOccupancyEntry? existing,
  ]) async {
    final plan = _indoorOccupancy;
    if (plan == null || !_canManageOccupancy) return;
    final draft = await showDialog<_IndoorOccupancyDraft>(
      context: context,
      builder: (context) => _IndoorOccupancyDialog(
        existing: existing,
        defaultSeriesEnd: _organization?.season.endDate,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final repository = ref.read(repositoryProvider);
      if (existing == null) {
        await repository.createIndoorOccupancyEntry(
          seasonId: plan.seasonId,
          title: draft.title,
          startAt: draft.startAt,
          endAt: draft.endAt,
          isRecurring: draft.isRecurring,
          recurrenceWeekdays: draft.recurrenceWeekdays,
          recurrenceIntervalWeeks: draft.recurrenceIntervalWeeks,
          recurrenceUntil: draft.recurrenceUntil,
          notes: draft.notes,
        );
      } else {
        await repository.updateIndoorOccupancyEntry(
          entryId: existing.id,
          title: draft.title,
          startAt: draft.startAt,
          endAt: draft.endAt,
          isRecurring: draft.isRecurring,
          recurrenceWeekdays: draft.recurrenceWeekdays,
          recurrenceIntervalWeeks: draft.recurrenceIntervalWeeks,
          recurrenceUntil: draft.recurrenceUntil,
          notes: draft.notes,
        );
      }
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null
                  ? 'Die Hallen-Sonderbelegung wurde eingetragen.'
                  : 'Die Hallen-Sonderbelegung wurde aktualisiert.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die Hallen-Sonderbelegung konnte nicht gespeichert werden.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteIndoorOccupancyEntry(
    IndoorOccupancyEntry entry,
  ) async {
    if (!_canManageOccupancy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sonderbelegung löschen?'),
        content: Text(
          '„${entry.title}“ wird dauerhaft aus der Hallenbelegung entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _creating = true);
    try {
      await ref.read(repositoryProvider).deleteIndoorOccupancyEntry(entry.id);
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sonderbelegung wurde gelöscht.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sonderbelegung konnte nicht gelöscht werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

class _IndoorOccupancyDraft {
  const _IndoorOccupancyDraft({
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.isRecurring,
    required this.recurrenceWeekdays,
    required this.recurrenceIntervalWeeks,
    this.recurrenceUntil,
    this.notes,
  });

  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final bool isRecurring;
  final List<int> recurrenceWeekdays;
  final int recurrenceIntervalWeeks;
  final DateTime? recurrenceUntil;
  final String? notes;
}

class _IndoorOccupancyDialog extends StatefulWidget {
  const _IndoorOccupancyDialog({
    this.existing,
    this.defaultSeriesEnd,
  });

  final IndoorOccupancyEntry? existing;
  final DateTime? defaultSeriesEnd;

  @override
  State<_IndoorOccupancyDialog> createState() => _IndoorOccupancyDialogState();
}

class _IndoorOccupancyDialogState extends State<_IndoorOccupancyDialog> {
  static const _weekdayLabels = [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _startAt;
  late DateTime _endAt;
  late bool _isRecurring;
  late Set<int> _recurrenceWeekdays;
  late int _recurrenceIntervalWeeks;
  late DateTime _recurrenceUntil;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initialStart = widget.existing?.startAt ??
        DateTime(now.year, now.month, now.day + 1, 18);
    _startAt = initialStart;
    _endAt =
        widget.existing?.endAt ?? initialStart.add(const Duration(hours: 2));
    _isRecurring = widget.existing?.isRecurring ?? true;
    _recurrenceWeekdays = {
      ...(widget.existing?.recurrenceWeekdays ?? const <int>[]),
    };
    if (_isRecurring && _recurrenceWeekdays.isEmpty) {
      _recurrenceWeekdays.add(_startAt.weekday);
    }
    _recurrenceIntervalWeeks = widget.existing?.recurrenceIntervalWeeks ?? 1;
    _recurrenceUntil = widget.existing?.recurrenceUntil ??
        widget.defaultSeriesEnd ??
        DateTime(_startAt.year + 1, 6, 30);
    _title = TextEditingController(text: widget.existing?.title);
    _notes = TextEditingController(text: widget.existing?.notes);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')} Uhr';

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1100)),
    );
    if (selected == null) return;
    final duration = _endAt.difference(_startAt);
    setState(() {
      _startAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _startAt.hour,
        _startAt.minute,
      );
      _endAt = _startAt.add(duration);
    });
  }

  Future<void> _pickSeriesEnd() async {
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _recurrenceUntil.isBefore(_startAt) ? _startAt : _recurrenceUntil,
      firstDate: DateTime(
        _startAt.year,
        _startAt.month,
        _startAt.day,
      ),
      lastDate: DateTime.now().add(const Duration(days: 1500)),
    );
    if (selected != null) {
      setState(() => _recurrenceUntil = selected);
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final value = start ? _startAt : _endAt;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null) return;
    setState(() {
      final next = DateTime(
        _startAt.year,
        _startAt.month,
        _startAt.day,
        selected.hour,
        selected.minute,
      );
      if (start) {
        final duration = _endAt.difference(_startAt);
        _startAt = next;
        _endAt = _startAt.add(
          duration.isNegative || duration == Duration.zero
              ? const Duration(hours: 2)
              : duration,
        );
      } else {
        _endAt = next;
      }
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Bitte eine Bezeichnung angeben.');
      return;
    }
    if (!_endAt.isAfter(_startAt)) {
      setState(() => _error = 'Das Ende muss nach dem Beginn liegen.');
      return;
    }
    if (_isRecurring &&
        (_recurrenceWeekdays.isEmpty ||
            _recurrenceUntil.isBefore(DateTime(
              _startAt.year,
              _startAt.month,
              _startAt.day,
            )))) {
      setState(
        () => _error =
            'Bitte mindestens einen Wochentag und ein gültiges Serienende wählen.',
      );
      return;
    }
    Navigator.pop(
      context,
      _IndoorOccupancyDraft(
        title: title,
        startAt: _startAt,
        endAt: _endAt,
        isRecurring: _isRecurring,
        recurrenceWeekdays: _recurrenceWeekdays.toList()..sort(),
        recurrenceIntervalWeeks: _recurrenceIntervalWeeks,
        recurrenceUntil: _isRecurring
            ? DateTime(
                _recurrenceUntil.year,
                _recurrenceUntil.month,
                _recurrenceUntil.day,
                23,
                59,
                59,
              )
            : null,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.existing == null
              ? 'Hallen-Sonderbelegung'
              : 'Sonderbelegung bearbeiten',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Für regelmäßige oder einmalige Nutzungen der Sporthalle '
                  'durch Tennis, Faschingsverein oder andere Gruppen.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Bezeichnung',
                    hintText: 'z. B. Tennis oder Faschingsverein',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                const InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Ort',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  child: Text(
                    'Sporthalle',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text('Datum · ${_date(_startAt)}'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(start: true),
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text('Beginn · ${_time(_startAt)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(start: false),
                        icon: const Icon(Icons.schedule_outlined),
                        label: Text('Ende · ${_time(_endAt)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Als Serientermin eintragen',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Für regelmäßig wiederkehrende Hallenbelegungen.',
                  ),
                  value: _isRecurring,
                  onChanged: (value) => setState(() {
                    _isRecurring = value;
                    if (value && _recurrenceWeekdays.isEmpty) {
                      _recurrenceWeekdays.add(_startAt.weekday);
                    }
                  }),
                ),
                if (_isRecurring) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Wochentage',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (var weekday = 1; weekday <= 7; weekday++)
                        FilterChip(
                          label: Text(_weekdayLabels[weekday - 1]),
                          selected: _recurrenceWeekdays.contains(weekday),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _recurrenceWeekdays.add(weekday);
                            } else {
                              _recurrenceWeekdays.remove(weekday);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _recurrenceIntervalWeeks,
                    decoration: const InputDecoration(
                      labelText: 'Wiederholung',
                      prefixIcon: Icon(Icons.repeat_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 1,
                        child: Text('Jede Woche'),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text('Alle zwei Wochen'),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text('Alle drei Wochen'),
                      ),
                      DropdownMenuItem(
                        value: 4,
                        child: Text('Alle vier Wochen'),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _recurrenceIntervalWeeks = value ?? 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickSeriesEnd,
                    icon: const Icon(Icons.event_available_rounded),
                    label: Text(
                      'Serienende · ${_date(_recurrenceUntil)}',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notiz (optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
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
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Speichern'),
          ),
        ],
      );
}

class _TrainingScheduleDraft {
  const _TrainingScheduleDraft({
    required this.teamId,
    required this.trainingTimes,
    required this.trainingPartnerIds,
    required this.matchdayTimes,
    this.isRecreational = false,
    this.isSenior = false,
    this.trainingLocation,
    this.defaultReminderMinutes,
    this.secondaryReminderMinutes,
    this.defaultReminderPushEnabled = true,
  });

  final String teamId;
  final List<String> trainingTimes;
  final List<String> trainingPartnerIds;
  final List<String> matchdayTimes;
  final bool isRecreational;
  final bool isSenior;
  final String? trainingLocation;
  final int? defaultReminderMinutes;
  final int? secondaryReminderMinutes;
  final bool defaultReminderPushEnabled;
}

class _TrainingScheduleDialog extends StatefulWidget {
  const _TrainingScheduleDialog({
    required this.teams,
    required this.initialTeamId,
    required this.season,
    required this.allowRecreational,
    required this.allowSeniors,
    this.recreationalSchedule,
    this.seniorSchedule,
  });

  final List<TeamSummary> teams;
  final String initialTeamId;
  final SeasonSummary season;
  final bool allowRecreational;
  final bool allowSeniors;
  final PitchOccupancyTeam? recreationalSchedule;
  final PitchOccupancyTeam? seniorSchedule;

  @override
  State<_TrainingScheduleDialog> createState() =>
      _TrainingScheduleDialogState();
}

class _TrainingScheduleDialogState extends State<_TrainingScheduleDialog> {
  static const _recreationalId = 'recreational';
  static const _seniorId = 'seniors';
  static const _openLocation = 'Platz noch offen / unklar';
  static const _trainingLocations = [
    'Platz 1 unten',
    'Platz 2 oben',
    'Sportplatz Teugn · beide Plätze',
    'Sportplatz Hausen',
    'Sporthalle',
    _openLocation,
  ];

  late String _teamId;
  String? _location;
  List<_TrainingTimeSelection> _times = [];
  List<_TrainingTimeSelection> _matchdayTimes = [];
  Set<String> _trainingPartnerIds = {};
  List<String> _legacyTimes = [];
  List<String> _legacyMatchdayTimes = [];
  String? _validationMessage;
  String _reminderMode = '60';
  String _secondaryReminderMode = '1440';
  bool _reminderPushEnabled = true;
  late final TextEditingController _customReminderMinutes;
  late final TextEditingController _customSecondaryReminderMinutes;

  bool get _isRecreational => _teamId == _recreationalId;
  bool get _isSenior => _teamId == _seniorId;

  TeamSummary get _team =>
      widget.teams.firstWhere((team) => team.id == _teamId);

  List<String> get _availableLocations {
    final values = [..._trainingLocations];
    final savedLocations = [
      _location,
      ..._times.map((time) => time.location),
      ..._matchdayTimes.map((time) => time.location),
    ];
    for (final savedLocation in savedLocations) {
      final location = savedLocation?.trim();
      if (location != null &&
          location.isNotEmpty &&
          !values.contains(location)) {
        values.add(location);
      }
    }
    return values;
  }

  @override
  void initState() {
    super.initState();
    _customReminderMinutes = TextEditingController();
    _customSecondaryReminderMinutes = TextEditingController();
    _teamId = widget.teams.any((team) => team.id == widget.initialTeamId)
        ? widget.initialTeamId
        : widget.teams.first.id;
    _loadTeam();
  }

  @override
  void dispose() {
    _customReminderMinutes.dispose();
    _customSecondaryReminderMinutes.dispose();
    super.dispose();
  }

  void _loadTeam() {
    final specialSchedule = _isRecreational
        ? widget.recreationalSchedule
        : _isSenior
            ? widget.seniorSchedule
            : null;
    final location = specialSchedule != null
        ? specialSchedule.location == 'Platz offen'
            ? null
            : specialSchedule.location
        : _team.trainingLocation;
    final trainingTimes = specialSchedule?.trainingTimes ?? _team.trainingTimes;
    final matchdayTimes = specialSchedule?.matchdayTimes ?? _team.matchdayTimes;
    _location = location?.trim();
    if (_location?.isEmpty == true) _location = null;
    _times = [];
    _matchdayTimes = [];
    _trainingPartnerIds =
        specialSchedule == null ? _team.trainingPartnerIds.toSet() : {};
    _legacyTimes = [];
    _legacyMatchdayTimes = [];
    if (!_isRecreational && !_isSenior) {
      final reminder = _team.defaultReminderMinutes;
      final secondaryReminder = _team.secondaryReminderMinutes;
      _reminderPushEnabled = _team.defaultReminderPushEnabled;
      if (reminder == null) {
        _reminderMode = 'none';
        _customReminderMinutes.clear();
      } else if (const {30, 60, 120}.contains(reminder)) {
        _reminderMode = '$reminder';
        _customReminderMinutes.clear();
      } else {
        _reminderMode = 'custom';
        _customReminderMinutes.text = '$reminder';
      }
      if (secondaryReminder == null) {
        _secondaryReminderMode = 'none';
        _customSecondaryReminderMinutes.clear();
      } else if (const {30, 60, 120, 360, 720, 1440, 2880}
          .contains(secondaryReminder)) {
        _secondaryReminderMode = '$secondaryReminder';
        _customSecondaryReminderMinutes.clear();
      } else {
        _secondaryReminderMode = 'custom';
        _customSecondaryReminderMinutes.text = '$secondaryReminder';
      }
    }
    for (final value in trainingTimes) {
      final parsed = _TrainingTimeSelection.tryParse(
        value,
        defaultLocation: _location ?? _openLocation,
      );
      if (parsed == null) {
        _legacyTimes.add(value);
      } else {
        _times.add(parsed);
      }
    }
    for (final value in matchdayTimes) {
      final parsed = _TrainingTimeSelection.tryParse(
        value,
        defaultLocation: _openLocation,
      );
      if (parsed == null) {
        _legacyMatchdayTimes.add(value);
      } else {
        _matchdayTimes.add(parsed);
      }
    }
    _validationMessage = null;
  }

  Widget _reminderPicker({
    required String label,
    required String mode,
    required ValueChanged<String> onChanged,
    required TextEditingController customController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('training_reminder_$_teamId-$label-$mode'),
          initialValue: mode,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.notifications_active_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Deaktiviert')),
            DropdownMenuItem(value: '30', child: Text('30 Minuten vorher')),
            DropdownMenuItem(value: '60', child: Text('1 Stunde vorher')),
            DropdownMenuItem(value: '120', child: Text('2 Stunden vorher')),
            DropdownMenuItem(value: '360', child: Text('6 Stunden vorher')),
            DropdownMenuItem(value: '720', child: Text('12 Stunden vorher')),
            DropdownMenuItem(value: '1440', child: Text('24 Stunden vorher')),
            DropdownMenuItem(value: '2880', child: Text('48 Stunden vorher')),
            DropdownMenuItem(value: 'custom', child: Text('Benutzerdefiniert')),
          ],
          onChanged: (value) => onChanged(value ?? 'none'),
        ),
        if (mode == 'custom') ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: customController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minuten vor Trainingsbeginn',
              helperText: '1 bis 10.080 Minuten (7 Tage)',
            ),
            onChanged: (_) => setState(() => _validationMessage = null),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Trainingszeiten verwalten'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _teamId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mannschaft / Gruppe',
                    prefixIcon: Icon(Icons.groups_rounded),
                  ),
                  items: [
                    for (final team in widget.teams)
                      DropdownMenuItem(
                        value: team.id,
                        child: Text(team.displayName),
                      ),
                    if (widget.allowSeniors)
                      const DropdownMenuItem(
                        value: _seniorId,
                        child: Text('Herren · Vereinsbelegung'),
                      ),
                    if (widget.allowRecreational)
                      const DropdownMenuItem(
                        value: _recreationalId,
                        child: Text(
                          'Freizeitkicker · nur Systemadministration',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _teamId = value;
                      _loadTeam();
                    });
                  },
                ),
                if (_isRecreational) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.yellowDark.withValues(alpha: .35),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.admin_panel_settings_outlined, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dieser Platz-Slot gehört keiner Jugendmannschaft. '
                            'Er kann ausschließlich durch die '
                            'Systemadministration geändert werden.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isSenior) ...[
                  const SizedBox(height: 12),
                  const _ScheduleHint(
                    icon: Icons.shield_outlined,
                    message:
                        'Die Herren werden im gemeinsamen Belegungsplan berücksichtigt. Die Pflege ist der Systemadministration, Vereinsleitung und Jugendleitung vorbehalten.',
                  ),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey('training_location_${_teamId}_$_location'),
                  initialValue: _location,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Standardplatz für neue Trainingszeiten',
                    hintText: 'Standardplatz auswählen',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  items: [
                    for (final location in _availableLocations)
                      DropdownMenuItem(
                        value: location,
                        child: Text(location),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _location = value;
                    _validationMessage = null;
                  }),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Regelmäßige Trainingszeiten',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _times.length + _legacyTimes.length >= 14
                          ? null
                          : () => setState(() {
                                _times.add(
                                  const _TrainingTimeSelection(
                                    weekday: 1,
                                    start: TimeOfDay(hour: 17, minute: 0),
                                    end: TimeOfDay(hour: 18, minute: 30),
                                    location: _openLocation,
                                  ),
                                );
                                _validationMessage = null;
                              }),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Zeit hinzufügen'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_times.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Text(
                      'Noch keine regelmäßige Trainingszeit ausgewählt.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (var index = 0; index < _times.length; index++) ...[
                    _TrainingTimeRow(
                      key: ValueKey(
                        '${_teamId}_${index}_${_times[index].weekday}',
                      ),
                      value: _times[index],
                      locations: _availableLocations,
                      fallbackLocation: _location,
                      showLocation: true,
                      onChanged: (value) => setState(() {
                        _times[index] = value;
                        _validationMessage = null;
                      }),
                      onDelete: () => setState(() {
                        _times.removeAt(index);
                        _validationMessage = null;
                      }),
                    ),
                    if (index < _times.length - 1) const SizedBox(height: 8),
                  ],
                if (_legacyTimes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_legacyTimes.length} ältere Zeitangabe(n) werden '
                    'unverändert beibehalten.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!_isRecreational && !_isSenior) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.yellowDark.withValues(alpha: .25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Automatische Trainingserinnerungen',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Wird serverseitig vor jedem regulären Training an '
                          'die berechtigten Spieler und Eltern gesendet.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        _reminderPicker(
                          label: '1. Erinnerung (Standard: 24 Stunden)',
                          mode: _secondaryReminderMode,
                          customController: _customSecondaryReminderMinutes,
                          onChanged: (value) => setState(() {
                            _secondaryReminderMode = value;
                            _validationMessage = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        _reminderPicker(
                          label: '2. Erinnerung (Standard: 1 Stunde)',
                          mode: _reminderMode,
                          customController: _customReminderMinutes,
                          onChanged: (value) => setState(() {
                            _reminderMode = value;
                            _validationMessage = null;
                          }),
                        ),
                        if (_reminderMode != 'none' ||
                            _secondaryReminderMode != 'none')
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _reminderPushEnabled,
                            onChanged: (value) => setState(
                              () => _reminderPushEnabled = value,
                            ),
                            title: const Text(
                                'Zusätzlich als Pushnachricht senden'),
                            subtitle: const Text(
                                'In-App bleibt die Erinnerung aktiv.'),
                          ),
                      ],
                    ),
                  ),
                ],
                if (!_isRecreational && !_isSenior) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Gemeinsames Training',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Wähle Mannschaften, die diese Zeiten gemeinsam nutzen. Identische Belegungen gelten dann nicht als Konflikt.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final team in widget.teams)
                        if (team.id != _teamId)
                          FilterChip(
                            label: Text(team.displayName),
                            selected: _trainingPartnerIds.contains(team.id),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _trainingPartnerIds.add(team.id);
                              } else {
                                _trainingPartnerIds.remove(team.id);
                              }
                            }),
                          ),
                    ],
                  ),
                ],
                if (!_isRecreational) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mögliche Spieltage',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Nur informativ – Spieltage lösen keine Belegungskonflikte aus.',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _matchdayTimes.length +
                                    _legacyMatchdayTimes.length >=
                                14
                            ? null
                            : () => setState(() {
                                  _matchdayTimes.add(
                                    const _TrainingTimeSelection(
                                      weekday: 6,
                                      start: TimeOfDay(
                                        hour: 10,
                                        minute: 0,
                                      ),
                                      end: TimeOfDay(
                                        hour: 12,
                                        minute: 0,
                                      ),
                                      location: _openLocation,
                                    ),
                                  );
                                }),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Spieltag'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_matchdayTimes.isEmpty)
                    const _EmptyScheduleRow(
                      text: 'Noch kein möglicher Spieltag eingetragen.',
                    )
                  else
                    for (var index = 0;
                        index < _matchdayTimes.length;
                        index++) ...[
                      _TrainingTimeRow(
                        key: ValueKey(
                          'matchday_${_teamId}_${index}_${_matchdayTimes[index].weekday}',
                        ),
                        value: _matchdayTimes[index],
                        locations: _availableLocations,
                        fallbackLocation: _openLocation,
                        showLocation: true,
                        onChanged: (value) => setState(() {
                          _matchdayTimes[index] = value;
                          _validationMessage = null;
                        }),
                        onDelete: () => setState(() {
                          _matchdayTimes.removeAt(index);
                          _validationMessage = null;
                        }),
                      ),
                      if (index < _matchdayTimes.length - 1)
                        const SizedBox(height: 8),
                    ],
                ],
                if (_validationMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _validationMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Die Angaben gelten für die Saison ${widget.season.name}. '
                    'Kalender-Trainingsserien laufen automatisch bis zum '
                    'Saisonende am ${_date(widget.season.endDate)}.',
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
              final invalidTime = [..._times, ..._matchdayTimes].any(
                (value) => value.endMinutes <= value.startMinutes,
              );
              if (invalidTime) {
                setState(() {
                  _validationMessage =
                      'Die Endzeit muss nach der Startzeit liegen.';
                });
                return;
              }
              if ([..._times, ..._matchdayTimes].any(
                (value) => (value.location ?? _openLocation).trim().isEmpty,
              )) {
                setState(() {
                  _validationMessage =
                      'Bitte wähle für jeden Termin einen Platz aus.';
                });
                return;
              }
              final customReminder =
                  int.tryParse(_customReminderMinutes.text.trim());
              final customSecondaryReminder = int.tryParse(
                _customSecondaryReminderMinutes.text.trim(),
              );
              if (!_isRecreational &&
                  !_isSenior &&
                  _reminderMode == 'custom' &&
                  (customReminder == null ||
                      customReminder < 1 ||
                      customReminder > 10080)) {
                setState(() {
                  _validationMessage =
                      'Bitte 1 bis 10.080 Minuten für die Erinnerung eingeben.';
                });
                return;
              }
              if (!_isRecreational &&
                  !_isSenior &&
                  _secondaryReminderMode == 'custom' &&
                  (customSecondaryReminder == null ||
                      customSecondaryReminder < 1 ||
                      customSecondaryReminder > 10080)) {
                setState(() {
                  _validationMessage =
                      'Bitte 1 bis 10.080 Minuten für die erste Erinnerung eingeben.';
                });
                return;
              }
              final times = [
                ..._times.map(
                  (value) => value
                      .copyWith(location: value.location ?? _location)
                      .storageValue,
                ),
                ..._legacyTimes,
              ].take(14).toList();
              final matchdayTimes = [
                ..._matchdayTimes.map(
                  (value) => value
                      .copyWith(location: value.location ?? _openLocation)
                      .storageValue,
                ),
                ..._legacyMatchdayTimes,
              ].take(14).toList();
              Navigator.pop(
                context,
                _TrainingScheduleDraft(
                  teamId: _teamId,
                  trainingTimes: times,
                  trainingPartnerIds: _trainingPartnerIds.toList(),
                  matchdayTimes: matchdayTimes,
                  isRecreational: _isRecreational,
                  isSenior: _isSenior,
                  trainingLocation: _location,
                  defaultReminderMinutes: _isRecreational || _isSenior
                      ? null
                      : _reminderMode == 'none'
                          ? null
                          : _reminderMode == 'custom'
                              ? customReminder
                              : int.parse(_reminderMode),
                  secondaryReminderMinutes: _isRecreational || _isSenior
                      ? null
                      : _secondaryReminderMode == 'none'
                          ? null
                          : _secondaryReminderMode == 'custom'
                              ? customSecondaryReminder
                              : int.parse(_secondaryReminderMode),
                  defaultReminderPushEnabled: _reminderPushEnabled,
                ),
              );
            },
            child: const Text('Speichern'),
          ),
        ],
      );

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _TrainingTimeRow extends StatelessWidget {
  const _TrainingTimeRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onDelete,
    this.locations = const [],
    this.fallbackLocation,
    this.showLocation = false,
  });

  final _TrainingTimeSelection value;
  final ValueChanged<_TrainingTimeSelection> onChanged;
  final VoidCallback onDelete;
  final List<String> locations;
  final String? fallbackLocation;
  final bool showLocation;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final day = DropdownButtonFormField<int>(
              initialValue: value.weekday,
              decoration: const InputDecoration(
                labelText: 'Wochentag',
                isDense: true,
              ),
              items: [
                for (var index = 0;
                    index < _TrainingTimeSelection.weekdays.length;
                    index++)
                  DropdownMenuItem(
                    value: index + 1,
                    child: Text(_TrainingTimeSelection.weekdays[index]),
                  ),
              ],
              onChanged: (weekday) {
                if (weekday != null) {
                  onChanged(value.copyWith(weekday: weekday));
                }
              },
            );
            final times = Row(
              children: [
                Expanded(
                  child: _TimePickerButton(
                    label: 'Beginn',
                    value: value.start,
                    onSelected: (time) =>
                        onChanged(value.copyWith(start: time)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, size: 18),
                ),
                Expanded(
                  child: _TimePickerButton(
                    label: 'Ende',
                    value: value.end,
                    onSelected: (time) => onChanged(value.copyWith(end: time)),
                  ),
                ),
              ],
            );
            final delete = IconButton(
              tooltip: 'Trainingszeit entfernen',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            );
            final selectedLocation = value.location ?? fallbackLocation;
            final location = DropdownButtonFormField<String>(
              key: ValueKey(
                'slot_location_${value.weekday}_${selectedLocation ?? ''}',
              ),
              initialValue: selectedLocation,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Platz für diesen Trainingstag',
                isDense: true,
                prefixIcon: Icon(Icons.location_on_outlined, size: 19),
              ),
              items: [
                for (final item in locations)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: (selected) =>
                  onChanged(value.copyWith(location: selected)),
            );

            if (constraints.maxWidth < 470) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: day),
                      delete,
                    ],
                  ),
                  const SizedBox(height: 8),
                  times,
                  if (showLocation) ...[
                    const SizedBox(height: 8),
                    location,
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    SizedBox(width: 154, child: day),
                    const SizedBox(width: 10),
                    Expanded(child: times),
                    delete,
                  ],
                ),
                if (showLocation) ...[
                  const SizedBox(height: 9),
                  location,
                ],
              ],
            );
          },
        ),
      );
}

class _TimePickerButton extends StatelessWidget {
  const _TimePickerButton({
    required this.label,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onSelected;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () async {
          final selected = await showTimePicker(
            context: context,
            initialTime: value,
            helpText: '$label auswählen',
            confirmText: 'Übernehmen',
            cancelText: 'Abbrechen',
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                alwaysUse24HourFormat: true,
              ),
              child: child!,
            ),
          );
          if (selected != null) onSelected(selected);
        },
        icon: const Icon(Icons.schedule_rounded, size: 18),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10)),
            Text(
              _TrainingTimeSelection.formatTime(value),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

class _ScheduleHint extends StatelessWidget {
  const _ScheduleHint({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.yellow.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.yellowDark.withValues(alpha: .28),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Text(message)),
          ],
        ),
      );
}

class _EmptyScheduleRow extends StatelessWidget {
  const _EmptyScheduleRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(text, textAlign: TextAlign.center),
      );
}

class _TrainingTimeSelection {
  const _TrainingTimeSelection({
    required this.weekday,
    required this.start,
    required this.end,
    this.location,
  });

  static const weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  final int weekday;
  final TimeOfDay start;
  final TimeOfDay end;
  final String? location;

  int get startMinutes => start.hour * 60 + start.minute;
  int get endMinutes => end.hour * 60 + end.minute;

  String get storageValue {
    final time =
        '${weekdays[weekday - 1]} ${formatTime(start)}–${formatTime(end)}';
    final place = location?.trim();
    return place == null || place.isEmpty ? time : '$time · Platz: $place';
  }

  _TrainingTimeSelection copyWith({
    int? weekday,
    TimeOfDay? start,
    TimeOfDay? end,
    String? location,
  }) =>
      _TrainingTimeSelection(
        weekday: weekday ?? this.weekday,
        start: start ?? this.start,
        end: end ?? this.end,
        location: location ?? this.location,
      );

  static _TrainingTimeSelection? tryParse(
    String value, {
    String? defaultLocation,
  }) {
    final dayMatch = RegExp(
      r'(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)',
      caseSensitive: false,
    ).firstMatch(value);
    final timeMatch = RegExp(
      r'(\d{1,2}):(\d{2})\s*(?:-|–|—|bis)\s*(\d{1,2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(value);
    if (dayMatch == null || timeMatch == null) return null;
    final weekday = weekdays.indexWhere(
          (day) => day.toLowerCase() == dayMatch.group(1)!.toLowerCase(),
        ) +
        1;
    final startHour = int.tryParse(timeMatch.group(1)!) ?? -1;
    final startMinute = int.tryParse(timeMatch.group(2)!) ?? -1;
    final endHour = int.tryParse(timeMatch.group(3)!) ?? -1;
    final endMinute = int.tryParse(timeMatch.group(4)!) ?? -1;
    if (weekday < 1 ||
        startHour < 0 ||
        startHour > 23 ||
        startMinute < 0 ||
        startMinute > 59 ||
        endHour < 0 ||
        endHour > 23 ||
        endMinute < 0 ||
        endMinute > 59) {
      return null;
    }
    final locationMatch = RegExp(
      r'(?:·|\|)\s*Platz:\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    return _TrainingTimeSelection(
      weekday: weekday,
      start: TimeOfDay(hour: startHour, minute: startMinute),
      end: TimeOfDay(hour: endHour, minute: endMinute),
      location: locationMatch?.group(1)?.trim() ?? defaultLocation,
    );
  }

  static String formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _RegularTrainingTimes extends StatelessWidget {
  const _RegularTrainingTimes({required this.team});

  final TeamSummary team;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Container(
            padding: EdgeInsets.all(compact ? 13 : 18),
            decoration: BoxDecoration(
              color: AppColors.black,
              borderRadius: BorderRadius.circular(compact ? 17 : 20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: compact ? 38 : 44,
                      height: compact ? 38 : 44,
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(compact ? 11 : 13),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: AppColors.black,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REGULÄRE TRAININGSZEITEN',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.yellow,
                              fontSize: compact ? 10 : 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: compact ? .4 : .7,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            team.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${team.trainingTimes.length}× / Woche',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 9 : 13),
                if (team.trainingTimes.isEmpty)
                  const Text(
                    'Noch keine regelmäßigen Zeiten hinterlegt',
                    style: TextStyle(color: Colors.white70),
                  )
                else
                  for (final value in team.trainingTimes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 9 : 11,
                          vertical: compact ? 7 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 17,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                value,
                                maxLines: compact ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.black,
                                  fontSize: compact ? 11 : 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (team.trainingTimes.isEmpty &&
                    team.trainingLocation?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      team.trainingLocation!,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Container(
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                fontSize: 15,
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
  ConsumerState<TrainingPlannerPage> createState() =>
      _TrainingPlannerPageState();
}

class _TrainingPlannerPageState extends ConsumerState<TrainingPlannerPage> {
  TrainingModel? _training;
  List<TrainingExerciseModel> _exercises = const [];
  List<TrainingCoachModel> _availableCoaches = const [];
  Set<String> _selectedCoachIds = {};
  List<TrainingPlanItemModel> _items = [];
  Map<String, TrainingAttendanceStatus> _attendance = {};
  final _focus = TextEditingController();
  final _goals = TextEditingController();
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
    _materials.dispose();
    _pitch.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(repositoryProvider);
      final training = await repository.training(widget.trainingId);
      var exercises = const <TrainingExerciseModel>[];
      var availableCoaches = const <TrainingCoachModel>[];
      await Future.wait([
        repository
            .trainingExercises()
            .then((value) => exercises = value)
            .catchError(
              (_) => exercises,
            ),
        repository
            .trainingCoaches(widget.trainingId)
            .then((value) => availableCoaches = value)
            .catchError((_) => availableCoaches),
      ]);
      if (!mounted) return;
      setState(() {
        _training = training;
        _exercises = _mergeTrainingExerciseSuggestions(training, exercises);
        _availableCoaches = availableCoaches;
        _selectedCoachIds =
            training.plan?.coaches.map((coach) => coach.id).toSet() ?? {};
        _items = training.plan?.items.toList() ?? [];
        _focus.text = training.plan?.focusAreas.join(', ') ?? '';
        _goals.text = training.plan?.learningGoals ?? '';
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
        child: Center(
          child: LogoLoadingPanel(message: 'Training wird geladen …'),
        ),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 430;
                return TabBar(
                  isScrollable: !compact,
                  tabs: [
                    Tab(
                      icon: compact
                          ? const Icon(Icons.view_timeline_rounded, size: 19)
                          : null,
                      text: compact ? 'Plan' : 'Einheitsplan',
                    ),
                    Tab(
                      icon: compact
                          ? const Icon(Icons.auto_stories_outlined, size: 19)
                          : null,
                      text: compact ? 'Übungen' : 'Übungsbibliothek',
                    ),
                    Tab(
                      icon: compact
                          ? const Icon(Icons.fact_check_outlined, size: 19)
                          : null,
                      text: 'Anwesenheit',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              height:
                  (MediaQuery.sizeOf(context).height - 225).clamp(460.0, 900.0),
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

  Widget _planTab() => LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth >= 804
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return ListView(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _PresetTextField(
                      controller: _focus,
                      label: 'Schwerpunkte',
                      icon: Icons.center_focus_strong_rounded,
                      options: const [
                        'Ballkontrolle & Dribbling',
                        'Passspiel & Freilaufen',
                        'Torabschluss',
                        'Umschalten',
                        'Zweikampfverhalten',
                        'Koordination & Schnelligkeit',
                      ],
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _CoachMultiSelectField(
                      coaches: _availableCoaches,
                      selectedIds: _selectedCoachIds,
                      onTap: _availableCoaches.isEmpty ? null : _selectCoaches,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PresetTextField(
                controller: _goals,
                label: 'Lernziele',
                icon: Icons.flag_outlined,
                options: const [
                  'Beidfüßig und mit Blick nach vorn lösen',
                  'Nach dem Pass sofort wieder freilaufen',
                  'Mutig ins Dribbling gehen und Entscheidungen treffen',
                  'Schnell umschalten und gemeinsam verteidigen',
                  'Viele Ballaktionen und Torabschlüsse ermöglichen',
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _PresetTextField(
                      controller: _materials,
                      label: 'Material',
                      icon: Icons.inventory_2_outlined,
                      options: const [
                        'Bälle, Hütchen und Leibchen',
                        'Bälle, Mini-Tore und Hütchen',
                        'Bälle, Stangen, Hürden und Leibchen',
                        'Bälle, Koordinationsleiter und Hütchen',
                      ],
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _PresetTextField(
                      controller: _pitch,
                      label: 'Platzaufteilung / Aufbau',
                      icon: Icons.grid_on_rounded,
                      options: const [
                        'Halber Platz · zwei parallele Felder',
                        'Vier kleine Felder für Kleingruppen',
                        'Ein Hauptfeld mit zwei Mini-Toren',
                        'Stationenbetrieb in drei Bereichen',
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, headerConstraints) {
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _addCustomItem,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Freier Baustein'),
                      ),
                      FilledButton.icon(
                        onPressed: _exercises.isEmpty ? null : _addFromLibrary,
                        icon: const Icon(Icons.library_add_outlined),
                        label: const Text('Aus Bibliothek'),
                      ),
                    ],
                  );
                  if (headerConstraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Ablauf',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        AdaptiveActionBar(
                          actions: [
                            AdaptiveActionSpec(
                              label: 'Freier Baustein',
                              icon: Icons.add_rounded,
                              onPressed: _addCustomItem,
                            ),
                            AdaptiveActionSpec(
                              label: 'Aus Bibliothek',
                              icon: Icons.library_add_outlined,
                              onPressed:
                                  _exercises.isEmpty ? null : _addFromLibrary,
                              primary: true,
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Text(
                        'Ablauf',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      actions,
                    ],
                  );
                },
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
                          backgroundColor:
                              _phaseColor(item.phase).withValues(alpha: .12),
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
                          tooltip: 'Übung entfernen',
                          onPressed: () =>
                              setState(() => _items.removeAt(index)),
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
                    _saving ? 'Wird gespeichert …' : 'Trainingsplan speichern',
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      );

  Widget _exerciseTab() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_exercises.length} Übungen & Jugendideen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _createExercise,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    style: compact
                        ? FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                          )
                        : null,
                    label: Text(compact ? 'Neu' : 'Neue Übung'),
                  ),
                ],
              ),
              SizedBox(height: compact ? 7 : 12),
              Expanded(
                child: _exercises.isEmpty
                    ? const EmptyState(
                        icon: Icons.auto_stories_outlined,
                        title: 'Übungsbibliothek ist leer',
                        message:
                            'Lege wiederverwendbare Übungen für dein Trainerteam an.',
                      )
                    : GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 430,
                          mainAxisExtent: compact ? 220 : 245,
                          crossAxisSpacing: compact ? 7 : 12,
                          mainAxisSpacing: compact ? 7 : 12,
                        ),
                        itemCount: _exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = _exercises[index];
                          return Card(
                            child: Padding(
                              padding: EdgeInsets.all(compact ? 11 : 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Chip(
                                            visualDensity: compact
                                                ? const VisualDensity(
                                                    horizontal: -3,
                                                    vertical: -3,
                                                  )
                                                : VisualDensity.standard,
                                            label: Text(
                                              exercise.category,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (exercise.isFavorite)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 4),
                                          child: Icon(
                                            Icons.star_rounded,
                                            color: AppColors.orange,
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    exercise.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: compact
                                        ? Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w900)
                                        : Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    exercise.instructions,
                                    maxLines: compact ? 2 : 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      const Icon(Icons.timer_outlined,
                                          size: 17),
                                      Text(' ${exercise.durationMinutes} Min.'),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _appendExercise(exercise),
                                        style: compact
                                            ? TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                ),
                                              )
                                            : null,
                                        icon: const Icon(Icons.add_rounded,
                                            size: 17),
                                        label: Text(
                                            compact ? 'Planen' : 'Einplanen'),
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
        },
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
            exerciseId: exercise.id.startsWith('preset:') ? null : exercise.id,
          ),
        ),
      );

  Future<void> _addFromLibrary() async {
    final exercise = await showModalBottomSheet<TrainingExerciseModel>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _exercises.length,
          itemBuilder: (context, index) {
            final exercise = _exercises[index];
            return ListTile(
              leading: const Icon(Icons.sports_soccer_rounded),
              title: Text(exercise.title),
              subtitle: Text(
                  '${exercise.category} · ${exercise.durationMinutes} Min.'),
              onTap: () => Navigator.pop(context, exercise),
            );
          },
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
                  decoration:
                      const InputDecoration(labelText: 'Dauer in Minuten'),
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
                        decoration:
                            const InputDecoration(labelText: 'Kategorie'),
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
                    const SnackBar(
                        content:
                            Text('Übung konnte nicht gespeichert werden.')),
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
            coachIds: _selectedCoachIds.toList(),
            learningGoals: _goals.text,
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

  Future<void> _selectCoaches() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        var draft = {..._selectedCoachIds};
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .78,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trainerteam auswählen',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Mehrere Trainer der zugeordneten Jugend sind möglich.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => setSheetState(
                            () => draft =
                                draft.length == _availableCoaches.length
                                    ? {}
                                    : _availableCoaches
                                        .map((coach) => coach.id)
                                        .toSet(),
                          ),
                          child: Text(
                            draft.length == _availableCoaches.length
                                ? 'Alle abwählen'
                                : 'Alle auswählen',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final coach in _availableCoaches)
                          CheckboxListTile(
                            value: draft.contains(coach.id),
                            secondary: CircleAvatar(
                              backgroundColor:
                                  AppColors.yellow.withValues(alpha: .35),
                              foregroundColor: AppColors.black,
                              child: Text(_initials(coach.name)),
                            ),
                            title: Text(coach.name),
                            subtitle: Text(_coachRoleLabel(coach.role)),
                            onChanged: (value) => setSheetState(() {
                              if (value == true) {
                                draft.add(coach.id);
                              } else {
                                draft.remove(coach.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, draft),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          '${draft.length} ${draft.length == 1 ? 'Person' : 'Personen'} übernehmen',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _selectedCoachIds = selected);
    }
  }
}

class _PresetTextField extends StatefulWidget {
  const _PresetTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.options,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final List<String> options;

  @override
  State<_PresetTextField> createState() => _PresetTextFieldState();
}

class _PresetTextFieldState extends State<_PresetTextField> {
  static const customValue = '__custom__';
  late String? value;

  @override
  void initState() {
    super.initState();
    value = widget.controller.text.trim().isEmpty
        ? null
        : widget.controller.text.trim();
  }

  @override
  void didUpdateWidget(covariant _PresetTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.controller.text.trim();
    if (current != (value ?? '')) value = current.isEmpty ? null : current;
  }

  @override
  Widget build(BuildContext context) {
    final values = <String>{
      ...widget.options,
      if (value?.isNotEmpty == true && !widget.options.contains(value)) value!,
    };
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon),
      ),
      hint: const Text('Auswählen oder selbst eingeben'),
      items: [
        for (final option in values)
          DropdownMenuItem(
            value: option,
            child: Text(
              option,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const DropdownMenuItem(
          value: customValue,
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18),
              SizedBox(width: 8),
              Text('Eigene Eingabe …'),
            ],
          ),
        ),
      ],
      onChanged: (selected) async {
        if (selected == customValue) {
          final editor = TextEditingController(text: value ?? '');
          final custom = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('${widget.label} anpassen'),
              content: TextField(
                controller: editor,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Eigene Angabe eintragen',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, editor.text.trim()),
                  child: const Text('Übernehmen'),
                ),
              ],
            ),
          );
          editor.dispose();
          if (!mounted || custom == null) {
            setState(() {});
            return;
          }
          setState(() {
            value = custom.isEmpty ? null : custom;
            widget.controller.text = custom;
          });
          return;
        }
        setState(() {
          value = selected;
          widget.controller.text = selected ?? '';
        });
      },
    );
  }
}

List<TrainingExerciseModel> _mergeTrainingExerciseSuggestions(
  TrainingModel training,
  List<TrainingExerciseModel> saved,
) {
  final titles = saved.map((item) => item.title.toLowerCase().trim()).toSet();
  return [
    ...saved,
    ...trainingExerciseSuggestions(training).where(
      (item) => !titles.contains(item.title.toLowerCase().trim()),
    ),
  ];
}

List<TrainingExerciseModel> trainingExerciseSuggestions(
  TrainingModel training,
) {
  final context =
      '${training.teamNames.join(' ')} ${training.title}'.toUpperCase();
  final age =
      RegExp(r'\b([A-G])\d?[- ]?JUGEND\b').firstMatch(context)?.group(1) ??
          RegExp(r'\b([A-G])\d\b').firstMatch(context)?.group(1) ??
          'E';
  final ideas = switch (age) {
    'G' => const [
        (
          'Dribbel-Zoo',
          'Ballgefühl',
          10,
          'Viele kleine Hütchentore verteilen.',
          'Jedes Kind führt einen Ball und löst spielerische Bewegungsaufgaben.'
        ),
        (
          'Farben-Fänger',
          'Reaktion',
          10,
          'Vier farbige Zonen markieren.',
          'Auf Zuruf dribbeln die Kinder schnell in die passende Farbzone.'
        ),
        (
          '3 gegen 3 auf zwei Tore',
          'Spielform',
          15,
          'Kleines Feld mit zwei Mini-Toren.',
          'Freies Spiel mit vielen Ballkontakten und schnellen Neustarts.'
        ),
      ],
    'F' => const [
        (
          'Balljäger mit Rettungszonen',
          'Dribbling',
          12,
          'Quadrat mit vier sicheren Ecken markieren.',
          'Kinder schützen ihren Ball und wechseln mutig die Richtung.'
        ),
        (
          'Passtore sammeln',
          'Passspiel',
          12,
          'Mehrere Hütchentore im Feld verteilen.',
          'Paare passen durch möglichst viele unterschiedliche Tore.'
        ),
        (
          '3 gegen 3 auf vier Tore',
          'Spielform',
          18,
          'Vier Mini-Tore an den Seiten aufstellen.',
          'Freies Spiel; jedes Team greift auf zwei Tore an.'
        ),
      ],
    'E' => const [
        (
          'Finten-Inseln',
          'Dribbling',
          12,
          'Vier Inseln mit Hütchen und je einem Fintenauftrag aufbauen.',
          'Spieler dribbeln frei und führen an jeder Insel eine andere Finte aus.'
        ),
        (
          'Passdreieck mit Anschlussaktion',
          'Passspiel',
          15,
          'Dreiecke in Kleingruppen markieren.',
          'Passen, dem Ball nachgehen und vor der Annahme offen zum Feld stehen.'
        ),
        (
          '3 gegen 3 auf vier Tore',
          'Spielform',
          18,
          'Vier Mini-Tore an den Seiten aufstellen.',
          'Freies Spiel mit Umschalten; jedes Team greift auf zwei Tore an.'
        ),
        (
          'Torabschluss nach Dribbling',
          'Torabschluss',
          15,
          'Zwei kurze Dribbelparcours vor dem Tor.',
          'Finte am Hütchen, Ball vorlegen und gezielt mit beiden Füßen abschließen.'
        ),
      ],
    _ => const [
        (
          'Rondo mit Anschlussaktion',
          'Passspiel',
          15,
          'Zwei Felder für 4 gegen 1 oder 5 gegen 2.',
          'Nach mehreren Pässen folgt der zielgerichtete Wechsel ins Nachbarfeld.'
        ),
        (
          'Überzahl zum Torabschluss',
          'Taktik',
          18,
          'Halbfeld mit Tor und zwei Kontertoren.',
          'Angreifer lösen eine Überzahl und schalten nach Ballverlust sofort um.'
        ),
        (
          '4 gegen 4 plus Anspieler',
          'Spielform',
          20,
          'Kompaktes Feld mit neutralen Außenspielern.',
          'Ballbesitz sichern, Tiefe erkennen und nach Ballgewinn schnell spielen.'
        ),
      ],
  };
  return [
    for (var index = 0; index < ideas.length; index++)
      TrainingExerciseModel(
        id: 'preset:$age:$index',
        teamId: training.teamId,
        title: ideas[index].$1,
        category: '$age-Jugend · ${ideas[index].$2}',
        durationMinutes: ideas[index].$3,
        setup: ideas[index].$4,
        instructions: ideas[index].$5,
        isFavorite: false,
      ),
  ];
}

class _CoachMultiSelectField extends StatelessWidget {
  const _CoachMultiSelectField({
    required this.coaches,
    required this.selectedIds,
    required this.onTap,
  });

  final List<TrainingCoachModel> coaches;
  final Set<String> selectedIds;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected =
        coaches.where((coach) => selectedIds.contains(coach.id)).toList();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Trainerteam',
          prefixIcon: const Icon(Icons.groups_2_outlined),
          suffixIcon:
              onTap == null ? null : const Icon(Icons.arrow_drop_down_rounded),
        ),
        isEmpty: selected.isEmpty,
        child: selected.isEmpty
            ? Text(
                coaches.isEmpty
                    ? 'Keine freigegebenen Trainer'
                    : 'Trainer auswählen · Mehrfachauswahl',
                style: const TextStyle(color: AppColors.muted),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final coach in selected)
                    Chip(
                      avatar: CircleAvatar(
                        child: Text(
                          _initials(coach.name),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      label: Text(coach.name),
                    ),
                ],
              ),
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

String _coachRoleLabel(String role) => switch (role) {
      'COACH' || 'TRAINER' => 'Trainer/in',
      'ASSISTANT_COACH' => 'Co-Trainer/in',
      'TRAINER_ADMIN' => 'Trainer-Administration',
      'TEAM_MANAGER' => 'Teammanagement',
      _ => 'Trainerteam',
    };

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
