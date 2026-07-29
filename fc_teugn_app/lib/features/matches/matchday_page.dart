import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../../core/lineup_planner.dart';
import '../../core/match_clock.dart';
import '../../core/models/matchday.dart';
import '../../core/models/player.dart';
import '../../core/offline_ticker.dart';
import '../../core/providers.dart';
import '../../core/ticker_signal.dart';
import '../../core/widgets/captain_badge.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';

class MatchdayPage extends ConsumerStatefulWidget {
  const MatchdayPage({
    required this.matchId,
    required this.staffView,
    super.key,
  });

  final String matchId;
  final bool staffView;

  @override
  ConsumerState<MatchdayPage> createState() => _MatchdayPageState();
}

class _MatchdayPageState extends ConsumerState<MatchdayPage> {
  MatchdayModel? _match;
  List<PlayerModel> _players = const [];
  bool _loading = true;
  bool _online = true;
  bool _usingOfflineSnapshot = false;
  bool _refreshingTicker = false;
  String? _error;
  Timer? _poller;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poller = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) unawaited(_refreshTicker());
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _loadRequest += 1;
    super.dispose();
  }

  Future<void> _load({bool refreshPlayers = false}) async {
    final request = ++_loadRequest;
    final userId = ref.read(authProvider).user?.id;
    final repository = ref.read(repositoryProvider);
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    final matchId = widget.matchId;
    final staffView = widget.staffView;
    try {
      final match = await repository.match(matchId);
      var players = staffView ? match.eligiblePlayers : const <PlayerModel>[];
      if (staffView) {
        if (refreshPlayers) {
          ref.invalidate(playersProvider);
        }
        try {
          // Read the exact same Riverpod result shown on the team page. The
          // match endpoint remains a fallback and both lists are merged, so a
          // temporary second request can never turn ten visible players into
          // an empty match roster.
          final cachedPlayers = ref.read(playersProvider).asData?.value;
          final List<PlayerModel> sharedPlayers =
              cachedPlayers ?? await ref.read(playersProvider.future);
          players = _mergeEligiblePlayers(players, sharedPlayers);
        } catch (_) {
          // The match response remains a usable fallback.
        }
      }
      if (userId != null) {
        try {
          await offlineQueue.cacheMatch(
            userId: userId,
            match: match,
          );
        } catch (_) {
          // A storage failure must never turn a successful network load into
          // an offline error.
        }
      }
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _match = match;
        _players = players;
        _loading = false;
        _online = true;
        _usingOfflineSnapshot = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _loadRequest) return;
      if (_match != null) {
        setState(() {
          _loading = false;
          if (_isConnectivityFailure(error)) _online = false;
        });
        return;
      }
      MatchdayModel? cached;
      if (userId != null) {
        try {
          cached = await offlineQueue.cachedMatch(
            userId: userId,
            eventId: matchId,
          );
        } catch (_) {
          cached = null;
        }
      }
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _loading = false;
        _online = false;
        _usingOfflineSnapshot = cached != null;
        _match = cached;
        _error =
            cached == null ? 'Der Spieltag konnte nicht geladen werden.' : null;
      });
    }
  }

  Future<void> _refreshTicker() async {
    if (!mounted || _match == null || _refreshingTicker) return;
    final repository = ref.read(repositoryProvider);
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    final userId = ref.read(authProvider).user?.id;
    final matchId = widget.matchId;
    _refreshingTicker = true;
    try {
      final ticker = await repository.ticker(matchId);
      if (!mounted) return;
      late final MatchdayModel updatedMatch;
      setState(() {
        final current = _match!;
        updatedMatch = MatchdayModel(
          id: current.id,
          title: current.title,
          startAt: current.startAt,
          meetingAt: current.meetingAt,
          location: current.location,
          teamId: current.teamId,
          details: current.details,
          squad: current.squad,
          ticker: ticker,
          eligiblePlayers: current.eligiblePlayers,
          gameFormat: current.gameFormat,
        );
        _match = updatedMatch;
        _online = true;
        _usingOfflineSnapshot = false;
      });
      if (userId != null) {
        try {
          await offlineQueue.cacheMatch(
            userId: userId,
            match: updatedMatch,
          );
        } catch (_) {
          // Keep the live ticker usable even if local cache storage fails.
        }
      }
    } catch (error) {
      if (mounted && _isConnectivityFailure(error)) {
        setState(() => _online = false);
      }
    } finally {
      _refreshingTicker = false;
    }
  }

  Future<void> _applySavedSquad(MatchSquadModel squad) async {
    if (!mounted || _match == null) return;
    setState(() {
      final current = _match!;
      _match = MatchdayModel(
        id: current.id,
        title: current.title,
        startAt: current.startAt,
        meetingAt: current.meetingAt,
        location: current.location,
        teamId: current.teamId,
        details: current.details,
        squad: squad,
        ticker: current.ticker,
        eligiblePlayers: current.eligiblePlayers,
        gameFormat: current.gameFormat,
      );
    });
  }

  Future<void> _applySavedLineup(LineupModel lineup) async {
    if (!mounted || _match?.squad == null) return;
    setState(() {
      final current = _match!;
      final squad = current.squad!;
      _match = MatchdayModel(
        id: current.id,
        title: current.title,
        startAt: current.startAt,
        meetingAt: current.meetingAt,
        location: current.location,
        teamId: current.teamId,
        details: current.details,
        squad: MatchSquadModel(
          id: squad.id,
          members: squad.members,
          name: squad.name,
          formation: squad.formation,
          publishedAt: squad.publishedAt,
          lineup: lineup,
        ),
        ticker: current.ticker,
        eligiblePlayers: current.eligiblePlayers,
        gameFormat: current.gameFormat,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PageScaffold(
        title: 'Spieltag',
        subtitle: 'Spiel wird vorbereitet …',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _match == null) {
      return PageScaffold(
        title: 'Spieltag',
        subtitle: 'Die Spieldaten sind gerade nicht verfügbar.',
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Spieltag nicht erreichbar',
          message: _error!,
        ),
      );
    }
    final match = _match!;
    final opponent = match.details?.opponent ?? 'Gegner';
    return DefaultTabController(
      length: 4,
      child: PageScaffold(
        title: 'FC Teugn · $opponent',
        subtitle: _dateLine(match),
        child: Column(
          children: [
            if (!_online || _usingOfflineSnapshot) ...[
              _OfflineBanner(cached: _usingOfflineSnapshot),
              const SizedBox(height: 12),
            ],
            _ScoreHero(match: match),
            const SizedBox(height: 18),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.info_outline_rounded), text: 'Übersicht'),
                Tab(icon: Icon(Icons.groups_rounded), text: 'Kader'),
                Tab(icon: Icon(Icons.dashboard_customize_rounded), text: 'Aufstellung'),
                Tab(icon: Icon(Icons.bolt_rounded), text: 'Liveticker'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: max(520.0, MediaQuery.sizeOf(context).height - 350),
              child: TabBarView(
                children: [
                  _Overview(match: match),
                  _SquadTab(
                    match: match,
                    allPlayers: _players,
                    editable: widget.staffView,
                    onSaved: _applySavedSquad,
                    onReload: () => _load(refreshPlayers: true),
                  ),
                  _LineupTab(
                    match: match,
                    editable: widget.staffView,
                    onSaved: _applySavedLineup,
                  ),
                  _TickerTab(
                    match: match,
                    editable: widget.staffView,
                    online: _online,
                    onChanged: _load,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLine(MatchdayModel match) {
    final date = match.startAt.toLocal();
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '${date.day}.${date.month}.${date.year} · $time Uhr · ${match.location}';
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.cached});

  final bool cached;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        border: Border.all(color: const Color(0xFFF59E0B)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFF9A3412)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              cached
                  ? 'Offline · zuletzt gespeicherter Spielstand. '
                      'Neue Tickeraktionen werden sicher vorgemerkt.'
                  : 'Verbindung unterbrochen · der letzte Stand bleibt sichtbar. '
                      'Tickeraktionen werden automatisch synchronisiert.',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.match});
  final MatchdayModel match;

  @override
  Widget build(BuildContext context) {
    final details = match.details;
    final ticker = match.ticker;
    final home = details?.isHome != false ? 'FC Teugn' : details?.opponent ?? 'Gegner';
    final away = details?.isHome != false ? details?.opponent ?? 'Gegner' : 'FC Teugn';
    final our = ticker?.ourGoals ?? details?.ourGoals;
    final their = ticker?.theirGoals ?? details?.theirGoals;
    final homeGoals = details?.isHome != false ? our : their;
    final awayGoals = details?.isHome != false ? their : our;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.blue],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(child: _TeamName(name: home)),
          Text(
            homeGoals == null ? '–' : '$homeGoals',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 38,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(':', style: TextStyle(color: Colors.white54, fontSize: 32)),
          ),
          Text(
            awayGoals == null ? '–' : '$awayGoals',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 38,
            ),
          ),
          Expanded(child: _TeamName(name: away)),
        ],
      ),
    );
  }
}

