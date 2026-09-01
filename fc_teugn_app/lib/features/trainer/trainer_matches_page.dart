import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/data_repository.dart';
import '../../core/football_options.dart';
import '../../core/match_view_preferences.dart';
import '../../core/match_overview_sort.dart';
import '../../core/models/event.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../../core/widgets/team_crest.dart';
import '../../core/widgets/match_venue_badge.dart';
import '../shared/page_scaffold.dart';
import '../imports/competition_import_dialog.dart';
import '../matches/competition_management_dialog.dart';
import '../matches/past_matches_page.dart';
import '../matches/tournament_opponent_picker.dart';
import '../auth/auth_controller.dart';
import '../../core/models/user.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../calendar/tournament_plan_browser_page.dart';

class TrainerMatchesPage extends ConsumerStatefulWidget {
  const TrainerMatchesPage({super.key});

  @override
  ConsumerState<TrainerMatchesPage> createState() => _TrainerMatchesPageState();
}

class _TrainerMatchesPageState extends ConsumerState<TrainerMatchesPage> {
  final _viewPreferences = MatchViewPreferences();
  MatchSortOrder _sortOrder = MatchSortOrder.nextFirst;
  MatchViewMode _viewMode = MatchViewMode.veryCompact;

  String get _preferenceUserId =>
      ref.read(authProvider).user?.id ?? 'anonymous';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    try {
      final values = await Future.wait([
        _viewPreferences.loadSortOrder(_preferenceUserId),
        _viewPreferences.loadViewMode(_preferenceUserId),
      ]);
      if (!mounted) return;
      setState(() {
        _sortOrder = values[0] as MatchSortOrder;
        _viewMode = values[1] as MatchViewMode;
      });
    } catch (_) {
      // Sichere Standardwerte bleiben auch ohne verfügbaren Gerätespeicher aktiv.
    }
  }

  Future<void> _selectSortOrder(MatchSortOrder order) async {
    setState(() => _sortOrder = order);
    try {
      await _viewPreferences.saveSortOrder(_preferenceUserId, order);
    } catch (_) {
      // Die Auswahl bleibt für die aktuelle Sitzung trotzdem wirksam.
    }
  }

  Future<void> _selectViewMode(MatchViewMode mode) async {
    setState(() => _viewMode = mode);
    try {
      await _viewPreferences.saveViewMode(_preferenceUserId, mode);
    } catch (_) {
      // Die Auswahl bleibt für die aktuelle Sitzung trotzdem wirksam.
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(matchEventsProvider);
    final repository = ref.watch(repositoryProvider);
    final organization = ref.watch(organizationProvider).valueOrNull;

    Future<void> openCompetitionManagement() async {
      final organization = await ref.read(organizationProvider.future);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => CompetitionManagementDialog(
          repository: repository,
          organization: organization,
          isSystemAdmin:
              ref.read(authProvider).user?.role == UserRole.superAdmin,
          onOrganizationChanged: () {
            ref.invalidate(organizationProvider);
          },
        ),
      );
    }

    Future<void> importSchedule() async {
      final organization = await ref.read(organizationProvider.future);
      if (!context.mounted) return;
      final imported = await showDialog<bool>(
        context: context,
        builder: (context) =>
            CompetitionImportDialog(organization: organization),
      );
      if (imported == true) {
        ref.invalidate(eventsProvider);
        ref.invalidate(matchEventsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Spielplan wurde importiert.')),
          );
        }
      }
    }

    return PageScaffold(
      title: 'Spieltage',
      subtitle: 'Gegner, Wettbewerb und Ergebnisse zentral verwalten.',
      denseMobileHeader: true,
      action: _MatchesPageActions(
        onManageOpponents: openCompetitionManagement,
        onImport: importSchedule,
      ),
      child: events.when(
        data: (items) {
          final now = DateTime.now();
          final matches = items
              .where(
                (event) =>
                    event.type == EventType.match &&
                    event.parentTournamentId == null,
              )
              .toList()
            ..sort((a, b) {
              final byDate = compareMatchOverviewEvents(
                a,
                b,
                now,
                _sortOrder,
              );
              return byDate != 0 ? byDate : a.title.compareTo(b.title);
            });
          final historyEntry = PastMatchesEntryCard(
            onTap: () => context.push('/trainer/matches/history'),
          );
          if (matches.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                historyEntry,
                const SizedBox(height: 14),
                const EmptyState(
                  icon: Icons.sports_soccer_rounded,
                  title: 'Noch kein Spiel angelegt',
                  message:
                      'Lege unter „Termine“ ein Spiel an, um hier den Spieltag zu planen.',
                ),
              ],
            );
          }
          return Column(
            children: [
              historyEntry,
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MatchOverviewToolbar(
                  sortOrder: _sortOrder,
                  viewMode: _viewMode,
                  onSortChanged: _selectSortOrder,
                  onViewChanged: _selectViewMode,
                ),
              ),
              for (final match in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MatchCard(
                    event: match,
                    viewMode: _viewMode,
                    onOpen: match.category.isTournament
                        ? () => _manageTournament(
                              context,
                              ref,
                              match,
                              repository,
                              organization,
                            )
                        : () => context.push('/trainer/matches/${match.id}'),
                    onDelete: match.capabilities.canDelete
                        ? () => _deleteMatch(context, ref, match)
                        : null,
                    onCancel: match.capabilities.canCancel && !match.isCancelled
                        ? () => _cancelMatch(context, ref, match)
                        : null,
                    onReschedule: match.capabilities.canReschedule &&
                            !match.category.isTournament
                        ? () => _rescheduleMatch(context, ref, match)
                        : null,
                    onEdit: () async {
                      if (match.category.isTournament) {
                        await _manageTournament(
                          context,
                          ref,
                          match,
                          repository,
                          organization,
                        );
                        return;
                      }
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
                          reminder24hEnabled: draft.reminder24hEnabled,
                        );
                        ref.invalidate(eventsProvider);
                        ref.invalidate(matchEventsProvider);
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
      ref.invalidate(matchEventsProvider);
      final refreshed = await ref.read(matchEventsProvider.future);
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
      ref.invalidate(matchEventsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spiel konnte nicht gelöscht werden.')),
        );
      }
    }
  }

  Future<void> _cancelMatch(
    BuildContext context,
    WidgetRef ref,
    EventModel event,
  ) async {
    final reason = TextEditingController();
    try {
      final preview =
          await ref.read(repositoryProvider).cancelMatchPreview(event.id);
      if (!context.mounted) return;
      final recipientCount = preview['recipientCount'] as int? ?? 0;
      final playerCount = preview['playerCount'] as int? ?? 0;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.event_busy_rounded, color: Colors.redAccent),
          title: const Text('Spiel verbindlich absagen?'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Das Spiel bleibt sichtbar und wird klar als abgesagt markiert. '
                  '$playerCount Spieler sowie $recipientCount berechtigte Empfänger werden informiert.',
                ),
                const SizedBox(height: 12),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_active_rounded),
                  title: Text('In-App und Push sind verpflichtend'),
                  subtitle: Text(
                      'Offene Rückmeldungen und geplante Erinnerungen werden geschlossen.'),
                ),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Absagegrund *',
                    hintText: 'z. B. Platz nicht bespielbar',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Zurück')),
            FilledButton.icon(
              onPressed: () {
                if (reason.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              icon: const Icon(Icons.event_busy_rounded),
              label: const Text('Spiel absagen'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final result = await ref.read(repositoryProvider).cancelMatch(
            eventId: event.id,
            reason: reason.text.trim(),
          );
      ref.invalidate(eventsProvider);
      ref.invalidate(matchEventsProvider);
      if (context.mounted) {
        final delivery = result['delivery'] as Map<String, dynamic>?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Spiel abgesagt · ${delivery?['recipients'] ?? recipientCount} Empfänger informiert.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spiel konnte nicht abgesagt werden: $error')),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  Future<OpponentClubModel?> _createOpponentClub(
    BuildContext context,
    DataRepository repository,
  ) async {
    final club = TextEditingController();
    final venue = TextEditingController();
    final address = TextEditingController();
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ResponsiveFormDialog(
          title: 'Gegnerischen Verein hinzufügen',
          subtitle:
              'Vereinsdaten, Wappen und Spielstätte sind anschließend für alle Jugenden verfügbar.',
          maxWidth: 560,
          onSave: () {
            if (club.text.trim().isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Bitte den Vereinsnamen angeben.'),
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
      return repository.saveOpponentClub(
        name: club.text.trim(),
        venue: venue.text.trim(),
        address: address.text.trim(),
      );
    } finally {
      club.dispose();
      venue.dispose();
      address.dispose();
    }
  }

  Future<OpponentModel?> _createTournamentOpponent(
    BuildContext context,
    DataRepository repository,
    TeamSummary team,
    List<OpponentModel> opponents,
    List<OpponentClubModel> clubs,
  ) async {
    final draft = await showDialog<_TournamentOpponentDraft>(
      context: context,
      builder: (context) => _TournamentOpponentEditorDialog(
        ageGroup: team.ageGroup,
      ),
    );
    if (draft == null || !context.mounted) return null;

    final designation = _canonicalOpponentDesignation(
      draft.teamDesignation,
      team.ageGroup,
    );
    var clubName = draft.clubName.trim();
    clubName = clubName.replaceFirst(
      RegExp(
        '\\s+${RegExp.escape(designation)}' r'$',
        caseSensitive: false,
      ),
      '',
    );
    if (clubName.isEmpty) clubName = draft.clubName.trim();

    try {
      var club = clubs
          .where(
            (item) =>
                _normalizedOpponentClubName(item.name) ==
                _normalizedOpponentClubName(clubName),
          )
          .firstOrNull;
      if (club == null) {
        club = await repository.saveOpponentClub(name: clubName);
        clubs.add(club);
        clubs.sort((a, b) => a.name.compareTo(b.name));
      }

      final existing = opponents
          .where(
            (item) =>
                item.opponentClubId == club!.id &&
                _canonicalOpponentDesignation(
                      item.teamDesignation,
                      team.ageGroup,
                    ) ==
                    designation,
          )
          .firstOrNull;
      if (existing != null) return existing;

      return await repository.saveOpponent(
        ageGroupId: team.ageGroup.id,
        teamId: team.id,
        opponentClubId: club.id,
        clubName: club.name,
        teamDesignation: designation,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Gegner konnte nicht angelegt werden: $error')),
        );
      }
      return null;
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
    ref.invalidate(matchEventsProvider);
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
    var opponentClubs = ageGroupId == null
        ? <OpponentClubModel>[]
        : await repository.opponentClubs().catchError(
              (_) => <OpponentClubModel>[],
            );
    if (!context.mounted) {
      opponent.dispose();
      return null;
    }
    String? selectedOpponentId = details?.opponentId;
    final storedOpponent =
        opponents.where((item) => item.id == selectedOpponentId).firstOrNull;
    String? selectedOpponentClubId = storedOpponent?.opponentClubId;
    String? selectedTeamDesignation = storedOpponent == null
        ? null
        : _canonicalOpponentDesignation(
            storedOpponent.teamDesignation,
            team?.ageGroup,
          );
    if (selectedOpponentClubId == null && opponent.text.trim().isNotEmpty) {
      final legacyClub = opponentClubs
          .where((item) => opponent.text.trim().startsWith(item.name))
          .toList()
        ..sort((a, b) => b.name.length.compareTo(a.name.length));
      if (legacyClub.isNotEmpty) {
        selectedOpponentClubId = legacyClub.first.id;
        final suffix =
            opponent.text.trim().substring(legacyClub.first.name.length).trim();
        selectedTeamDesignation = suffix.isEmpty
            ? null
            : _canonicalOpponentDesignation(suffix, team?.ageGroup);
      }
    }
    String? competition = footballCompetitionForEvent(
      category: event.category,
      storedCompetition: details?.competition,
    );
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
    var reminder24hEnabled =
        event.reminderPushEnabled && event.reminderMinutes.contains(1440);
    var savingOpponent = false;

    final result = await showDialog<_MatchDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> save() async {
            if (ageGroupId == null ||
                selectedOpponentClubId == null ||
                selectedTeamDesignation == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bitte Verein und Jugendmannschaft auswählen.'),
                ),
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
            if (savingOpponent) return;
            setState(() => savingOpponent = true);
            try {
              var selectedOpponent = opponents
                  .where(
                    (item) =>
                        item.opponentClubId == selectedOpponentClubId &&
                        _canonicalOpponentDesignation(
                              item.teamDesignation,
                              team?.ageGroup,
                            ) ==
                            selectedTeamDesignation,
                  )
                  .firstOrNull;
              if (selectedOpponent == null) {
                final club = opponentClubs
                    .where((item) => item.id == selectedOpponentClubId)
                    .first;
                selectedOpponent = await repository.saveOpponent(
                  ageGroupId: ageGroupId,
                  teamId: team?.id,
                  opponentClubId: club.id,
                  clubName: club.name,
                  teamDesignation: selectedTeamDesignation!,
                );
                opponents = [...opponents, selectedOpponent];
              }
              selectedOpponentId = selectedOpponent.id;
              opponent.text = selectedOpponent.displayName;
              if (!context.mounted) return;
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
                  reminder24hEnabled: reminder24hEnabled,
                ),
              );
            } catch (error) {
              if (!context.mounted) return;
              setState(() => savingOpponent = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('Gegner konnte nicht gespeichert werden: $error'),
                ),
              );
            }
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
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedOpponentClubId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Verein *',
                            helperText: 'Jugendübergreifender Vereins-Pool',
                          ),
                          items: [
                            for (final club in opponentClubs)
                              DropdownMenuItem(
                                value: club.id,
                                child: Row(
                                  children: [
                                    TeamCrest.opponent(
                                      size: 24,
                                      logoUrl: club.logoUrl,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        club.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedOpponentClubId = value;
                              final existing = opponents
                                  .where((item) => item.opponentClubId == value)
                                  .toList();
                              selectedTeamDesignation = existing.length == 1
                                  ? existing.first.teamDesignation
                                  : null;
                              selectedOpponentId = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Verein zum gemeinsamen Pool hinzufügen',
                        onPressed: () async {
                          final created = await _createOpponentClub(
                            context,
                            repository,
                          );
                          if (created == null) return;
                          setState(() {
                            opponentClubs = [...opponentClubs, created]
                              ..sort((a, b) => a.name.compareTo(b.name));
                            selectedOpponentClubId = created.id;
                            selectedTeamDesignation = null;
                          });
                        },
                        icon: const Icon(Icons.add_business_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      '$selectedOpponentClubId:$selectedTeamDesignation',
                    ),
                    initialValue: selectedTeamDesignation,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText:
                          '${team?.ageGroup.name ?? 'Jugend'}‑Mannschaft *',
                      helperText:
                          'Nur diese Jugend wird angelegt und von ihrem Trainerteam verwaltet.',
                    ),
                    items: [
                      for (final designation in _opponentDesignationOptions(
                        team?.ageGroup,
                        opponents.where(
                          (item) =>
                              item.opponentClubId == selectedOpponentClubId,
                        ),
                      ))
                        DropdownMenuItem(
                          value: designation,
                          child: Text(designation),
                        ),
                    ],
                    onChanged: selectedOpponentClubId == null
                        ? null
                        : (value) => setState(() {
                              selectedTeamDesignation = value;
                              selectedOpponentId = null;
                            }),
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
                        decoration: InputDecoration(
                          labelText: 'Tore ${event.ownTeamShortName}',
                        ),
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
                title: 'Automatische Erinnerung',
                subtitle:
                    'Gilt für Liga, Freundschaftsspiel, Turnier und alle weiteren Spielformen.',
                icon: Icons.notifications_active_outlined,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: reminder24hEnabled,
                    onChanged: (value) =>
                        setState(() => reminder24hEnabled = value),
                    title: const Text('24 Stunden vorher erinnern'),
                    subtitle: const Text(
                      'Sendet automatisch eine Push- und In-App-Erinnerung an die relevanten Eltern und Spieler.',
                    ),
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

  Future<void> _manageTournament(
    BuildContext context,
    WidgetRef ref,
    EventModel tournament,
    DataRepository repository,
    OrganizationContext? organization,
  ) async {
    final team = organization?.teams
        .where((item) => item.id == tournament.teamId)
        .firstOrNull;
    if (team == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mannschaftsdaten sind noch nicht geladen.')),
      );
      return;
    }
    var opponents = await repository.opponents(team.ageGroup.id).catchError(
          (_) => <OpponentModel>[],
        );
    final opponentClubs = await repository.opponentClubs().catchError(
          (_) => <OpponentClubModel>[],
        );
    if (!context.mounted) return;
    final rows = tournament.tournamentFixtures.map((fixture) {
      final details = fixture.matchDetails;
      final stored = opponents
          .where((opponent) => opponent.id == details?.opponentId)
          .firstOrNull;
      final byName = stored ??
          opponents
              .where((opponent) => opponent.displayName == details?.opponent)
              .firstOrNull;
      return _TournamentFixtureDraftState(
        id: fixture.id,
        opponentId: byName?.id,
        startAt: fixture.startAt,
        isHome: details?.isHome ?? true,
        periodCount: details?.periodCount ?? 1,
        periodMinutes: details?.periodMinutes ?? 10,
        familyReleasedAt: fixture.familyReleasedAt,
      );
    }).toList();
    var saving = false;
    final releasingFixtureIds = <String>{};
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> chooseStart(_TournamentFixtureDraftState row) async {
            final date = await showDatePicker(
              context: dialogContext,
              initialDate: row.startAt,
              firstDate: DateTime(
                tournament.startAt.year,
                tournament.startAt.month,
                tournament.startAt.day,
              ),
              lastDate: DateTime(
                (tournament.endAt ?? tournament.startAt).year,
                (tournament.endAt ?? tournament.startAt).month,
                (tournament.endAt ?? tournament.startAt).day,
              ),
            );
            if (date == null || !dialogContext.mounted) return;
            final time = await showTimePicker(
              context: dialogContext,
              initialTime: TimeOfDay.fromDateTime(row.startAt),
            );
            if (time == null) return;
            setDialogState(() {
              row.startAt = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
            });
          }

          Future<void> releaseFixture(
            _TournamentFixtureDraftState row,
          ) async {
            final fixtureId = row.id;
            if (fixtureId == null || releasingFixtureIds.contains(fixtureId)) {
              return;
            }
            setDialogState(() => releasingFixtureIds.add(fixtureId));
            try {
              final preview = await repository.familyReleasePreview(fixtureId);
              if (!dialogContext.mounted) return;
              final requiresFullTeam =
                  preview['audienceMode'] == 'FULL_TEAM_REQUIRED';
              final kickoff = row.startAt.toLocal();
              final kickoffLabel = '${kickoff.day.toString().padLeft(2, '0')}.'
                  '${kickoff.month.toString().padLeft(2, '0')}. '
                  '${kickoff.hour.toString().padLeft(2, '0')}:'
                  '${kickoff.minute.toString().padLeft(2, '0')} Uhr';
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmationContext) => AlertDialog(
                  title: const Text('Partie für Familien freigeben?'),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Die Partie erscheint danach direkt in der '
                            'Turnierübersicht von Eltern und Spielern.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Text(
                              'Gegner: ${preview['opponent'] ?? 'Noch offen'}'),
                          Text('Anstoß: $kickoffLabel'),
                          Text(
                            'Empfänger: ${preview['recipients'] ?? 0} Benutzer',
                          ),
                          Text(
                            requiresFullTeam
                                ? 'Empfängerkreis: gesamte Mannschaft'
                                : 'Empfängerkreis: nominierter Kader',
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Es werden eine In-App- und eine Pushnachricht '
                            'versendet.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(confirmationContext, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(confirmationContext, true),
                      icon: const Icon(Icons.family_restroom_rounded),
                      label: const Text('Jetzt freigeben'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !dialogContext.mounted) return;
              await repository.releaseMatchToFamilies(
                fixtureId,
                fullTeam: requiresFullTeam,
              );
              if (!dialogContext.mounted) return;
              setDialogState(() => row.familyReleasedAt = DateTime.now());
              ref.invalidate(eventsProvider);
              ref.invalidate(matchEventsProvider);
              ref.invalidate(personalResponsesProvider);
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Partie ist jetzt für Eltern und Spieler sichtbar.',
                  ),
                ),
              );
            } on DioException catch (error) {
              if (!dialogContext.mounted) return;
              final data = error.response?.data;
              final message = data is Map<String, dynamic>
                  ? data['message'] as String?
                  : null;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    message ?? 'Die Partie konnte nicht freigegeben werden.',
                  ),
                ),
              );
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => releasingFixtureIds.remove(fixtureId));
              }
            }
          }

          Future<void> save() async {
            if (rows.any((row) => row.opponentId == null)) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content:
                      Text('Bitte für jede Partie einen Gegner auswählen.'),
                ),
              );
              return;
            }
            if (saving) return;
            setDialogState(() => saving = true);
            try {
              await repository.syncTournamentFixtures(
                tournamentId: tournament.id,
                fixtures: rows
                    .map(
                      (row) => TournamentFixtureWriteData(
                        id: row.id,
                        opponentId: row.opponentId!,
                        startAt: row.startAt,
                        isHome: row.isHome,
                        periodCount: row.periodCount,
                        periodMinutes: row.periodMinutes,
                      ),
                    )
                    .toList(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } on DioException catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() => saving = false);
              final data = error.response?.data;
              final message = data is Map<String, dynamic>
                  ? data['message'] as String?
                  : null;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(message ??
                      'Turnierplan konnte nicht gespeichert werden.'),
                ),
              );
            }
          }

          return ResponsiveFormDialog(
            title: 'Turnierplan',
            subtitle:
                '${tournament.title} · Gegner und Anstoßzeit je Partie festlegen.',
            maxWidth: 760,
            saveLabel: saving ? 'Speichert …' : 'Speichern',
            preferInlineActions: true,
            onSave: saving ? null : save,
            children: [
              _TournamentPlanToolbar(
                count: rows.length,
                onAdd: () {
                  var startAt = tournament.startAt.add(
                    Duration(minutes: rows.length * 20),
                  );
                  final latest = tournament.endAt ??
                      tournament.startAt.add(const Duration(hours: 24));
                  if (startAt.isAfter(latest)) startAt = tournament.startAt;
                  setDialogState(() {
                    rows.add(
                      _TournamentFixtureDraftState(
                        startAt: startAt,
                        periodCount: 1,
                        periodMinutes: 10,
                      ),
                    );
                  });
                },
              ),
              const SizedBox(height: 10),
              _TournamentPlanningAccessCard(
                onOpen: () {
                  Navigator.pop(dialogContext, false);
                  context.push(
                    '/trainer/matches/${tournament.id}?planning=tournament',
                  );
                },
              ),
              if (rows.isEmpty) const _CompactTournamentEmptyState(),
              for (var index = 0; index < rows.length; index++) ...[
                _TournamentFixtureEditor(
                  key: ValueKey(rows[index].id ?? 'new-$index'),
                  index: index,
                  row: rows[index],
                  ownTeamName: team.playingShortName,
                  opponents: opponents,
                  onAddOpponent: () async {
                    final created = await _createTournamentOpponent(
                      dialogContext,
                      repository,
                      team,
                      opponents,
                      opponentClubs,
                    );
                    if (created != null && dialogContext.mounted) {
                      setDialogState(() {
                        opponents = [...opponents, created]..sort(
                            (a, b) => a.displayName.compareTo(b.displayName),
                          );
                      });
                    }
                    return created;
                  },
                  onChanged: () => setDialogState(() {}),
                  onChooseStart: () => chooseStart(rows[index]),
                  onOpen: rows[index].id == null
                      ? null
                      : () {
                          final fixtureId = rows[index].id!;
                          Navigator.pop(dialogContext, false);
                          context.push('/trainer/matches/$fixtureId');
                        },
                  onRelease: rows[index].id == null ||
                          rows[index].familyReleasedAt != null
                      ? null
                      : () => releaseFixture(rows[index]),
                  releaseBusy: rows[index].id != null &&
                      releasingFixtureIds.contains(rows[index].id),
                  onRemove: () => setDialogState(() => rows.removeAt(index)),
                ),
                if (index < rows.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
    if (saved == true) {
      ref.invalidate(eventsProvider);
      ref.invalidate(matchEventsProvider);
      await ref.read(matchEventsProvider.future);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnierpartien wurden gespeichert.')),
        );
      }
    }
  }
}

