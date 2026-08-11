import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models/competition.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/team_crest.dart';

typedef TournamentOpponentCreator = Future<OpponentModel?> Function();

/// Compact field for selecting a tournament opponent.
///
/// A regular [DropdownButton] renders every opponent in one route and can
/// cover an entire phone. This field opens a height-limited, searchable sheet
/// instead and keeps close/add actions visible at every viewport size.
class TournamentOpponentPickerField extends StatelessWidget {
  const TournamentOpponentPickerField({
    super.key,
    required this.opponentId,
    required this.opponents,
    required this.onChanged,
    this.onAddOpponent,
  });

  final String? opponentId;
  final List<OpponentModel> opponents;
  final ValueChanged<String?> onChanged;
  final TournamentOpponentCreator? onAddOpponent;

  OpponentModel? get selectedOpponent =>
      opponents.where((opponent) => opponent.id == opponentId).firstOrNull;

  Future<void> _open(BuildContext context) async {
    final pane = _pickerPaneFor(context);
    final choice = await showModalBottomSheet<_OpponentPickerChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      anchorPoint: pane.anchorPoint,
      constraints: BoxConstraints(maxWidth: pane.fullSize.width),
      builder: (context) => _TournamentOpponentPickerSheet(
        opponents: opponents,
        selectedId: opponentId,
        canAdd: onAddOpponent != null,
        pane: pane,
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice.addRequested) {
      final created = await onAddOpponent?.call();
      if (created != null && context.mounted) onChanged(created.id);
      return;
    }
    onChanged(choice.opponentId);
  }

  @override
  Widget build(BuildContext context) {
    final selected = selectedOpponent;
    return Semantics(
      button: true,
      label: selected == null
          ? 'Gegner auswählen'
          : 'Gegner ${selected.displayName} ändern',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          isEmpty: selected == null,
          decoration: const InputDecoration(
            labelText: 'Gegner *',
            isDense: true,
            contentPadding: EdgeInsets.fromLTRB(12, 12, 8, 12),
            suffixIcon: Icon(Icons.expand_more_rounded),
          ),
          child: Text(
            selected?.displayName ?? 'Auswählen oder neu anlegen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: selected == null
                ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    )
                : Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ),
      ),
    );
  }
}

class _OpponentPickerPane {
  const _OpponentPickerPane({
    required this.size,
    required this.alignment,
    required this.fullSize,
    required this.anchorPoint,
  });

  final Size size;
  final Alignment alignment;
  final Size fullSize;
  final Offset anchorPoint;
}

_OpponentPickerPane _pickerPaneFor(BuildContext context) {
  final paneSize = MediaQuery.sizeOf(context);
  final view = View.of(context);
  final fullSize = view.physicalSize / view.devicePixelRatio;
  final renderBox = context.findRenderObject() as RenderBox?;
  final center = renderBox?.localToGlobal(renderBox.size.center(Offset.zero)) ??
      Offset(fullSize.width / 2, fullSize.height / 2);
  final horizontal = paneSize.width < fullSize.width - .5
      ? center.dx < fullSize.width / 2
          ? -1.0
          : 1.0
      : 0.0;
  final vertical = paneSize.height < fullSize.height - .5
      ? center.dy < fullSize.height / 2
          ? -1.0
          : 1.0
      : 1.0;
  return _OpponentPickerPane(
    size: paneSize,
    alignment: Alignment(horizontal, vertical),
    fullSize: fullSize,
    anchorPoint: center,
  );
}

class _OpponentPickerChoice {
  const _OpponentPickerChoice.select(this.opponentId) : addRequested = false;
  const _OpponentPickerChoice.add()
      : opponentId = null,
        addRequested = true;

  final String? opponentId;
  final bool addRequested;
}

class _TournamentOpponentPickerSheet extends StatefulWidget {
  const _TournamentOpponentPickerSheet({
    required this.opponents,
    required this.selectedId,
    required this.canAdd,
    required this.pane,
  });

  final List<OpponentModel> opponents;
  final String? selectedId;
  final bool canAdd;
  final _OpponentPickerPane pane;

  @override
  State<_TournamentOpponentPickerSheet> createState() =>
      _TournamentOpponentPickerSheetState();
}

class _TournamentOpponentPickerSheetState
    extends State<_TournamentOpponentPickerSheet> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<OpponentModel> get filtered {
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.opponents;
    return widget.opponents
        .where(
          (opponent) => opponent.displayName.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = widget.pane.size.width < AppBreakpoints.narrow;
    final short = widget.pane.size.height < 680;
    final width = math.min(620.0, widget.pane.size.width);
    final height = math.min(
      short ? widget.pane.size.height * .86 : widget.pane.size.height * .72,
      590.0,
    );
    final items = filtered;

    return Align(
      alignment: widget.pane.alignment,
      child: SizedBox(
        key: const ValueKey('tournament-opponent-picker-sheet'),
        width: width,
        height: height,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(narrow ? 12 : 18, 10, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Gegner auswählen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('tournament-opponent-picker-close'),
                      tooltip: 'Gegnerauswahl schließen',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 18),
                child: TextField(
                  key: const ValueKey('tournament-opponent-picker-search'),
                  controller: search,
                  autofocus: false,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Suchen',
                    hintText: 'Verein oder Mannschaft',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche leeren',
                            onPressed: () {
                              search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                  ),
                ),
              ),
              if (widget.canAdd)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 12 : 18,
                    8,
                    narrow ? 12 : 18,
                    6,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('tournament-opponent-picker-add'),
                      onPressed: () => Navigator.pop(
                        context,
                        const _OpponentPickerChoice.add(),
                      ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 19),
                      label: const AdaptiveButtonLabel(
                        'Gegner hinzufügen',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Kein passender Gegner gefunden.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: const ValueKey(
                          'tournament-opponent-picker-results',
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final opponent = items[index];
                          final selected = opponent.id == widget.selectedId;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            minVerticalPadding: 6,
                            leading: TeamCrest.opponent(
                              size: 30,
                              logoUrl: opponent.logoUrl,
                            ),
                            title: Text(
                              opponent.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                              ),
                            ),
                            trailing: selected
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(
                              context,
                              _OpponentPickerChoice.select(opponent.id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
