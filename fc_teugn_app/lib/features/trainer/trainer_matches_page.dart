import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/data_repository.dart';
import '../../core/football_options.dart';
import '../../core/models/event.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../../core/widgets/team_crest.dart';
import '../shared/page_scaffold.dart';
import '../imports/competition_import_dialog.dart';
import '../matches/competition_management_dialog.dart';

class TrainerMatchesPage extends ConsumerWidget {
  const TrainerMatchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final repository = ref.watch(repositoryProvider);
    final organization = ref.watch(organizationProvider).valueOrNull;

    return PageScaffold(
      title: 'Spieltage',
      subtitle: 'Gegner, Wettbewerb und Ergebnisse zentral verwalten.',
      action: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final organization = await ref.read(organizationProvider.future);
              if (!context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (context) => CompetitionManagementDialog(
                  repository: repository,
                  organization: organization,
                ),
              );
            },
            icon: const Icon(Icons.emoji_events_outlined),
            label: const Text('Liga & Gegner'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final organization = await ref.read(organizationProvider.future);
              if (!context.mounted) return;
              final imported = await showDialog<bool>(
                context: context,
                builder: (context) =>
                    CompetitionImportDialog(organization: organization),
              );
              if (imported == true) {
                ref.invalidate(eventsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Spielplan wurde importiert.')),
                  );
                }
              }
            },
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Spielplan importieren'),
          ),
        ],
      ),
      child: events.when(
        data: (items) {
          final matches = items
              .where((event) => event.type == EventType.match)
              .toList()
            ..sort((a, b) => b.startAt.compareTo(a.startAt));
          if (matches.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_soccer_rounded,
              title: 'Noch kein Spiel angelegt',
              message:
                  'Lege unter „Termine“ ein Spiel an, um hier den Spieltag zu planen.',
            );
          }
          return Column(
            children: [
              for (final match in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _MatchCard(
                    event: match,
                    onOpen: () => context.push('/trainer/matches/${match.id}'),
                    onDelete: match.capabilities.canDelete
                        ? () => _deleteMatch(context, ref, match)
                        : null,
                    onReschedule: match.capabilities.canReschedule
                        ? () => _rescheduleMatch(context, ref, match)
                        : null,
                    onEdit: () async {
                      final draft = await _openMatchDialog(
                        context,
                        match,
                        repository,
                        organization,
                      );
                      if (draft == null) return;
                      try {
                        await repository.updateMatchDetails(
                          eventId: match.id,
                          opponent: draft.opponent,
                          isHome: draft.isHome,
                          competition: draft.competition,
                          notes: draft.notes,
                          ourGoals: draft.ourGoals,
                          theirGoals: draft.theirGoals,
                          periodCount: draft.periodCount,
                          periodMinutes: draft.periodMinutes,
                          opponentId: draft.opponentId,
                        );
                        ref.invalidate(eventsProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Spieldaten gespeichert.')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Spieldaten konnten nicht gespeichert werden.')),
                          );
                        }
                      }
                    },
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(
          child: LogoLoadingPanel(message: 'Spiele werden geladen …'),
        ),
        error: (_, __) => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Spiele nicht erreichbar',
          message: 'Bitte prüfe die Verbindung und versuche es erneut.',
        ),
      ),
    );
  }

  Future<void> _deleteMatch(
    BuildContext context,
    WidgetRef ref,
    EventModel event,
  ) async {
    var scope = 'single';
    var deleteLeagueMatch = event.matchDetails?.leagueId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: const Text('Spiel endgültig löschen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '„${event.title}“ wird mit Kader, Aufstellung, Liveticker, '
                'Statistiken und Rückmeldungen dauerhaft gelöscht. Diese '
                'Aktion kann nicht rückgängig gemacht werden.',
              ),
              if (event.isRecurring) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: 'Umfang'),
                  items: const [
                    DropdownMenuItem(
                      value: 'single',
                      child: Text('Nur dieses Spiel'),
                    ),
                    DropdownMenuItem(
                      value: 'future',
                      child: Text('Dieses und alle folgenden'),
                    ),
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Komplette Spielserie'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => scope = value ?? 'single',
                  ),
                ),
              ],
              if (event.matchDetails?.leagueId != null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verknüpfte Ligapartie mit löschen'),
                  subtitle: const Text(
                    'Die Partie verschwindet dann auch aus Spielplan und Tabelle.',
                  ),
                  value: deleteLeagueMatch,
                  onChanged: (value) => setDialogState(
                    () => deleteLeagueMatch = value ?? false,
                  ),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Endgültig löschen'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deleteEventPermanently(
            eventId: event.id,
            scope: scope,
            deleteLeagueMatch: deleteLeagueMatch,
          );
      ref.invalidate(eventsProvider);
      final refreshed = await ref.read(eventsProvider.future);
      if (refreshed.any((item) => item.id == event.id)) {
        throw StateError('Das gelöschte Spiel ist weiterhin vorhanden.');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spiel wurde endgültig gelöscht.')),
        );
      }
    } catch (_) {
      ref.invalidate(eventsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spiel konnte nicht gelöscht werden.')),
        );
      }
    }
  }

  Future<OpponentModel?> _createOpponent(
    BuildContext context,
    DataRepository repository,
    String ageGroupId,
    String? teamId,
  ) async {
    final club = TextEditingController();
    final designation = TextEditingController();
    final venue = TextEditingController();
    final address = TextEditingController();
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ResponsiveFormDialog(
          title: 'Gegner fest hinzufügen',
          subtitle:
              'Die Mannschaft steht anschließend für weitere Spiele dieser Jugend bereit.',
          maxWidth: 560,
          onSave: () {
            if (club.text.trim().isEmpty || designation.text.trim().isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Bitte Verein und Mannschaft angeben.'),
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, true);
          },
          children: [
            TextField(
              controller: club,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Verein *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: designation,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Jugend / Mannschaft *',
                hintText: 'z. B. E1',
              ),
            ),
            const SizedBox(height: 12),
            ResponsiveFormRow(
              children: [
                TextField(
                  controller: venue,
                  decoration: const InputDecoration(labelText: 'Spielstätte'),
                ),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Adresse'),
                ),
              ],
            ),
          ],
        ),
      );
      if (save != true) return null;
      return repository.saveOpponent(
        ageGroupId: ageGroupId,
        teamId: teamId,
        clubName: club.text.trim(),
        teamDesignation: designation.text.trim(),
        venue: venue.text.trim(),
        address: address.text.trim(),
      );
    } finally {
      club.dispose();
      designation.dispose();
      venue.dispose();
      address.dispose();
    }
  }

  Future<void> _rescheduleMatch(
    BuildContext context,
    WidgetRef ref,
    EventModel event,
  ) async {
    final draft = await _openRescheduleDialog(context, event);
    if (draft == null || !context.mounted) return;

    Future<void> save({bool confirmConflicts = false}) =>
        ref.read(repositoryProvider).rescheduleMatch(
              eventId: event.id,
              startAt: draft.startAt,
              meetingAt: draft.meetingAt,
              meetingLocation: draft.meetingLocation,
              location: draft.location,
              address: draft.address,
              pitch: draft.pitch,
              isHome: draft.isHome,
              matchDay: draft.matchDay,
              reason: draft.reason,
              internalNote: draft.internalNote,
              publicNotice: draft.publicNotice,
              retention: draft.retention,
              notification: draft.notification,
              confirmConflicts: confirmConflicts,
            );

    try {
      await save();
    } on DioException catch (error) {
      if (error.response?.statusCode != 409 || !context.mounted) rethrow;
      final data = error.response?.data;
      final conflicts = data is Map<String, dynamic>
          ? (data['conflicts'] as List<dynamic>? ?? const [])
          : const <dynamic>[];
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Terminüberschneidung erkannt'),
          content: Text(
            conflicts.isEmpty
                ? 'Das Spiel kann in seinem aktuellen Zustand nicht verlegt werden.'
                : 'Der neue Termin überschneidet sich mit ${conflicts.length} '
                    'bestehenden Belegung${conflicts.length == 1 ? '' : 'en'}. '
                    'Trotzdem verbindlich speichern?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Prüfen'),
            ),
            if (conflicts.isNotEmpty)
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Trotzdem verlegen'),
              ),
          ],
        ),
      );
      if (proceed != true) return;
      try {
        await save(confirmConflicts: true);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Das Spiel konnte nicht verlegt werden.'),
            ),
          );
        }
        return;
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Das Spiel konnte nicht verlegt werden.'),
          ),
        );
      }
      return;
    }
    ref.invalidate(eventsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spieltermin wurde verbindlich verlegt.')),
      );
    }
  }

  Future<_RescheduleDraft?> _openRescheduleDialog(
    BuildContext context,
    EventModel event,
  ) async {
    const homeVenue = 'Stadion am Kreutweg, Teugn';
    const awayMeeting = 'Vereinsheim Teugn';
    var startAt = event.startAt.toLocal();
    var meetingAt = event.meetingAt?.toLocal() ??
        startAt.subtract(const Duration(minutes: 60));
    var isHome = event.matchDetails?.isHome ?? event.homeAway != HomeAway.away;
    final location = TextEditingController(
      text: isHome ? homeVenue : event.location,
    );
    final meetingLocation = TextEditingController(
      text: isHome ? (event.meetingLocation ?? '') : awayMeeting,
    );
    final address = TextEditingController(text: event.address ?? '');
    final pitch = TextEditingController(text: event.venue ?? '');
    final matchDay = TextEditingController();
    final reason = TextEditingController();
    final publicNotice = TextEditingController();
    final internalNote = TextEditingController(text: event.internalNote ?? '');
    var retention = 'KEEP';
    var notification = 'PUSH';

    Future<DateTime?> pickDateTime(
      BuildContext dialogContext,
      DateTime initial,
    ) async {
      final date = await showDatePicker(
        context: dialogContext,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
      );
      if (date == null || !dialogContext.mounted) return null;
      final time = await showTimePicker(
        context: dialogContext,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (time == null) return null;
      return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    try {
      return await showDialog<_RescheduleDraft>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) => ResponsiveFormDialog(
            title: 'Spiel verlegen',
            subtitle:
                'Neuen Termin prüfen, Zuständigkeiten festlegen und Betroffene informieren.',
            maxWidth: 680,
            saveLabel: 'Verlegung prüfen',
            saveIcon: Icons.event_repeat_rounded,
            onSave: () async {
              if (meetingAt.isAfter(startAt) ||
                  meetingAt.isAtSameMomentAs(startAt)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Der Treffpunkt muss vor dem Anpfiff liegen.'),
                  ),
                );
                return;
              }
              if (location.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                      content: Text('Bitte einen Spielort angeben.')),
                );
                return;
              }
              final draft = _RescheduleDraft(
                startAt: startAt,
                meetingAt: meetingAt,
                meetingLocation: meetingLocation.text.trim(),
                location: isHome ? homeVenue : location.text.trim(),
                address: address.text.trim(),
                pitch: pitch.text.trim(),
                isHome: isHome,
                matchDay: matchDay.text.trim(),
                reason: reason.text.trim(),
                publicNotice: publicNotice.text.trim(),
                internalNote: internalNote.text.trim(),
                retention: retention,
                notification: notification,
              );
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (summaryContext) => AlertDialog(
                  title: const Text('Verlegung verbindlich speichern?'),
                  content: Text(
                    '${_formatDateTime(draft.startAt)}\n'
                    'Treffpunkt: ${_formatDateTime(draft.meetingAt)} · '
                    '${draft.meetingLocation.isEmpty ? 'noch offen' : draft.meetingLocation}\n'
                    'Spielort: ${draft.location}\n\n'
                    'Kader/Rückmeldungen: ${_retentionLabel(draft.retention)}\n'
                    'Information: ${_notificationLabel(draft.notification)}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(summaryContext, false),
                      child: const Text('Zurück'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(summaryContext, true),
                      child: const Text('Verbindlich verlegen'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && dialogContext.mounted) {
                Navigator.pop(dialogContext, draft);
              }
            },
            children: [
              ResponsiveFormSection(
                title: 'Neuer Termin',
                icon: Icons.event_repeat_rounded,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Anpfiff'),
                    subtitle: Text(_formatDateTime(startAt)),
                    trailing: const Icon(Icons.edit_calendar_rounded),
                    onTap: () async {
                      final value = await pickDateTime(dialogContext, startAt);
                      if (value != null) setState(() => startAt = value);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Treffpunktzeit'),
                    subtitle: Text(_formatDateTime(meetingAt)),
                    trailing: const Icon(Icons.schedule_rounded),
                    onTap: () async {
                      final value =
                          await pickDateTime(dialogContext, meetingAt);
                      if (value != null) setState(() => meetingAt = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.home_rounded),
                        label: Text('Heimspiel'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.directions_bus_rounded),
                        label: Text('Auswärts'),
                      ),
                    ],
                    selected: {isHome},
                    onSelectionChanged: (selection) => setState(() {
                      isHome = selection.first;
                      if (isHome) {
                        location.text = homeVenue;
                      } else {
                        meetingLocation.text = awayMeeting;
                        if (location.text == homeVenue) location.clear();
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: location,
                    readOnly: isHome,
                    decoration: InputDecoration(
                      labelText: 'Spielstätte *',
                      helperText: isHome
                          ? 'Für Heimspiele fest vorgegeben.'
                          : 'Spielstätte des Gegners',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ResponsiveFormRow(
                    children: [
                      TextField(
                        controller: meetingLocation,
                        decoration:
                            const InputDecoration(labelText: 'Treffpunkt'),
                      ),
                      TextField(
                        controller: pitch,
                        decoration:
                            const InputDecoration(labelText: 'Platz / Feld'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ResponsiveFormRow(
                    children: [
                      TextField(
                        controller: address,
                        decoration: const InputDecoration(labelText: 'Adresse'),
                      ),
                      TextField(
                        controller: matchDay,
                        decoration:
                            const InputDecoration(labelText: 'Spieltag'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Folgen der Verlegung',
                icon: Icons.rule_rounded,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: retention,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kader und Rückmeldungen',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'KEEP',
                        child: Text('Alles beibehalten'),
                      ),
                      DropdownMenuItem(
                        value: 'RESET_RESPONSES',
                        child: Text('Rückmeldungen neu anfordern'),
                      ),
                      DropdownMenuItem(
                        value: 'RESET_SQUAD',
                        child: Text('Kader und Rückmeldungen zurücksetzen'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => retention = value ?? 'KEEP'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: notification,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Benachrichtigung'),
                    items: const [
                      DropdownMenuItem(
                        value: 'PUSH',
                        child: Text('In-App und Push senden'),
                      ),
                      DropdownMenuItem(
                        value: 'IN_APP',
                        child: Text('Nur In-App senden'),
                      ),
                      DropdownMenuItem(
                        value: 'NONE',
                        child: Text('Keine Benachrichtigung'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => notification = value ?? 'PUSH'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Hinweise',
                icon: Icons.notes_rounded,
                children: [
                  TextField(
                    controller: reason,
                    decoration:
                        const InputDecoration(labelText: 'Grund der Verlegung'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: publicNotice,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Öffentlicher Hinweis'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: internalNote,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Interne Notiz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } finally {
      location.dispose();
      meetingLocation.dispose();
      address.dispose();
      pitch.dispose();
      matchDay.dispose();
      reason.dispose();
      publicNotice.dispose();
      internalNote.dispose();
    }
  }

  Future<_MatchDraft?> _openMatchDialog(
    BuildContext context,
    EventModel event,
    DataRepository repository,
    OrganizationContext? organization,
  ) async {
    final details = event.matchDetails;
    final opponent = TextEditingController(text: details?.opponent ?? '');
    final team = organization?.teams
        .where((item) => item.id == event.teamId)
        .firstOrNull;
    final ageGroupId = team?.ageGroup.id;
    var opponents = ageGroupId == null
        ? <OpponentModel>[]
        : await repository.opponents(ageGroupId).catchError(
              (_) => <OpponentModel>[],
            );
    if (!context.mounted) {
      opponent.dispose();
      return null;
    }
    String? selectedOpponentId = details?.opponentId;
    String? competition = details?.competition ?? 'Liga';
    final notes = TextEditingController(text: details?.notes ?? '');
    final ourGoals =
        TextEditingController(text: details?.ourGoals?.toString() ?? '');
    final theirGoals =
        TextEditingController(text: details?.theirGoals?.toString() ?? '');
    final periodCount = TextEditingController(
      text: (details?.periodCount ?? 2).toString(),
    );
    final periodMinutes = TextEditingController(
      text: (details?.periodMinutes ?? 30).toString(),
    );
    var isHome = details?.isHome ?? true;

    final result = await showDialog<_MatchDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void save() {
            if (opponent.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bitte einen Gegner eintragen.')),
              );
              return;
            }
            final count = int.tryParse(periodCount.text.trim());
            final minutes = int.tryParse(periodMinutes.text.trim());
            if (count == null ||
                count < 1 ||
                count > 8 ||
                minutes == null ||
                minutes < 1 ||
                minutes > 90 ||
                count * minutes > 180) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Bitte 1–8 Abschnitte und 1–90 Minuten je Abschnitt '
                    '(maximal 180 Minuten insgesamt) eingeben.',
                  ),
                ),
              );
              return;
            }
            final selectedOpponent = opponents
                .where((item) => item.id == selectedOpponentId)
                .firstOrNull;
            if (selectedOpponent?.displayName != opponent.text.trim()) {
              selectedOpponentId = null;
            }
            Navigator.pop(
              context,
              _MatchDraft(
                opponent: opponent.text.trim(),
                opponentId: selectedOpponentId,
                isHome: isHome,
                competition: competition ?? '',
                notes: notes.text.trim(),
                ourGoals: int.tryParse(ourGoals.text),
                theirGoals: int.tryParse(theirGoals.text),
                periodCount: count,
                periodMinutes: minutes,
              ),
            );
          }

          return ResponsiveFormDialog(
            title: 'Spieldaten bearbeiten',
            subtitle: 'Begegnung, Ergebnis und Spielzeit kompakt verwalten.',
            maxWidth: 620,
            onSave: save,
            children: [
              ResponsiveFormSection(
                title: 'Begegnung',
                icon: Icons.sports_soccer_rounded,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth < 390
                            ? DropdownButtonFormField<bool>(
                                initialValue: isHome,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Spielort',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: true,
                                    child: Text('Heimspiel'),
                                  ),
                                  DropdownMenuItem(
                                    value: false,
                                    child: Text('Auswärtsspiel'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => isHome = value);
                                  }
                                },
                              )
                            : SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Heimspiel'),
                                    icon: Icon(Icons.home_rounded),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Auswärts'),
                                    icon: Icon(Icons.directions_bus_rounded),
                                  ),
                                ],
                                selected: {isHome},
                                onSelectionChanged: (value) =>
                                    setState(() => isHome = value.first),
                              ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              DropdownMenu<String>(
                            controller: opponent,
                            width: constraints.maxWidth,
                            label: const Text('Gegner'),
                            hintText:
                                'Gespeichert auswählen oder frei eingeben',
                            enableFilter: true,
                            enableSearch: true,
                            dropdownMenuEntries: [
                              for (final item in opponents)
                                DropdownMenuEntry(
                                  value: item.id,
                                  label: item.displayName,
                                  leadingIcon: TeamCrest.opponent(
                                    size: 24,
                                    logoUrl: item.logoUrl,
                                  ),
                                ),
                            ],
                            onSelected: (id) {
                              final selected = opponents
                                  .where((item) => item.id == id)
                                  .firstOrNull;
                              if (selected == null) return;
                              selectedOpponentId = selected.id;
                              opponent.text = selected.displayName;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Gegner fest hinzufügen',
                        onPressed: ageGroupId == null
                            ? null
                            : () async {
                                final created = await _createOpponent(
                                  context,
                                  repository,
                                  ageGroupId,
                                  team?.id,
                                );
                                if (created == null) return;
                                setState(() {
                                  opponents = [...opponents, created]
                                    ..sort((a, b) =>
                                        a.displayName.compareTo(b.displayName));
                                  selectedOpponentId = created.id;
                                  opponent.text = created.displayName;
                                });
                              },
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: ListTile(
                      leading: Icon(
                        isHome
                            ? Icons.stadium_rounded
                            : Icons.directions_bus_rounded,
                      ),
                      title: Text(
                        isHome
                            ? 'Heimspielstätte: Stadion am Kreutweg, Teugn'
                            : 'Standard-Treffpunkt: Vereinsheim Teugn',
                      ),
                      subtitle: Text(
                        isHome
                            ? 'Die Heimspielstätte wird automatisch fest übernommen.'
                            : 'Der Treffpunkt wird automatisch vorbelegt und kann beim Verlegen angepasst werden.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: competition,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Wettbewerb'),
                    items: footballOptionItems(
                      options: footballCompetitions,
                      emptyLabel: 'Nicht angegeben',
                      currentValue: competition,
                    ),
                    onChanged: (value) => setState(() => competition = value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Ergebnis',
                subtitle: 'Optional – kann auch später ergänzt werden.',
                icon: Icons.scoreboard_outlined,
                children: [
                  ResponsiveFormRow(
                    children: [
                      TextField(
                        controller: ourGoals,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Tore FC Teugn'),
                      ),
                      TextField(
                        controller: theirGoals,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Tore Gegner'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Spielzeit',
                icon: Icons.timer_outlined,
                children: [
                  ResponsiveFormRow(
                    children: [
                      TextField(
                        controller: periodCount,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Spielabschnitte',
                          helperText: '2 Halbzeiten / 4 Viertel',
                        ),
                      ),
                      TextField(
                        controller: periodMinutes,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Minuten je Abschnitt',
                          helperText: 'z. B. 15',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final count = int.tryParse(periodCount.text.trim());
                      final minutes = int.tryParse(periodMinutes.text.trim());
                      final total = count == null || minutes == null
                          ? null
                          : count * minutes;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          total == null
                              ? 'Gesamtspielzeit: –'
                              : 'Gesamtspielzeit: $count × $minutes = $total Minuten',
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ResponsiveFormSection(
                title: 'Notizen',
                icon: Icons.notes_rounded,
                children: [
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notizen'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    opponent.dispose();
    notes.dispose();
    ourGoals.dispose();
    theirGoals.dispose();
    periodCount.dispose();
    periodMinutes.dispose();
    return result;
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.event,
    required this.onEdit,
    required this.onOpen,
    this.onDelete,
    this.onReschedule,
  });
  final EventModel event;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onReschedule;

  @override
  Widget build(BuildContext context) {
    final details = event.matchDetails;
    final date = event.startAt.toLocal();
    final hasResult = details?.ourGoals != null && details?.theirGoals != null;
    final isFriendly = event.category == EventCategory.friendlyMatch ||
        (details?.competition ?? '').toLowerCase().contains('freundschaft');
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final title = details == null
              ? event.title
              : 'FC Teugn ${details.isHome ? '–' : '@'} ${details.opponent}';
          final information = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}.${date.month}.${date.year} · ${event.location}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (details?.competition?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isFriendly
                          ? AppColors.yellowSoft
                          : AppColors.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isFriendly
                            ? AppColors.gold
                            : AppColors.blue.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      child: Text(
                        isFriendly
                            ? 'Freundschaftsspiel'
                            : details!.competition!,
                        style: TextStyle(
                          color: isFriendly ? AppColors.gold : AppColors.blue,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              if (details != null)
                Text(
                  '${details.periodCount} × ${details.periodMinutes} Min. '
                  '· ${details.durationMinutes} Min. gesamt',
                ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Daten'),
              ),
              if (onReschedule != null)
                OutlinedButton.icon(
                  onPressed: onReschedule,
                  icon: const Icon(Icons.event_repeat_rounded, size: 18),
                  label: const Text('Verlegen'),
                ),
              if (onDelete != null)
                IconButton.filledTonal(
                  onPressed: onDelete,
                  color: Theme.of(context).colorScheme.error,
                  tooltip: 'Spiel endgültig löschen',
                  icon: const Icon(Icons.delete_forever_rounded),
                ),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.stadium_rounded, size: 18),
                label: const Text('Spieltag'),
              ),
            ],
          );
          return Padding(
            padding: EdgeInsets.all(compact ? 14 : 20),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MatchLogos(
                            opponentLogoUrl: details?.opponentLogoUrl,
                            compact: true,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: information),
                          if (hasResult) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${details!.ourGoals}:${details.theirGoals}',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(alignment: Alignment.centerLeft, child: actions),
                    ],
                  )
                : Row(
                    children: [
                      _MatchLogos(
                        opponentLogoUrl: details?.opponentLogoUrl,
                        compact: false,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: information),
                      if (hasResult)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${details!.ourGoals} : ${details.theirGoals}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _MatchLogos extends StatelessWidget {
  const _MatchLogos({required this.opponentLogoUrl, required this.compact});
  final String? opponentLogoUrl;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 42.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamCrest.club(size: size),
        const SizedBox(width: 5),
        TeamCrest.opponent(
          size: size,
          logoUrl: opponentLogoUrl,
        ),
      ],
    );
  }
}

class _MatchDraft {
  const _MatchDraft({
    required this.opponent,
    required this.isHome,
    required this.competition,
    required this.notes,
    required this.periodCount,
    required this.periodMinutes,
    this.opponentId,
    this.ourGoals,
    this.theirGoals,
  });
  final String opponent;
  final String? opponentId;
  final bool isHome;
  final String competition;
  final String notes;
  final int periodCount;
  final int periodMinutes;
  final int? ourGoals;
  final int? theirGoals;
}

class _RescheduleDraft {
  const _RescheduleDraft({
    required this.startAt,
    required this.meetingAt,
    required this.meetingLocation,
    required this.location,
    required this.address,
    required this.pitch,
    required this.isHome,
    required this.matchDay,
    required this.reason,
    required this.publicNotice,
    required this.internalNote,
    required this.retention,
    required this.notification,
  });

  final DateTime startAt;
  final DateTime meetingAt;
  final String meetingLocation;
  final String location;
  final String address;
  final String pitch;
  final bool isHome;
  final String matchDay;
  final String reason;
  final String publicNotice;
  final String internalNote;
  final String retention;
  final String notification;
}

String _retentionLabel(String value) => switch (value) {
      'RESET_RESPONSES' => 'Rückmeldungen neu anfordern',
      'RESET_SQUAD' => 'Kader und Rückmeldungen zurücksetzen',
      _ => 'Alles beibehalten',
    };

String _notificationLabel(String value) => switch (value) {
      'PUSH' => 'In-App und Push',
      'IN_APP' => 'Nur In-App',
      _ => 'Keine Benachrichtigung',
    };

String _formatDateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year} · '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')} Uhr';