class _MatchesPageActions extends StatelessWidget {
  const _MatchesPageActions({
    required this.onManageOpponents,
    required this.onImport,
  });

  final VoidCallback onManageOpponents;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppBreakpoints.medium;
          final veryNarrow = constraints.maxWidth < AppBreakpoints.veryNarrow;
          final narrow = constraints.maxWidth < AppBreakpoints.narrow;
          return Row(
            key: const ValueKey('matches-page-actions'),
            mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (compact)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onManageOpponents,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.emoji_events_outlined, size: 18),
                    label: AdaptiveButtonLabel(
                      narrow ? 'Gegner' : 'Liga & Gegner',
                      maxLines: 1,
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: onManageOpponents,
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Liga & Gegner'),
                ),
              const SizedBox(width: 8),
              if (compact)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onImport,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: AdaptiveButtonLabel(
                      veryNarrow
                          ? 'Import'
                          : narrow
                              ? 'Importieren'
                              : 'Spielplan importieren',
                      maxLines: 1,
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Spielplan importieren'),
                ),
            ],
          );
        },
      );
}

String _matchSortLabel(MatchSortOrder order) => switch (order) {
      MatchSortOrder.nextFirst => 'Nächste zuerst',
      MatchSortOrder.newestFirst => 'Neueste zuerst',
      MatchSortOrder.oldestFirst => 'Älteste zuerst',
    };

