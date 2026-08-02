import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../core/football_options.dart';
import '../../core/models/event.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';
import '../../core/widgets/responsive_form_dialog.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import '../imports/competition_import_dialog.dart';

class TrainerMatchesPage extends ConsumerWidget {
  const TrainerMatchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final repository = ref.watch(repositoryProvider);
    final isSystemAdmin =
        ref.watch(authProvider).user?.role == UserRole.superAdmin;

    return PageScaffold(
      title: 'Spieltage',
      subtitle: 'Gegner, Wettbewerb und Ergebnisse zentral verwalten.',
      action: FilledButton.icon(
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
                const SnackBar(content: Text('Spielplan wurde importiert.')),
              );
            }
          }
        },
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Spielplan importieren'),
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
                    onDelete: isSystemAdmin
                        ? () => _deleteMatch(context, ref, match)
                        : null,
                    onEdit: () async {
                      final draft = await _openMatchDialog(context, match);
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
        loading: () => const Center(child: CircularProgressIndicator()),
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
    var entireSeries = false;
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
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Dieses und alle folgenden Spiele der Serie löschen',
                  ),
                  value: entireSeries,
                  onChanged: (value) => setDialogState(
                    () => entireSeries = value ?? false,
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
            entireSeries: entireSeries,
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

  Future<_MatchDraft?> _openMatchDialog(
      BuildContext context, EventModel event) async {
    final details = event.matchDetails;
    final opponent = TextEditingController(text: details?.opponent ?? '');
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
            Navigator.pop(
              context,
              _MatchDraft(
                opponent: opponent.text.trim(),
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
                  TextField(
                    controller: opponent,
                    decoration: const InputDecoration(labelText: 'Gegner'),
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
  });
  final EventModel event;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final details = event.matchDetails;
    final date = event.startAt.toLocal();
    final hasResult = details?.ourGoals != null && details?.theirGoals != null;
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
                Text(
                  details!.competition!,
                  style: const TextStyle(color: AppColors.blue),
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
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.sports_soccer_rounded,
                              color: AppColors.blue,
                            ),
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
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.sports_soccer_rounded,
                          color: AppColors.blue,
                        ),
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

class _MatchDraft {
  const _MatchDraft({
    required this.opponent,
    required this.isHome,
    required this.competition,
    required this.notes,
    required this.periodCount,
    required this.periodMinutes,
    this.ourGoals,
    this.theirGoals,
  });
  final String opponent;
  final bool isHome;
  final String competition;
  final String notes;
  final int periodCount;
  final int periodMinutes;
  final int? ourGoals;
  final int? theirGoals;
}