class _TeamName extends StatelessWidget {
  const _TeamName({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.match});
  final MatchdayModel match;

  @override
  Widget build(BuildContext context) {
    final details = match.details;
    final rows = <(IconData, String, String)>[
      (Icons.emoji_events_outlined, 'Wettbewerb', details?.competition ?? 'Nicht angegeben'),
      (Icons.format_list_numbered_rounded, 'Spieltag', details?.matchDay ?? 'Nicht angegeben'),
      (Icons.location_on_outlined, 'Spielstätte', match.location),
      (Icons.sports_rounded, 'Platz', details?.pitch ?? 'Nicht angegeben'),
      (
        Icons.timer_outlined,
        'Spielzeit',
        '${details?.periodCount ?? 2} × ${details?.periodMinutes ?? 30} Minuten',
      ),
      (Icons.person_outline_rounded, 'Schiedsrichter', details?.referee ?? 'Nicht angegeben'),
    ];
    return ListView(
      padding: const EdgeInsets.only(top: 4),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final row in rows)
              SizedBox(
                width: 310,
                child: Card(
                  child: ListTile(
                    leading: Icon(row.$1, color: AppColors.blue),
                    title: Text(row.$2),
                    subtitle: Text(row.$3),
                  ),
                ),
              ),
          ],
        ),
        if (details?.notes?.isNotEmpty == true) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(details!.notes!),
            ),
          ),
        ],
      ],
    );
  }
}

class _SquadTab extends ConsumerStatefulWidget {
  const _SquadTab({
    required this.match,
    required this.allPlayers,
    required this.editable,
    required this.onSaved,
    required this.onReload,
  });
  final MatchdayModel match;
  final List<PlayerModel> allPlayers;
  final bool editable;
  final Future<void> Function(MatchSquadModel squad) onSaved;
  final Future<void> Function() onReload;

  @override
  ConsumerState<_SquadTab> createState() => _SquadTabState();
}