String _matchViewLabel(MatchViewMode mode) => switch (mode) {
      MatchViewMode.veryCompact => 'Kompakt',
      MatchViewMode.standard => 'Normal',
      MatchViewMode.detailed => 'Detailliert',
    };

IconData _matchViewIcon(MatchViewMode mode) => switch (mode) {
      MatchViewMode.veryCompact => Icons.view_headline_rounded,
      MatchViewMode.standard => Icons.view_stream_outlined,
      MatchViewMode.detailed => Icons.subject_rounded,
    };

class _MatchOverviewToolbar extends StatelessWidget {
  const _MatchOverviewToolbar({
    required this.sortOrder,
    required this.viewMode,
    required this.onSortChanged,
    required this.onViewChanged,
  });

  final MatchSortOrder sortOrder;
  final MatchViewMode viewMode;
  final ValueChanged<MatchSortOrder> onSortChanged;
  final ValueChanged<MatchViewMode> onViewChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final veryNarrow = constraints.maxWidth < 380;
          return Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                _MatchToolbarMenu<MatchSortOrder>(
                  menuKey: const ValueKey('match-sort-menu'),
                  icon: Icons.sort_rounded,
                  label: _matchSortLabel(sortOrder),
                  triggerLabel: veryNarrow ? 'Sortierung' : null,
                  values: MatchSortOrder.values,
                  selected: sortOrder,
                  itemLabel: _matchSortLabel,
                  onSelected: onSortChanged,
                ),
                _MatchToolbarMenu<MatchViewMode>(
                  menuKey: const ValueKey('match-view-menu'),
                  icon: _matchViewIcon(viewMode),
                  label: _matchViewLabel(viewMode),
                  triggerLabel: veryNarrow ? '' : null,
                  values: MatchViewMode.values,
                  selected: viewMode,
                  itemLabel: _matchViewLabel,
                  itemIcon: _matchViewIcon,
                  onSelected: onViewChanged,
                ),
              ],
            ),
          );
        },
      );
}

class _MatchToolbarMenu<T> extends StatelessWidget {
  const _MatchToolbarMenu({
    required this.menuKey,
    required this.icon,
    required this.label,
    required this.values,
    required this.selected,
    required this.itemLabel,
    required this.onSelected,
    this.triggerLabel,
    this.itemIcon,
  });

  final Key menuKey;
  final IconData icon;
  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) itemLabel;
  final IconData Function(T value)? itemIcon;
  final ValueChanged<T> onSelected;
  final String? triggerLabel;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        key: menuKey,
        tooltip: label,
        initialValue: selected,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final value in values)
            PopupMenuItem<T>(
              value: value,
              child: Row(
                children: [
                  Icon(itemIcon?.call(value) ?? Icons.sort_rounded, size: 19),
                  const SizedBox(width: 9),
                  Expanded(child: Text(itemLabel(value))),
                  if (value == selected)
                    const Icon(Icons.check_rounded, size: 19),
                ],
              ),
            ),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: context.appColors.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19),
              if (triggerLabel != '') ...[
                const SizedBox(width: 7),
                Text(
                  triggerLabel ?? label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, size: 20),
            ],
          ),
        ),
      );
}

class _TournamentOpponentDraft {
  const _TournamentOpponentDraft({
    required this.clubName,
    required this.teamDesignation,
  });