class _SquadTabState extends ConsumerState<_SquadTab> {
  late Map<String, NominationStatus> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = _selectionFrom(widget.match);
  }

  @override
  void didUpdateWidget(covariant _SquadTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving &&
        _squadFingerprint(oldWidget.match) != _squadFingerprint(widget.match)) {
      _selected = _selectionFrom(widget.match);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editable) {
      final members = widget.match.squad?.members
              .where((member) => member.status == NominationStatus.nominated)
              .toList() ??
          const [];
      if (widget.match.squad?.publishedAt == null) {
        return const EmptyState(
          icon: Icons.visibility_off_outlined,
          title: 'Kader noch nicht veröffentlicht',
          message: 'Das Trainerteam veröffentlicht die Nominierung zu einem späteren Zeitpunkt.',
        );
      }
      return ListView(
        children: [
          for (final member in members)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(member.player.shirtNumber?.toString() ?? 'FC'),
                ),
                title: Text(member.player.name),
                subtitle: Text(member.player.position ?? 'Spieler'),
                trailing: const Chip(label: Text('Nominiert')),
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: constraints.maxWidth > 900
                    ? constraints.maxWidth - 650
                    : constraints.maxWidth,
                child: Text(
                  '${_selected.length} von ${widget.allPlayers.length} '
                  'Spielern ausgewählt',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    _saving || widget.allPlayers.isEmpty ? null : _selectAll,
                icon: const Icon(Icons.select_all_rounded),
                label: const Text('Alle auswählen'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _saving || _selected.isEmpty ? null : _deselectAll,
                icon: const Icon(Icons.deselect_rounded),
                label: const Text('Alle abwählen'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _publish,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Veröffentlichen'),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Kader speichern'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: widget.allPlayers.isEmpty
              ? EmptyState(
                  icon: Icons.group_off_outlined,
                  title: 'Noch keine Spieler verfügbar',
                  message:
                      'In deinen freigegebenen Mannschaften gibt es noch '
                      'keine aktiven Spielerprofile. Lege die Spieler unter '
                      '„Team“ an oder lade die Daten erneut.',
                  action: OutlinedButton.icon(
                    onPressed: widget.onReload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Spieler neu laden'),
                  ),
                )
              : ListView(
                  children: [
                    for (final player in widget.allPlayers)
                      Card(
                        child: CheckboxListTile(
                          value: _selected.containsKey(player.id),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected[player.id] =
                                  NominationStatus.nominated;
                            } else {
                              _selected.remove(player.id);
                            }
                          }),
                          secondary: CircleAvatar(
                            child:
                                Text(player.shirtNumber?.toString() ?? 'FC'),
                          ),
                          title: Text(player.displayName),
                          subtitle: Text(
                            player.status == PlayerStatus.injured
                                ? 'Verletzt · ${player.position ?? 'Spieler'}'
                                : player.position ?? 'Spieler',
                          ),
                          controlAffinity:
                              ListTileControlAffinity.trailing,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<bool> _save() async {
    final repository = ref.read(repositoryProvider);
    setState(() => _saving = true);
    try {
      final savedSquad = await repository.saveMatchSquad(
        eventId: widget.match.id,
        members: _selected.entries
            .map((item) => (playerId: item.key, status: item.value))
            .toList(),
      );
      final requestedIds = _selected.keys.toSet();
      final savedIds =
          savedSquad.members.map((member) => member.player.id).toSet();
      if (requestedIds.length != savedIds.length ||
          !requestedIds.containsAll(savedIds)) {
        throw StateError(
          'Der gespeicherte Kader entspricht nicht der Auswahl.',
        );
      }
      if (!mounted) return false;
      await widget.onSaved(savedSquad);
      if (mounted) _message('Kader wurde gespeichert.');
      return true;
    } catch (_) {
      if (mounted) _message('Kader konnte nicht gespeichert werden.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    final repository = ref.read(repositoryProvider);
    if (!await _save() || !mounted) return;
    try {
      await repository.publishMatchSquad(widget.match.id);
      if (!mounted) return;
      await widget.onReload();
      if (mounted) _message('Nominierung wurde veröffentlicht.');
    } catch (_) {
      if (mounted) _message('Nominierung konnte nicht veröffentlicht werden.');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _selectAll() {
    setState(() {
      _selected = {
        for (final player in widget.allPlayers)
          player.id: NominationStatus.nominated,
      };
    });
  }

  void _deselectAll() => setState(_selected.clear);

  Map<String, NominationStatus> _selectionFrom(MatchdayModel match) => {
        for (final member
            in match.squad?.members ?? const <SquadMemberModel>[])
          member.player.id: member.status,
      };

  String _squadFingerprint(MatchdayModel match) {
    final members = match.squad?.members ?? const <SquadMemberModel>[];
    return members
        .map((member) => '${member.player.id}:${member.status.name}')
        .join('|');
  }
}

class _LineupTab extends ConsumerStatefulWidget {
  const _LineupTab({
    required this.match,
    required this.editable,
    required this.onSaved,
  });
  final MatchdayModel match;
  final bool editable;
  final Future<void> Function(LineupModel lineup) onSaved;

  @override
  ConsumerState<_LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends ConsumerState<_LineupTab> {
  late List<LineupPositionModel> _positions;
  late String _formation;
  bool _saving = false;

  int get _fieldSize => widget.match.gameFormat.playerCount;
  List<MatchPlayer> get _nominatedPlayers =>
      widget.match.squad?.members
          .where((item) => item.status == NominationStatus.nominated)
          .map((item) => item.player)
          .toList() ??
      const [];
  List<MatchPlayer> get _benchPlayers {
    final fieldIds = _positions.map((position) => position.player.id).toSet();
    return _nominatedPlayers
        .where((player) => !fieldIds.contains(player.id))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final lineup = widget.match.squad?.lineup;
    _formation =
        lineup?.formation ?? widget.match.gameFormat.defaultFormation;
    _positions = lineup?.positions.toList() ?? _initialPositions();
  }

  @override
  void didUpdateWidget(covariant _LineupTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving ||
        _lineupFingerprint(oldWidget.match) ==
            _lineupFingerprint(widget.match)) {
      return;
    }
    final lineup = widget.match.squad?.lineup;
    _formation =
        lineup?.formation ?? widget.match.gameFormat.defaultFormation;
    _positions = lineup?.positions.toList() ?? _initialPositions();
  }

  List<LineupPositionModel> _initialPositions() {
    return planInitialLineup(
      players: _nominatedPlayers,
      fieldSize: _fieldSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.match.squad == null) {
      return const EmptyState(
        icon: Icons.group_add_outlined,
        title: 'Zuerst den Kader festlegen',
        message: 'Die Aufstellung verwendet ausschließlich nominierte Spieler.',
      );
    }
    final lineup = widget.match.squad!.lineup;
    if (!widget.editable && lineup == null) {
      return const EmptyState(
        icon: Icons.visibility_off_outlined,
        title: 'Aufstellung noch nicht veröffentlicht',
        message: 'Sobald die Aufstellung freigegeben ist, erscheint sie hier.',
      );
    }
    return Column(
      children: [
        if (widget.editable)
          LayoutBuilder(
            builder: (context, constraints) {
              final setup = <Widget>[
                DropdownButton<String>(
                  value: _formation,
                  items: {
                    _formation,
                    ...widget.match.gameFormat.formations,
                  }
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _formation = value!),
                ),
                Chip(
                  avatar: const Icon(Icons.groups_rounded, size: 18),
                  label: Text(widget.match.gameFormat.strength),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _positions = planInitialLineup(
                              players: _nominatedPlayers,
                              fieldSize: _fieldSize,
                            );
                          }),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Nach Positionen aufstellen'),
                ),
              ];
              final actions = <Widget>[
                OutlinedButton.icon(
                  onPressed:
                      _saving ? null : () => _save(LineupStatus.draft),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Entwurf'),
                ),
                FilledButton.icon(
                  onPressed:
                      _saving ? null : () => _save(LineupStatus.published),
                  icon: const Icon(Icons.publish_rounded),
                  label: const Text('Veröffentlichen'),
                ),
              ];
              if (constraints.maxWidth < 900) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [...setup, ...actions],
                );
              }
              return Row(
                children: [
                  ...setup.expand(
                    (widget) => [widget, const SizedBox(width: 10)],
                  ),
                  const Spacer(),
                  ...actions.expand(
                    (widget) => [widget, const SizedBox(width: 10)],
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              if (wide) {
                final pitchWidth =
                    min(constraints.maxWidth - 320, 720.0).toDouble();
                final pitchHeight = min(
                  constraints.maxHeight - (widget.editable ? 32 : 0),
                  pitchWidth * .72,
                ).toDouble();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _buildPitch(pitchWidth, pitchHeight),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 300,
                      height: constraints.maxHeight,
                      child: _buildBench(vertical: true),
                    ),
                  ],
                );
              }
              final pitchWidth = min(constraints.maxWidth, 720.0).toDouble();
              final pitchHeight =
                  min(constraints.maxHeight - 170, pitchWidth * .72).toDouble();
              return Column(
                children: [
                  _buildPitch(pitchWidth, max(260, pitchHeight).toDouble()),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: _buildBench(vertical: false),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPitch(double width, double height) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editable)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Spieler ziehen oder anklicken, um Spieler und Position zu ändern.',
            ),
          ),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xff16824b),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white70, width: 2),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _PitchLines()),
              for (var index = 0; index < _positions.length; index++)
                Positioned(
                  left: _positions[index].x * (width - 76),
                  top: _positions[index].y * (height - 62),
                  child: GestureDetector(
                    onTap:
                        widget.editable ? () => _editPosition(index) : null,
                    onPanUpdate: widget.editable
                        ? (details) {
                            setState(() {
                              final item = _positions[index];
                              _positions[index] = _copyPosition(
                                item,
                                x: (item.x + details.delta.dx / width)
                                    .clamp(0, 1)
                                    .toDouble(),
                                y: (item.y + details.delta.dy / height)
                                    .clamp(0, 1)
                                    .toDouble(),
                              );
                            });
                          }
                        : null,
                    child: _PlayerMarker(position: _positions[index]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBench({required bool vertical}) {
    final players = _benchPlayers;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_seat_rounded),
                const SizedBox(width: 8),
                Text(
                  'Ersatzbank · ${players.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: players.isEmpty
                  ? const Center(child: Text('Keine Ersatzspieler'))
                  : vertical
                      ? ListView(
                          children: [
                            for (final player in players)
                              _benchPlayerTile(player),
                          ],
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: players.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, index) => SizedBox(
                            width: 210,
                            child: _benchPlayerTile(players[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _benchPlayerTile(MatchPlayer player) {
    return Card(
      color: AppColors.background,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          child: Text(player.shirtNumber?.toString() ?? 'FC'),
        ),
        title: Text(player.name),
        subtitle: Text('Position: ${player.position ?? 'FLEX'}'),
        trailing: widget.editable
            ? const Icon(Icons.swap_horiz_rounded)
            : null,
        onTap: widget.editable ? () => _bringOntoField(player) : null,
      ),
    );
  }

  Future<void> _editPosition(int index) async {
    final current = _positions[index];
    var playerId = current.player.id;
    var positionCode = current.positionCode;
    var isGoalkeeper = current.isGoalkeeper;
    var isCaptain = current.isCaptain;
    final result = await showDialog<_LineupEditResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Spielerposition bearbeiten'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: playerId,
                  decoration: const InputDecoration(labelText: 'Spieler'),
                  items: [
                    for (final player in _nominatedPlayers)
                      DropdownMenuItem(
                        value: player.id,
                        child: Text(
                          '${player.name} · ${player.position ?? 'FLEX'}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => playerId = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: positionCode,
                  decoration: const InputDecoration(
                    labelText: 'Position in dieser Aufstellung',
                  ),
                  items: {
                    positionCode,
                    ...lineupPositionCodes,
                  }
                      .map(
                        (code) => DropdownMenuItem(
                          value: code,
                          child: Text(code),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        positionCode = value;
                        if (value == 'TW') isGoalkeeper = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Torhüter'),
                  value: isGoalkeeper,
                  onChanged: (value) =>
                      setDialogState(() => isGoalkeeper = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kapitän'),
                  value: isCaptain,
                  onChanged: (value) =>
                      setDialogState(() => isCaptain = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(
                context,
                const _LineupEditResult.onBench(),
              ),
              icon: const Icon(Icons.event_seat_rounded),
              label: const Text('Auf Bank setzen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _LineupEditResult.field(
                  playerId: playerId,
                  positionCode: positionCode,
                  isGoalkeeper: isGoalkeeper,
                  isCaptain: isCaptain,
                ),
              ),
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result.onBench) {
      setState(() => _positions.removeAt(index));
      return;
    }
    final selectedPlayer =
        _nominatedPlayers.firstWhere((player) => player.id == result.playerId);
    final otherIndex = _positions.indexWhere(
      (position) =>
          position.player.id == selectedPlayer.id &&
          position.player.id != current.player.id,
    );
    setState(() {
      if (result.isGoalkeeper) {
        for (var i = 0; i < _positions.length; i++) {
          if (i != index) {
            _positions[i] = _copyPosition(
              _positions[i],
              isGoalkeeper: false,
            );
          }
        }
      }
      if (result.isCaptain) {
        for (var i = 0; i < _positions.length; i++) {
          if (i != index) {
            _positions[i] = _copyPosition(
              _positions[i],
              isCaptain: false,
            );
          }
        }
      }
      if (otherIndex >= 0) {
        _positions[otherIndex] = _copyPosition(
          _positions[otherIndex],
          player: current.player,
        );
      }
      _positions[index] = _copyPosition(
        current,
        player: selectedPlayer,
        positionCode: result.positionCode,
        isGoalkeeper: result.isGoalkeeper,
        isCaptain: result.isCaptain,
      );
    });
  }

  Future<void> _bringOntoField(MatchPlayer player) async {
    if (_positions.any((position) => position.player.id == player.id)) return;
    if (_positions.length < _fieldSize) {
      final slots = lineupSlots(_fieldSize);
      final freeSlot = slots.firstWhere(
        (slot) => !_positions.any(
          (position) =>
              (position.x - slot.$1).abs() < .02 &&
              (position.y - slot.$2).abs() < .02,
        ),
        orElse: () => (.5, .5, player.position ?? 'FLEX'),
      );
      setState(() {
        _positions.add(
          LineupPositionModel(
            player: player,
            positionCode: freeSlot.$3,
            x: freeSlot.$1,
            y: freeSlot.$2,
            period: 1,
            isStarter: true,
            isGoalkeeper: freeSlot.$3 == 'TW',
            isCaptain: false,
          ),
        );
      });
      return;
    }
    final replaceIndex = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${player.name} einwechseln'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Welcher Spieler soll auf die Ersatzbank?'),
              const SizedBox(height: 10),
              for (var index = 0; index < _positions.length; index++)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      _positions[index].player.shirtNumber?.toString() ?? 'FC',
                    ),
                  ),
                  title: Text(_positions[index].player.name),
                  subtitle: Text(_positions[index].positionCode),
                  onTap: () => Navigator.pop(context, index),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (replaceIndex == null || !mounted) return;
    setState(() {
      _positions[replaceIndex] = _copyPosition(
        _positions[replaceIndex],
        player: player,
      );
    });
  }

  LineupPositionModel _copyPosition(
    LineupPositionModel position, {
    MatchPlayer? player,
    String? positionCode,
    double? x,
    double? y,
    bool? isGoalkeeper,
    bool? isCaptain,
  }) =>
      LineupPositionModel(
        player: player ?? position.player,
        positionCode: positionCode ?? position.positionCode,
        x: x ?? position.x,
        y: y ?? position.y,
        period: position.period,
        isStarter: position.isStarter,
        isGoalkeeper: isGoalkeeper ?? position.isGoalkeeper,
        isCaptain: isCaptain ?? position.isCaptain,
      );

  Future<void> _save(LineupStatus status) async {
    final repository = ref.read(repositoryProvider);
    setState(() => _saving = true);
    try {
      final savedLineup = await repository.saveLineup(
        eventId: widget.match.id,
        formation: _formation,
        fieldSize: _fieldSize,
        status: status,
        positions: _positions,
      );
      if (!_samePositions(_positions, savedLineup.positions)) {
        throw StateError(
          'Die gespeicherte Aufstellung entspricht nicht dem Entwurf.',
        );
      }
      if (!mounted) return;
      await widget.onSaved(savedLineup);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == LineupStatus.published
                  ? 'Aufstellung wurde veröffentlicht.'
                  : 'Aufstellungsentwurf wurde gespeichert.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aufstellung konnte nicht gespeichert werden.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _samePositions(
    List<LineupPositionModel> requested,
    List<LineupPositionModel> saved,
  ) {
    if (requested.length != saved.length) return false;
    final savedByPlayer = {
      for (final position in saved) position.player.id: position,
    };
    for (final position in requested) {
      final persisted = savedByPlayer[position.player.id];
      if (persisted == null ||
          persisted.positionCode != position.positionCode ||
          (persisted.x - position.x).abs() > .000001 ||
          (persisted.y - position.y).abs() > .000001 ||
          persisted.isGoalkeeper != position.isGoalkeeper ||
          persisted.isCaptain != position.isCaptain) {
        return false;
      }
    }
    return true;
  }

  String _lineupFingerprint(MatchdayModel match) {
    final lineup = match.squad?.lineup;
    return [
      match.gameFormat.apiValue,
      for (final member in match.squad?.members ?? const <SquadMemberModel>[])
        if (member.status == NominationStatus.nominated) member.player.id,
      if (lineup != null) lineup.formation,
      for (final position in lineup?.positions ?? const <LineupPositionModel>[])
        '${position.player.id}:${position.positionCode}:'
            '${position.x}:${position.y}:${position.period}:'
            '${position.isStarter}:${position.isGoalkeeper}:'
            '${position.isCaptain}',
    ].join('|');
  }
}

class _LineupEditResult {
  const _LineupEditResult.onBench()
      : onBench = true,
        playerId = '',
        positionCode = '',
        isGoalkeeper = false,
        isCaptain = false;

  const _LineupEditResult.field({
    required this.playerId,
    required this.positionCode,
    required this.isGoalkeeper,
    required this.isCaptain,
  }) : onBench = false;

  final bool onBench;
  final String playerId;
  final String positionCode;
  final bool isGoalkeeper;
  final bool isCaptain;
}

List<PlayerModel> _mergeEligiblePlayers(
  List<PlayerModel> matchPlayers,
  List<PlayerModel> sharedPlayers,
) {
  final byId = <String, PlayerModel>{};
  for (final player in [...matchPlayers, ...sharedPlayers]) {
    if (player.status == PlayerStatus.active ||
        player.status == PlayerStatus.injured) {
      byId[player.id] = player;
    }
  }
  final players = byId.values.toList()
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
  return players;
}

class _PitchLines extends StatelessWidget {
  const _PitchLines();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PitchPainter());
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * .14, paint);
    canvas.drawRect(Rect.fromLTWH(size.width * .2, 0, size.width * .6, size.height * .16), paint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * .2, size.height * .84, size.width * .6, size.height * .16),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({required this.position});
  final LineupPositionModel position;

  @override
  Widget build(BuildContext context) => Semantics(
        label: position.isCaptain
            ? '${position.player.name}, Kapitän'
            : position.player.name,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 76,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              decoration: BoxDecoration(
                color: position.isGoalkeeper ? AppColors.yellow : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${position.player.shirtNumber ?? '–'} · '
                    '${position.positionCode}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    position.player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            if (position.isCaptain)
              const Positioned(
                top: -9,
                right: -9,
                child: CaptainBadge(),
              ),
          ],
        ),
      );
}

class _TickerTab extends ConsumerStatefulWidget {
  const _TickerTab({
    required this.match,
    required this.editable,
    required this.online,
    required this.onChanged,
  });
  final MatchdayModel match;
  final bool editable;
  final bool online;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_TickerTab> createState() => _TickerTabState();
}

class _TickerTabState extends ConsumerState<_TickerTab> {
  bool _busy = false;
  bool _syncing = false;
  bool _queueOffline = false;
  List<QueuedTickerAction> _pending = const [];
  Timer? _queuePoller;
  Timer? _clockTimer;
  DateTime? _lastQueuedAt;
  late DateTime _clockSynchronizedAt;
  late int _elapsedAtSynchronization;
  late TickerStatus _statusAtSynchronization;
  late final ValueNotifier<_TickerFocusData> _focusData;
  final Set<int> _warnedPeriods = {};

  @override
  void initState() {
    super.initState();
    _synchronizeClock(_ticker);
    _focusData = ValueNotifier(_tickerFocusData(_ticker));
    unawaited(_loadPending());
    _queuePoller = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (mounted) unawaited(_synchronizePending());
      },
    );
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickClock(),
    );
  }

  @override
  void didUpdateWidget(covariant _TickerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronizeClock(_ticker);
    if (!oldWidget.online && widget.online) {
      unawaited(_synchronizePending());
    }
  }

  @override
  void dispose() {
    _queuePoller?.cancel();
    _clockTimer?.cancel();
    _focusData.dispose();
    super.dispose();
  }

  LiveTickerModel get _ticker =>
      widget.match.ticker ??
      const LiveTickerModel(
        status: TickerStatus.notStarted,
        currentPeriod: 1,
        elapsedSeconds: 0,
        ourGoals: 0,
        theirGoals: 0,
        lastSequence: 0,
        events: [],
      );

  void _synchronizeClock(LiveTickerModel ticker) {
    _clockSynchronizedAt = DateTime.now();
    _elapsedAtSynchronization = ticker.elapsedSeconds;
    _statusAtSynchronization = ticker.status;
  }

  int _effectiveElapsedSeconds() {
    if (_statusAtSynchronization != TickerStatus.live) {
      return _elapsedAtSynchronization;
    }
    return _elapsedAtSynchronization +
        DateTime.now().difference(_clockSynchronizedAt).inSeconds;
  }

  MatchClockValue _clockValue(LiveTickerModel ticker) => calculateMatchClock(
        ticker: ticker,
        periodMinutes: widget.match.details?.periodMinutes ?? 30,
        effectiveElapsedSeconds: _effectiveElapsedSeconds(),
      );

  ({int ours, int theirs}) _displayedScores(LiveTickerModel ticker) {
    final fcIsHome = widget.match.details?.isHome != false;
    final pendingOurGoals = _pending.where((action) {
      return (fcIsHome && action.type == TickerEventType.homeGoal) ||
          (!fcIsHome && action.type == TickerEventType.awayGoal);
    }).length;
    final pendingTheirGoals = _pending.where((action) {
      return (fcIsHome && action.type == TickerEventType.awayGoal) ||
          (!fcIsHome && action.type == TickerEventType.homeGoal);
    }).length;
    return (
      ours: ticker.ourGoals + pendingOurGoals,
      theirs: ticker.theirGoals + pendingTheirGoals,
    );
  }

  _TickerFocusData _tickerFocusData(LiveTickerModel ticker) {
    final scores = _displayedScores(ticker);
    final periodCount = widget.match.details?.periodCount ?? 2;
    return _TickerFocusData(
      clock: _clockValue(ticker),
      ourGoals: scores.ours,
      theirGoals: scores.theirs,
      opponent: widget.match.details?.opponent ?? 'Gegner',
      periodLabel: matchPeriodLabel(ticker.currentPeriod, periodCount),
      status: ticker.status,
    );
  }

  void _tickClock() {
    if (!mounted) return;
    final ticker = _ticker;
    final clock = _clockValue(ticker);
    if (widget.editable &&
        ticker.status == TickerStatus.live &&
        clock.expired &&
        _warnedPeriods.add(ticker.currentPeriod)) {
      unawaited(playTickerEndSignal());
    }
    setState(() {});
    _focusData.value = _tickerFocusData(ticker);
  }

  @override
  Widget build(BuildContext context) {
    final ticker = _ticker;
    final clock = _clockValue(ticker);
    final fcIsHome = widget.match.details?.isHome != false;
    final scores = _displayedScores(ticker);
    final connected = widget.online && !_queueOffline;
    final periodCount = widget.match.details?.periodCount ?? 2;
    final nextPeriod = ticker.currentPeriod < periodCount
        ? ticker.currentPeriod + 1
        : periodCount;
    final canStartNextPeriod =
        ticker.status == TickerStatus.notStarted ||
        (ticker.status == TickerStatus.halfTime &&
            ticker.currentPeriod < periodCount);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ConnectionChip(
              online: connected,
              syncing: _syncing,
              pending: _pending.length,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _CountdownCard(
          clock: clock,
          periodLabel: matchPeriodLabel(ticker.currentPeriod, periodCount),
          status: ticker.status,
          onExpand: _showFocusMode,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            _TickerMetric(
              label: 'SPIELSTAND',
              value: '${scores.ours}:${scores.theirs}',
            ),
            _TickerMetric(
              label: 'GESPIELT',
              value: _formatElapsed(clock.elapsedSeconds),
            ),
            _TickerMetric(
              label: 'ABSCHNITT',
              value: '${ticker.currentPeriod}/$periodCount',
            ),
            _TickerMetric(
              label: 'STATUS',
              value: _tickerStatus(ticker.status),
            ),
          ],
        ),
        if (widget.editable) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _goal(true),
                icon: const Icon(Icons.sports_soccer_rounded),
                label: const Text('Tor FC Teugn'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _goal(false),
                icon: const Icon(Icons.sports_soccer_rounded),
                label: const Text('Tor Gegner'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !canStartNextPeriod
                    ? null
                    : () => _startPeriod(ticker, nextPeriod),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  ticker.status == TickerStatus.notStarted
                      ? 'Spiel starten'
                      : 'Abschnitt $nextPeriod starten',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy || ticker.status != TickerStatus.live
                    ? null
                    : () => _send(
                          TickerEventType.periodEnd,
                          period: ticker.currentPeriod,
                        ),
                icon: const Icon(Icons.pause_rounded),
                label: Text('Abschnitt ${ticker.currentPeriod} beenden'),
              ),
              if (ticker.status == TickerStatus.live)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _send(TickerEventType.interruption),
                  icon: const Icon(Icons.timer_off_outlined),
                  label: const Text('Uhr pausieren'),
                ),
              if (ticker.status == TickerStatus.interrupted)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _resumeClock,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Uhr fortsetzen'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _undo,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Letzte Aktion zurück'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    _busy ? null : () => _confirmEnd(context),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Spiel beenden'),
              ),
            ],
          ),
        ],
        if (_pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lokal vorgemerkte Aktionen',
                  style: TextStyle(
                    color: Color(0xFF9A3412),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                for (final action in _pending.take(4))
                  Text(
                    '• ${_queuedActionLabel(action.type)} · '
                    '${_clock(action.createdAt)} Uhr',
                  ),
                if (_pending.length > 4)
                  Text(
                    '• ${_pending.length - 4} weitere Aktionen',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Expanded(
          child: ticker.events.isEmpty
              ? const EmptyState(
                  icon: Icons.bolt_outlined,
                  title: 'Noch keine Tickerereignisse',
                  message: 'Zum Spielstart erscheinen hier alle Aktionen chronologisch.',
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: ticker.events.length,
                  itemBuilder: (context, index) {
                    final event =
                        ticker.events[ticker.events.length - index - 1];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _eventColor(event.type),
                          child: Icon(_eventIcon(event.type), color: Colors.white),
                        ),
                        title: Text(_eventTitle(event, fcIsHome: fcIsHome)),
                        subtitle: _eventSubtitle(
                          event,
                          fcIsHome: fcIsHome,
                        ),
                        trailing: Text(
                          "${event.elapsedSeconds ~/ 60}' · ${event.ourGoals}:${event.theirGoals}",
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _startPeriod(
    LiveTickerModel ticker,
    int nextPeriod,
  ) async {
    await prepareTickerSignal();
    if (!mounted) return;
    await _send(
      ticker.status == TickerStatus.notStarted
          ? TickerEventType.matchStart
          : TickerEventType.periodStart,
      period: ticker.status == TickerStatus.notStarted ? 1 : nextPeriod,
    );
  }

  Future<void> _resumeClock() async {
    await prepareTickerSignal();
    if (mounted) await _send(TickerEventType.resume);
  }

  Future<void> _showFocusMode() async {
    await prepareTickerSignal();
    await activateTickerFocusMode();
    if (!mounted) {
      await deactivateTickerFocusMode();
      return;
    }
    try {
      await showDialog<void>(
        context: context,
        useSafeArea: false,
        builder: (dialogContext) => Dialog.fullscreen(
          child: ValueListenableBuilder<_TickerFocusData>(
            valueListenable: _focusData,
            builder: (context, data, _) => _TickerFocusView(
              data: data,
              editable: widget.editable,
              onOurGoal: () => _goal(true),
              onTheirGoal: () => _goal(false),
              onClose: () => Navigator.pop(dialogContext),
            ),
          ),
        ),
      );
    } finally {
      await deactivateTickerFocusMode();
    }
  }

  Future<void> _goal(bool ours) async {
    final members = widget.match.squad?.members
            .where((item) => item.status == NominationStatus.nominated)
            .toList() ??
        const [];
    _GoalAttribution? attribution;
    if (ours) {
      if (members.isEmpty) {
        _message(
          'Bitte zuerst mindestens einen Spieler für den Spielkader nominieren.',
        );
        return;
      }
      if (!mounted) return;
      attribution = await _selectGoalAttribution(members);
      if (attribution == null || !mounted) return;
    }
    await _send(
      ours
          ? (widget.match.details?.isHome != false
              ? TickerEventType.homeGoal
              : TickerEventType.awayGoal)
          : (widget.match.details?.isHome != false
              ? TickerEventType.awayGoal
              : TickerEventType.homeGoal),
      scorerId: attribution?.scorerId,
      assistId: attribution?.assistId,
    );
  }

  Future<_GoalAttribution?> _selectGoalAttribution(
    List<SquadMemberModel> members,
  ) {
    String? scorerId;
    String? assistId;
    return showDialog<_GoalAttribution>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tor für FC Teugn'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wer hat das Tor erzielt?',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scorerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Torschütze *',
                    prefixIcon: Icon(Icons.sports_soccer_rounded),
                  ),
                  items: [
                    for (final member in members)
                      DropdownMenuItem(
                        value: member.player.id,
                        child: Text(_matchPlayerLabel(member.player)),
                      ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      scorerId = value;
                      if (assistId == value) assistId = null;
                    });
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'Wer hat die Vorlage gegeben?',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional – kann leer bleiben.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('${scorerId ?? 'none'}-${assistId ?? 'none'}'),
                  initialValue: assistId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vorlagengeber (optional)',
                    prefixIcon: Icon(Icons.assistant_direction_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Keine Vorlage'),
                    ),
                    for (final member in members)
                      if (member.player.id != scorerId)
                        DropdownMenuItem(
                          value: member.player.id,
                          child: Text(_matchPlayerLabel(member.player)),
                        ),
                  ],
                  onChanged: (value) {
                    setDialogState(
                      () => assistId = value?.isEmpty == true ? null : value,
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: scorerId == null
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        _GoalAttribution(
                          scorerId: scorerId!,
                          assistId: assistId,
                        ),
                      ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Tor speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(
    TickerEventType type, {
    String? scorerId,
    String? assistId,
    int? period,
  }) async {
    final now = DateTime.now();
    if (_lastQueuedAt != null &&
        now.difference(_lastQueuedAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    final userId = ref.read(authProvider).user?.id;
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    if (userId == null) {
      _message('Die Sitzung ist abgelaufen. Bitte erneut anmelden.');
      return;
    }
    setState(() => _busy = true);
    try {
      _lastQueuedAt = now;
      await offlineQueue.enqueue(
        QueuedTickerAction(
          userId: userId,
          eventId: widget.match.id,
          clientEventId: '${now.microsecondsSinceEpoch}-${type.name}',
          type: type,
          scorerId: scorerId,
          assistId: assistId,
          period: period,
          createdAt: now,
        ),
      );
      await _loadPending();
      unawaited(_synchronizePending(showSuccess: false));
    } on StateError catch (error) {
      if (mounted) _message(error.message.toString());
    } catch (_) {
      if (mounted) {
        _message('Tickeraktion konnte nicht lokal vorgemerkt werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPending() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    try {
      final pending = await offlineQueue.pending(
        userId: userId,
        eventId: widget.match.id,
      );
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      // A browser storage problem is not a network outage.
    }
  }

  Future<void> _synchronizePending({bool showSuccess = true}) async {
    if (_syncing || _pending.isEmpty) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    final repository = ref.read(repositoryProvider);
    setState(() => _syncing = true);
    TickerQueueSyncResult result;
    try {
      result = await offlineQueue.synchronize(
        userId: userId,
        eventId: widget.match.id,
        send: (action) async {
          try {
            await repository.sendTickerEvent(
              eventId: action.eventId,
              clientEventId: action.clientEventId,
              type: action.type,
              scorerId: action.scorerId,
              assistId: action.assistId,
              comment: action.comment,
              period: action.period,
            );
          } on DioException catch (error) {
            final status = error.response?.statusCode;
            if (status != null && [400, 403, 404, 409, 422].contains(status)) {
              final data = error.response?.data;
              final message =
                  data is Map<String, dynamic> ? data['message'] as String? : null;
              throw PermanentTickerActionError(
                message ?? 'Die Aktion wurde vom Server abgelehnt.',
              );
            }
            rethrow;
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _syncing = false);
        _message(
          'Die Ticker-Synchronisierung konnte nicht abgeschlossen werden.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _queueOffline = !result.online;
    });
    await _loadPending();
    if (result.rejected > 0 && mounted) {
      _message(
        '${result.rejected} vorgemerkte Aktionen wurden vom Server abgelehnt '
        'und nicht übernommen.',
      );
    }
    if (result.sent > 0) {
      await widget.onChanged();
      if (showSuccess && mounted) {
        _message('${result.sent} vorgemerkte Aktionen synchronisiert.');
      }
    }
  }

  Future<void> _undo() async {
    if (!widget.online || _pending.isNotEmpty) {
      _message(
        'Korrekturen benötigen eine Verbindung und einen synchronen Spielstand.',
      );
      return;
    }
    final repository = ref.read(repositoryProvider);
    setState(() => _busy = true);
    try {
      await repository.undoTickerEvent(
        eventId: widget.match.id,
        clientEventId: '${DateTime.now().microsecondsSinceEpoch}-undo',
      );
      await widget.onChanged();
    } catch (_) {
      if (mounted) {
        _message('Die letzte Aktion konnte nicht rückgängig gemacht werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spiel wirklich beenden?'),
        content: const Text('Der Endstand wird gespeichert und das Spiel als beendet markiert.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Spiel beenden'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _send(TickerEventType.matchEnd);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _TickerFocusData {
  const _TickerFocusData({
    required this.clock,
    required this.ourGoals,
    required this.theirGoals,
    required this.opponent,
    required this.periodLabel,
    required this.status,
  });

  final MatchClockValue clock;
  final int ourGoals;
  final int theirGoals;
  final String opponent;
  final String periodLabel;
  final TickerStatus status;
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.clock,
    required this.periodLabel,
    required this.status,
    required this.onExpand,
  });

  final MatchClockValue clock;
  final String periodLabel;
  final TickerStatus status;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final expired = clock.expired && status == TickerStatus.live;
    final accent = expired ? const Color(0xFFC2410C) : AppColors.yellow;
    return Container(
      width: min(MediaQuery.sizeOf(context).width, 620.0),
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: status == TickerStatus.live
                      ? const Color(0xFF22C55E)
                      : AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$periodLabel · ${_tickerStatus(status)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onExpand,
                tooltip: 'Liveticker groß anzeigen',
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Text(
            clock.countdown,
            style: TextStyle(
              color: accent,
              fontSize: 52,
              height: 1,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: clock.progress,
              backgroundColor: Colors.white12,
              color: accent,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            expired
                ? 'Abschnittszeit abgelaufen'
                : 'Restzeit · ${clock.periodDurationSeconds ~/ 60} Minuten',
            style: TextStyle(
              color: expired ? const Color(0xFFFDBA74) : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TickerFocusView extends StatelessWidget {
  const _TickerFocusView({
    required this.data,
    required this.editable,
    required this.onOurGoal,
    required this.onTheirGoal,
    required this.onClose,
  });

  final _TickerFocusData data;
  final bool editable;
  final VoidCallback onOurGoal;
  final VoidCallback onTheirGoal;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final expired =
        data.clock.expired && data.status == TickerStatus.live;
    final clockColor = expired ? const Color(0xFFFFA56B) : AppColors.yellow;
    return Material(
      color: AppColors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const ClubLogo(size: 52),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'FC TEUGN · LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: onClose,
                    tooltip: 'Großansicht schließen',
                    icon: const Icon(Icons.close_fullscreen_rounded),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final clockSize = min(
                      constraints.maxWidth * .2,
                      constraints.maxHeight * .28,
                    ).clamp(58, 128);
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Text(
                          '${data.periodLabel} · ${_tickerStatus(data.status)}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data.clock.countdown,
                          style: TextStyle(
                            color: clockColor,
                            fontSize: clockSize.toDouble(),
                            height: 1,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: data.clock.progress,
                              minHeight: 10,
                              backgroundColor: Colors.white12,
                              color: clockColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _FocusTeamScore(
                              team: 'FC Teugn',
                              goals: data.ourGoals,
                              highlighted: true,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 26),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 54,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                            _FocusTeamScore(
                              team: data.opponent,
                              goals: data.theirGoals,
                            ),
                          ],
                        ),
                        if (expired) ...[
                          const SizedBox(height: 22),
                          const Text(
                            'Abschnittszeit abgelaufen',
                            style: TextStyle(
                              color: Color(0xFFFFA56B),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (editable)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onOurGoal,
                          icon: const Icon(Icons.sports_soccer_rounded),
                          label: const Text('Tor FC Teugn'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onTheirGoal,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          icon: const Icon(Icons.sports_soccer_rounded),
                          label: const Text('Tor Gegner'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusTeamScore extends StatelessWidget {
  const _FocusTeamScore({
    required this.team,
    required this.goals,
    this.highlighted = false,
  });

  final String team;
  final int goals;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: min(MediaQuery.sizeOf(context).width * .28, 240.0),
        child: Column(
          children: [
            Text(
              '$goals',
              style: TextStyle(
                color: highlighted ? AppColors.yellow : Colors.white,
                fontSize: 64,
                height: 1,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              team,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({
    required this.online,
    required this.syncing,
    required this.pending,
  });

  final bool online;
  final bool syncing;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final color = syncing
        ? AppColors.blue
        : online
            ? AppColors.teal
            : const Color(0xFFB45309);
    final label = syncing
        ? 'Synchronisiert …'
        : online
            ? 'Online${pending == 0 ? '' : ' · $pending ausstehend'}'
            : 'Offline · $pending ausstehend';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              size: 16,
              color: color,
            ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

String _queuedActionLabel(TickerEventType type) => switch (type) {
      TickerEventType.homeGoal => 'Tor Heimteam',
      TickerEventType.awayGoal => 'Tor Auswärtsteam',
      TickerEventType.matchStart => 'Spielstart',
      TickerEventType.periodEnd => 'Halbzeit',
      TickerEventType.periodStart || TickerEventType.resume => 'Fortsetzung',
      TickerEventType.interruption => 'Unterbrechung',
      TickerEventType.matchEnd => 'Spielende',
      _ => 'Tickerereignis',
    };

String _clock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatElapsed(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

bool _isConnectivityFailure(Object error) {
  if (error is! DioException) return false;
  return error.response == null ||
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;
}

class _TickerMetric extends StatelessWidget {
  const _TickerMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

String _tickerStatus(TickerStatus status) => switch (status) {
      TickerStatus.notStarted => 'Bereit',
      TickerStatus.live => 'Live',
      TickerStatus.paused => 'Pause',
      TickerStatus.halfTime => 'Halbzeit',
      TickerStatus.interrupted => 'Unterbrochen',
      TickerStatus.finished => 'Beendet',
    };

class _GoalAttribution {
  const _GoalAttribution({
    required this.scorerId,
    this.assistId,
  });

  final String scorerId;
  final String? assistId;
}

String _matchPlayerLabel(MatchPlayer player) {
  final number = player.shirtNumber == null ? '' : '${player.shirtNumber} · ';
  return '$number${player.name}';
}

bool _isOurGoal(TickerEventType type, {required bool fcIsHome}) =>
    (fcIsHome && type == TickerEventType.homeGoal) ||
    (!fcIsHome && type == TickerEventType.awayGoal);

String _eventTitle(
  TickerEventModel event, {
  required bool fcIsHome,
}) => switch (event.type) {
      TickerEventType.homeGoal || TickerEventType.awayGoal =>
        _isOurGoal(event.type, fcIsHome: fcIsHome)
            ? 'Tor durch ${event.scorer?.name ?? 'FC Teugn'}!'
            : 'Tor für den Gegner',
      TickerEventType.matchStart => 'Das Spiel läuft',
      TickerEventType.periodEnd => 'Abschnitt beendet',
      TickerEventType.periodStart || TickerEventType.resume => 'Spiel fortgesetzt',
      TickerEventType.matchEnd => 'Abpfiff',
      TickerEventType.eventRevoked => 'Aktion korrigiert',
      TickerEventType.comment => 'Ticker-Update',
      _ => 'Spielereignis',
    };

Widget? _eventSubtitle(
  TickerEventModel event, {
  required bool fcIsHome,
}) {
  final lines = <String>[
    if (_isOurGoal(event.type, fcIsHome: fcIsHome) && event.assist != null)
      'Vorlage: ${event.assist!.name}',
    if (event.comment?.trim().isNotEmpty == true) event.comment!.trim(),
  ];
  return lines.isEmpty ? null : Text(lines.join('\n'));
}

IconData _eventIcon(TickerEventType type) => switch (type) {
      TickerEventType.homeGoal || TickerEventType.awayGoal => Icons.sports_soccer_rounded,
      TickerEventType.matchStart || TickerEventType.resume => Icons.play_arrow_rounded,
      TickerEventType.matchEnd => Icons.flag_rounded,
      TickerEventType.eventRevoked => Icons.undo_rounded,
      _ => Icons.bolt_rounded,
    };

Color _eventColor(TickerEventType type) => switch (type) {
      TickerEventType.homeGoal => AppColors.blue,
      TickerEventType.awayGoal => Colors.deepOrange,
      TickerEventType.matchEnd => AppColors.navy,
      TickerEventType.eventRevoked => Colors.orange,
      _ => Colors.blueGrey,
    };