  final String clubName;
  final String teamDesignation;
}

class _TournamentOpponentEditorDialog extends StatefulWidget {
  const _TournamentOpponentEditorDialog({required this.ageGroup});

  final AgeGroupSummary ageGroup;

  @override
  State<_TournamentOpponentEditorDialog> createState() =>
      _TournamentOpponentEditorDialogState();
}

class _TournamentOpponentEditorDialogState
    extends State<_TournamentOpponentEditorDialog> {
  late final TextEditingController club;
  late final TextEditingController designation;

  String get agePrefix {
    final compact = widget.ageGroup.code
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-ZÄÖÜ]'), '');
    return compact.isEmpty ? '' : compact[0];
  }

  @override
  void initState() {
    super.initState();
    club = TextEditingController();
    designation = TextEditingController(text: '${agePrefix}1');
  }

  @override
  void dispose() {
    club.dispose();
    designation.dispose();
    super.dispose();
  }

  void save() {
    final clubName = club.text.trim();
    final teamDesignation = canonicalYouthTeamDesignation(
      designation.text,
      ageCode: widget.ageGroup.code,
    );
    final designationValid = agePrefix.isNotEmpty &&
        RegExp('^${RegExp.escape(agePrefix)}[1-9][0-9]?' r'$')
            .hasMatch(teamDesignation);
    if (clubName.isEmpty || !designationValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clubName.isEmpty
                ? 'Bitte den Vereinsnamen angeben.'
                : 'Bitte eine Mannschaft wie ${agePrefix}1 angeben.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _TournamentOpponentDraft(
        clubName: clubName,
        teamDesignation: teamDesignation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ResponsiveFormDialog(
        title: 'Gegner hinzufügen',
        subtitle:
            'Neue Mannschaft direkt für die ${widget.ageGroup.name} anlegen und auswählen.',
        maxWidth: 560,
        preferInlineActions: true,
        saveLabel: 'Hinzufügen',
        saveIcon: Icons.add_rounded,
        onSave: save,
        children: [
          TextField(
            key: const ValueKey('tournament-opponent-club-name'),
            controller: club,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Verein *',
              hintText: 'z. B. ATSV Kelheim',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('tournament-opponent-designation'),
            controller: designation,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => save(),
            decoration: InputDecoration(
              labelText: '${widget.ageGroup.name}-Mannschaft *',
              hintText: '${agePrefix}1',
              helperText:
                  'Nur die Mannschaftsbezeichnung, z. B. ${agePrefix}1 oder ${agePrefix}2.',
            ),
          ),
        ],
      );
}

class _TournamentFixtureDraftState {
  _TournamentFixtureDraftState({
    required this.startAt,
    required this.periodCount,
    required this.periodMinutes,
    this.id,
    this.opponentId,
    this.isHome = true,
    this.familyReleasedAt,
  });

  final String? id;
  String? opponentId;
  DateTime startAt;
  bool isHome;
  int periodCount;
  int periodMinutes;
  DateTime? familyReleasedAt;
}

class _TournamentPlanToolbar extends StatelessWidget {
  const _TournamentPlanToolbar({
    required this.count,
    required this.onAdd,
  });

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppBreakpoints.compact;
          return Container(
            key: const ValueKey('tournament-plan-toolbar'),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 9 : 12,
            ),
            decoration: BoxDecoration(
              color: context.appColors.brandSoft,
              borderRadius: BorderRadius.circular(compact ? 14 : 18),
              border: Border.all(color: context.appColors.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events_rounded,
                  size: compact ? 20 : 24,
                  color: context.appWarning,
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$count ${count == 1 ? 'Partie' : 'Partien'}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      Text(
                        compact
                            ? 'Gegner suchen oder direkt neu anlegen.'
                            : 'Gegner durchsuchen oder direkt in der Auswahl neu anlegen.',
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 14,
                      vertical: compact ? 8 : 10,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: Text(compact ? 'Partie' : 'Partie hinzufügen'),
                ),
              ],
            ),
          );
        },
      );
}

class _CompactTournamentEmptyState extends StatelessWidget {
  const _CompactTournamentEmptyState();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('tournament-plan-empty-state'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appColors.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.appInfo.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.sports_soccer_outlined,
                size: 21,
                color: context.appInfo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Noch keine Partie',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    'Über „+ Partie“ die erste Begegnung hinzufügen.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TournamentPlanningAccessCard extends StatelessWidget {
  const _TournamentPlanningAccessCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final description = Text(
            'Ein Kader und eine Grundaufstellung für das gesamte Turnier. '
            'Einzelne Partien können optional separat geplant werden.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.textMuted,
                ),
          );
          final action = FilledButton.icon(
            key: const ValueKey('open-tournament-planning'),
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            label: Text(compact ? 'Öffnen' : 'Kader & Aufstellung öffnen'),
          );
          return Container(
            key: const ValueKey('tournament-planning-access-card'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.appColors.outline),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.groups_rounded, color: context.appWarning),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'Turnier-Kader & Aufstellung',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      description,
                      const SizedBox(height: 9),
                      action,
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.groups_rounded,
                        color: context.appWarning,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Turnier-Kader & Aufstellung',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            description,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      action,
                    ],
                  ),
          );
        },
      );
}

class _TournamentFixtureEditor extends StatelessWidget {
  const _TournamentFixtureEditor({
    super.key,
    required this.index,
    required this.row,
    required this.ownTeamName,
    required this.opponents,
    required this.onAddOpponent,
    required this.onChanged,
    required this.onChooseStart,
    required this.onRemove,
    this.onOpen,
    this.onRelease,
    this.releaseBusy = false,
  });

  final int index;
  final _TournamentFixtureDraftState row;
  final String ownTeamName;
  final List<OpponentModel> opponents;
  final TournamentOpponentCreator onAddOpponent;
  final VoidCallback onChanged;
  final VoidCallback onChooseStart;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;
  final VoidCallback? onRelease;
  final bool releaseBusy;

  @override
  Widget build(BuildContext context) {
    final local = row.startAt.toLocal();
    final startLabel =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}. '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} Uhr';
    const compactDecoration = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
    final periodCountField = DropdownButtonFormField<int>(
      initialValue: row.periodCount,
      isExpanded: true,
      decoration: compactDecoration.copyWith(labelText: 'Abschnitte'),
      items: [
        for (var value = 1; value <= 4; value++)
          DropdownMenuItem(value: value, child: Text('$value')),
      ],
      onChanged: (value) {
        if (value == null) return;
        row.periodCount = value;
        onChanged();
      },
    );
    final periodMinutesField = DropdownButtonFormField<int>(
      initialValue: row.periodMinutes,
      isExpanded: true,
      decoration: compactDecoration.copyWith(labelText: 'Min./Abschnitt'),
      items: const [
        DropdownMenuItem(value: 8, child: Text('8 Min.')),
        DropdownMenuItem(value: 10, child: Text('10 Min.')),
        DropdownMenuItem(value: 12, child: Text('12 Min.')),
        DropdownMenuItem(value: 15, child: Text('15 Min.')),
        DropdownMenuItem(value: 20, child: Text('20 Min.')),
        DropdownMenuItem(value: 25, child: Text('25 Min.')),
        DropdownMenuItem(value: 30, child: Text('30 Min.')),
      ],
      onChanged: (value) {
        if (value == null) return;
        row.periodMinutes = value;
        onChanged();
      },
    );
    final orderField = DropdownButtonFormField<bool>(
      initialValue: row.isHome,
      isExpanded: true,
      decoration: compactDecoration.copyWith(labelText: 'Anzeige'),
      items: [
        DropdownMenuItem(
          value: true,
          child: Text('$ownTeamName zuerst'),
        ),
        const DropdownMenuItem(value: false, child: Text('Gegner zuerst')),
      ],
      onChanged: (value) {
        if (value == null) return;
        row.isHome = value;
        onChanged();
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Card(
          key: ValueKey('tournament-fixture-$index'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(compact ? 9 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: compact ? 15 : 20,
                      child: Text('${index + 1}'),
                    ),
                    SizedBox(width: compact ? 8 : 10),
                    Expanded(
                      child: Text(
                        compact
                            ? 'Partie ${index + 1}'
                            : 'Turnierspiel ${index + 1}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Partie entfernen',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline_rounded, size: 21),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 6 : 8),
                TournamentOpponentPickerField(
                  key: ValueKey('tournament-opponent-field-$index'),
                  opponentId: row.opponentId,
                  opponents: opponents,
                  onAddOpponent: onAddOpponent,
                  onChanged: (value) {
                    row.opponentId = value;
                    onChanged();
                  },
                ),
                SizedBox(height: compact ? 8 : 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onChooseStart,
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                    ),
                    icon: const Icon(Icons.schedule_rounded, size: 20),
                    label: Text(
                      startLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (compact) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: periodCountField),
                      const SizedBox(width: 8),
                      Expanded(child: periodMinutesField),
                    ],
                  ),
                  const SizedBox(height: 8),
                  orderField,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: periodCountField),
                      const SizedBox(width: 10),
                      Expanded(child: periodMinutesField),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: orderField),
                    ],
                  ),
                if (onOpen != null) ...[
                  SizedBox(height: compact ? 9 : 12),
                  const Divider(height: 1),
                  SizedBox(height: compact ? 8 : 10),
                  if (compact) ...[
                    if (row.familyReleasedAt != null)
                      const _TournamentFixtureReleaseStatus(),
                    if (onRelease != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          key: ValueKey(
                            'tournament-fixture-release-$index',
                          ),
                          onPressed: releaseBusy ? null : onRelease,
                          icon: releaseBusy
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.family_restroom_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            releaseBusy
                                ? 'Wird freigegeben …'
                                : 'Für Familien freigeben',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: ValueKey('tournament-fixture-open-$index'),
                        onPressed: onOpen,
                        icon: const Icon(Icons.stadium_rounded, size: 18),
                        label: const Text('Partie öffnen'),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        if (row.familyReleasedAt != null)
                          const _TournamentFixtureReleaseStatus(),
                        if (onRelease != null)
                          FilledButton.tonalIcon(
                            key: ValueKey(
                              'tournament-fixture-release-$index',
                            ),
                            onPressed: releaseBusy ? null : onRelease,
                            icon: releaseBusy
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.family_restroom_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              releaseBusy
                                  ? 'Wird freigegeben …'
                                  : 'Für Familien freigeben',
                            ),
                          ),
                        const Spacer(),
                        OutlinedButton.icon(
                          key: ValueKey('tournament-fixture-open-$index'),
                          onPressed: onOpen,
                          icon: const Icon(Icons.stadium_rounded, size: 18),
                          label: const Text('Partie öffnen'),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TournamentFixtureReleaseStatus extends StatelessWidget {
  const _TournamentFixtureReleaseStatus();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('tournament-fixture-release-status'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: context.appSuccess.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.appSuccess.withValues(alpha: .35),
          ),
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.verified_rounded, size: 18, color: context.appSuccess),
            Text(
              'Für Familien sichtbar',
              style: TextStyle(
                color: context.appSuccess,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.event,
    required this.viewMode,
    required this.onEdit,
    required this.onOpen,
    this.onDelete,
    this.onCancel,
    this.onReschedule,
  });
  final EventModel event;
  final MatchViewMode viewMode;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;

  @override
  Widget build(BuildContext context) {
    final details = event.matchDetails;
    final date = event.startAt.toLocal();
    final isTournament = event.category.isTournament;
    final tournamentPlan = event.meinTurnierplanAttachment;
    final openTournamentPlan =
        tournamentPlan == null || !isMeinTurnierplanUrl(tournamentPlan.url)
            ? null
            : () => openTournamentPlanBrowser(
                  context,
                  url: tournamentPlan.url,
                  tournamentName: event.title,
                );
    final displayScore = event.fixtureDisplayScore;
    final hasResult = displayScore != null;
    final isFriendly = event.category == EventCategory.friendlyMatch ||
        (details?.competition ?? '').toLowerCase().contains('freundschaft');
    return Card(
      key: ValueKey('match-card-${event.id}'),
      margin: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final responsiveCompact =
              constraints.maxWidth < (openTournamentPlan == null ? 680 : 960);
          final compact =
              responsiveCompact || viewMode == MatchViewMode.veryCompact;
          final title = event.fixtureDisplayTitle;
          final dateLocation = [
            '${date.day}.${date.month}.${date.year}',
            if (event.location.trim().isNotEmpty) event.location.trim(),
          ].join(' · ');
          final information = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: (compact
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (event.matchVenueType != null) ...[
                    const SizedBox(width: 7),
                    MatchVenueBadge(
                      type: event.matchVenueType!,
                      compact: true,
                    ),
                  ],
                ],
              ),
              SizedBox(height: compact ? 1 : 4),
              Text(
                dateLocation,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: compact
                    ? Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                        )
                    : null,
              ),
              if (details?.competition?.isNotEmpty == true)
                Padding(
                  padding: EdgeInsets.only(top: compact ? 3 : 5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isFriendly
                          ? context.appColors.brandSoft
                          : context.appInfo.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isFriendly
                            ? AppColors.gold
                            : context.appInfo.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      child: Text(
                        isFriendly
                            ? 'Freundschaftsspiel'
                            : details!.competition!,
                        style: TextStyle(
                          color:
                              isFriendly ? context.appWarning : context.appInfo,
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 11 : 12,
                        ),
                      ),
                    ),
                  ),
                ),
              if (isTournament && compact) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      size: 15,
                      color: context.appWarning,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${event.category.label} · '
                        '${event.tournamentFixtures.length} '
                        '${event.tournamentFixtures.length == 1 ? 'Partie' : 'Partien'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                if (event.tournamentFixtures.isNotEmpty)
                  Text(
                    event.tournamentFixtures.take(2).map((fixture) {
                      final time = fixture.startAt.toLocal();
                      final opponent =
                          fixture.matchDetails?.opponent ?? 'Gegner offen';
                      return '${time.hour.toString().padLeft(2, '0')}:'
                          '${time.minute.toString().padLeft(2, '0')} $opponent';
                    }).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ] else if (isTournament) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.emoji_events_rounded, size: 16),
                      label: Text(event.category.label),
                    ),
                    Text(
                      '${event.tournamentFixtures.length} '
                      '${event.tournamentFixtures.length == 1 ? 'Partie' : 'Partien'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                if (event.tournamentFixtures.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    event.tournamentFixtures.take(3).map((fixture) {
                      final time = fixture.startAt.toLocal();
                      final opponent =
                          fixture.matchDetails?.opponent ?? 'Gegner offen';
                      return '${time.hour.toString().padLeft(2, '0')}:'
                          '${time.minute.toString().padLeft(2, '0')} $opponent';
                    }).join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
              if (details != null)
                Text(
                  '${details.periodCount} × ${details.periodMinutes} Min. '
                  '· ${details.durationMinutes} Min. gesamt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact ? Theme.of(context).textTheme.bodySmall : null,
                ),
              if (viewMode == MatchViewMode.detailed) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  children: [
                    if (event.meetingAt != null)
                      _MatchDetailChip(
                        icon: Icons.groups_rounded,
                        text:
                            'Treffen ${_timeOnly(event.meetingAt!.toLocal())}',
                      ),
                    _MatchDetailChip(
                      icon: Icons.how_to_reg_rounded,
                      text: '${event.attendanceSummary.yes} Zusagen',
                    ),
                    _MatchDetailChip(
                      icon: Icons.schedule_rounded,
                      text: '${event.attendanceSummary.unknown} offen',
                    ),
                    _MatchDetailChip(
                      icon: event.isCancelled
                          ? Icons.event_busy_rounded
                          : Icons.event_available_rounded,
                      text: event.isCancelled ? 'Abgesagt' : 'Geplant',
                    ),
                  ],
                ),
              ],
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isTournament)
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
              if (onCancel != null)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent),
                  icon: const Icon(Icons.event_busy_rounded, size: 18),
                  label: const Text('Absagen'),
                ),
              if (onDelete != null)
                IconButton.filledTonal(
                  onPressed: onDelete,
                  color: Theme.of(context).colorScheme.error,
                  tooltip: 'Spiel endgültig löschen',
                  icon: const Icon(Icons.delete_forever_rounded),
                ),
              if (openTournamentPlan != null)
                OutlinedButton.icon(
                  key: ValueKey('trainer-tournament-plan-${event.id}'),
                  onPressed: openTournamentPlan,
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text('Live-Turnierplan'),
                ),
              FilledButton.icon(
                onPressed: onOpen,
                icon: Icon(
                  isTournament
                      ? Icons.account_tree_rounded
                      : Icons.stadium_rounded,
                  size: 18,
                ),
                label: Text(
                  isTournament ? 'Partien planen' : 'Spieltag',
                ),
              ),
            ],
          );
          return Padding(
            padding: EdgeInsets.all(
              viewMode == MatchViewMode.veryCompact
                  ? 8
                  : compact
                      ? 10
                      : 20,
            ),
            child: viewMode == MatchViewMode.veryCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _MatchLogos(
                            ownTeamLogoUrl: event.ownTeamLogoUrl,
                            ownTeamIsPlayingCommunity:
                                event.ownTeamIsPlayingCommunity,
                            opponentLogoUrl: details?.opponentLogoUrl,
                            isHome: details?.isHome ?? true,
                            compact: true,
                            tournament: isTournament,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  dateLocation,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: context.appColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (hasResult)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                displayScore,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _CompactMatchActions(
                        isTournament: isTournament,
                        onEdit: onEdit,
                        onOpen: onOpen,
                        onDelete: onDelete,
                        onCancel: onCancel,
                        onReschedule: onReschedule,
                        onOpenTournamentPlan: openTournamentPlan,
                        tournamentId: event.id,
                      ),
                    ],
                  )
                : compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MatchLogos(
                                ownTeamLogoUrl: event.ownTeamLogoUrl,
                                ownTeamIsPlayingCommunity:
                                    event.ownTeamIsPlayingCommunity,
                                opponentLogoUrl: details?.opponentLogoUrl,
                                isHome: details?.isHome ?? true,
                                compact: true,
                                tournament: isTournament,
                              ),
                              const SizedBox(width: 9),
                              Expanded(child: information),
                              if (hasResult) ...[
                                const SizedBox(width: 8),
                                Text(
                                  displayScore,
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 7),
                          _CompactMatchActions(
                            isTournament: isTournament,
                            onEdit: onEdit,
                            onOpen: onOpen,
                            onDelete: onDelete,
                            onCancel: onCancel,
                            onReschedule: onReschedule,
                            onOpenTournamentPlan: openTournamentPlan,
                            tournamentId: event.id,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          _MatchLogos(
                            ownTeamLogoUrl: event.ownTeamLogoUrl,
                            ownTeamIsPlayingCommunity:
                                event.ownTeamIsPlayingCommunity,
                            opponentLogoUrl: details?.opponentLogoUrl,
                            isHome: details?.isHome ?? true,
                            compact: false,
                            tournament: isTournament,
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: information),
                          if (hasResult)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                displayScore,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
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

String _timeOnly(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')} Uhr';

class _MatchDetailChip extends StatelessWidget {
  const _MatchDetailChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: context.appWarning),
            const SizedBox(width: 5),
            Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

class _CompactMatchActions extends StatelessWidget {
  const _CompactMatchActions({
    required this.isTournament,
    required this.onEdit,
    required this.onOpen,
    this.onDelete,
    this.onCancel,
    this.onReschedule,
    this.onOpenTournamentPlan,
    this.tournamentId,
  });

  final bool isTournament;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;
  final VoidCallback? onOpenTournamentPlan;
  final String? tournamentId;

  bool get hasMenuActions =>
      !isTournament ||
      onReschedule != null ||
      onCancel != null ||
      onDelete != null;

  void _select(String action) {
    switch (action) {
      case 'edit':
        onEdit();
        return;
      case 'reschedule':
        onReschedule?.call();
        return;
      case 'cancel':
        onCancel?.call();
        return;
      case 'delete':
        onDelete?.call();
        return;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final showTournamentActions = isTournament &&
              onOpenTournamentPlan == null &&
              constraints.maxWidth >= AppBreakpoints.veryNarrow &&
              textScale < 1.35;
          return Row(
            children: [
              if (showTournamentActions && onCancel != null)
                TextButton.icon(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.event_busy_rounded, size: 17),
                  label: const Text('Absagen'),
                ),
              if (showTournamentActions && onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  color: Theme.of(context).colorScheme.error,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Spiel endgültig löschen',
                  icon: const Icon(Icons.delete_forever_rounded, size: 20),
                ),
              if (!showTournamentActions && hasMenuActions)
                PopupMenuButton<String>(
                  tooltip: 'Weitere Aktionen',
                  onSelected: _select,
                  itemBuilder: (context) => [
                    if (!isTournament)
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_rounded),
                          title: Text('Daten bearbeiten'),
                        ),
                      ),
                    if (onReschedule != null)
                      const PopupMenuItem(
                        value: 'reschedule',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.event_repeat_rounded),
                          title: Text('Verlegen'),
                        ),
                      ),
                    if (onCancel != null)
                      const PopupMenuItem(
                        value: 'cancel',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.event_busy_rounded,
                            color: Colors.redAccent,
                          ),
                          title: Text('Absagen'),
                        ),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_forever_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: const Text('Endgültig löschen'),
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              if (onOpenTournamentPlan != null) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('trainer-tournament-plan-$tournamentId'),
                    onPressed: onOpenTournamentPlan,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: const Text('Live'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (onOpenTournamentPlan == null) const Spacer(),
              if (onOpenTournamentPlan != null)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.account_tree_rounded, size: 17),
                    label: const Text('Planen'),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                  ),
                  icon: Icon(
                    isTournament
                        ? Icons.account_tree_rounded
                        : Icons.stadium_rounded,
                    size: 17,
                  ),
                  label: Text(isTournament ? 'Planen' : 'Spieltag'),
                ),
            ],
          );
        },
      );
}

class _MatchLogos extends StatelessWidget {
  const _MatchLogos({
    required this.ownTeamLogoUrl,
    required this.ownTeamIsPlayingCommunity,
    required this.opponentLogoUrl,
    required this.isHome,
    required this.compact,
    this.tournament = false,
  });
  final String? ownTeamLogoUrl;
  final bool ownTeamIsPlayingCommunity;
  final String? opponentLogoUrl;
  final bool isHome;
  final bool compact;
  final bool tournament;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 42.0;
    final ownCrest = TeamCrest.ownTeam(
      size: size,
      logoUrl: ownTeamLogoUrl,
      isPlayingCommunity: ownTeamIsPlayingCommunity,
    );
    final opponentCrest = TeamCrest.opponent(
      size: size,
      logoUrl: opponentLogoUrl,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!tournament && !isHome) opponentCrest else ownCrest,
        const SizedBox(width: 5),
        if (tournament)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: context.appColors.brandSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.emoji_events_rounded, color: context.appWarning),
          )
        else if (isHome)
          opponentCrest
        else
          ownCrest,
      ],
    );
  }
}

List<String> _opponentDesignationOptions(
  AgeGroupSummary? ageGroup,
  Iterable<OpponentModel> existing,
) {
  if (ageGroup == null) return const [];
  final prefixSource =
      ageGroup.code.toUpperCase().replaceAll(RegExp(r'[^A-ZÄÖÜ]'), '');
  final prefix =
      prefixSource.isEmpty ? ageGroup.code.toUpperCase() : prefixSource[0];
  final values = <String>{
    for (var number = 1; number <= 9; number++) '$prefix$number',
    ...existing.map(
      (item) => _canonicalOpponentDesignation(item.teamDesignation, ageGroup),
    ),
  }.where((item) => item.isNotEmpty).toList()
    ..sort((a, b) => a.compareTo(b));
  return values;
}

String _canonicalOpponentDesignation(
  String value,
  AgeGroupSummary? ageGroup,
) {
  return canonicalYouthTeamDesignation(value, ageCode: ageGroup?.code);
}

String _normalizedOpponentClubName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _MatchDraft {
  const _MatchDraft({
    required this.opponent,
    required this.isHome,
    required this.competition,
    required this.notes,
    required this.periodCount,
    required this.periodMinutes,
    required this.reminder24hEnabled,
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
  final bool reminder24hEnabled;
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
