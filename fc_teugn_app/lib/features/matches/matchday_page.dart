import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../../core/lineup_planner.dart';
import '../../core/match_clock.dart';
import '../../core/models/matchday.dart';
import '../../core/models/event.dart';
import '../../core/models/player.dart';
import '../../core/offline_ticker.dart';
import '../../core/providers.dart';
import '../../core/ticker_signal.dart';
import '../../core/widgets/captain_badge.dart';
import '../../core/widgets/player_team_chip.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import 'matchday_autopilot_tab.dart';

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
          players = _mergeEligiblePlayers(
            players,
            sharedPlayers
                .where(
                  (player) =>
                      player.ageGroupCode == match.playerPoolAgeGroupCode,
                )
                .toList(),
          );
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
          attendance: current.attendance,
          playerPoolAgeGroupCode: current.playerPoolAgeGroupCode,
          gameFormat: current.gameFormat,
          teamDefaultFormation: current.teamDefaultFormation,
          teamFormationOptions: current.teamFormationOptions,
          canManageTicker: current.canManageTicker,
          canDelegateTicker: current.canDelegateTicker,
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
        attendance: current.attendance,
        playerPoolAgeGroupCode: current.playerPoolAgeGroupCode,
        gameFormat: current.gameFormat,
        teamDefaultFormation: current.teamDefaultFormation,
        teamFormationOptions: current.teamFormationOptions,
        canManageTicker: current.canManageTicker,
        canDelegateTicker: current.canDelegateTicker,
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
        attendance: current.attendance,
        playerPoolAgeGroupCode: current.playerPoolAgeGroupCode,
        gameFormat: current.gameFormat,
        teamDefaultFormation: current.teamDefaultFormation,
        teamFormationOptions: current.teamFormationOptions,
        canManageTicker: current.canManageTicker,
        canDelegateTicker: current.canDelegateTicker,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PageScaffold(
        title: 'Spieltag',
        subtitle: 'Spiel wird vorbereitet …',
        child: Center(
          child: LogoLoadingPanel(message: 'Spieltag wird geladen …'),
        ),
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return DefaultTabController(
      length: 5,
      child: PageScaffold(
        title: 'FC Teugn · $opponent',
        subtitle: _dateLine(match),
        denseMobileHeader: true,
        hideMobileHeader: true,
        child: Column(
          children: [
            if (!_online || _usingOfflineSnapshot) ...[
              _OfflineBanner(cached: _usingOfflineSnapshot),
              const SizedBox(height: 12),
            ],
            _ScoreHero(match: match),
            SizedBox(height: mobile ? 5 : 18),
            _MatchdayTabBar(compact: mobile),
            SizedBox(height: mobile ? 4 : 14),
            SizedBox(
              height: mobile
                  ? max(480.0, MediaQuery.sizeOf(context).height - 250)
                  : max(520.0, MediaQuery.sizeOf(context).height - 350),
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
                  MatchdayAutopilotTab(
                    match: match,
                    allPlayers: _players,
                    editable: widget.staffView,
                    onSquadSaved: _applySavedSquad,
                    onLineupSaved: _applySavedLineup,
                  ),
                  _TickerTab(
                    match: match,
                    editable: widget.staffView || match.canManageTicker,
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    final details = match.details;
    final ticker = match.ticker;
    final home =
        details?.isHome != false ? 'FC Teugn' : details?.opponent ?? 'Gegner';
    final away =
        details?.isHome != false ? details?.opponent ?? 'Gegner' : 'FC Teugn';
    final our = ticker?.ourGoals ?? details?.ourGoals;
    final their = ticker?.theirGoals ?? details?.theirGoals;
    final homeGoals = details?.isHome != false ? our : their;
    final awayGoals = details?.isHome != false ? their : our;
    final date = match.startAt.toLocal();
    final dateLine = '${date.day}.${date.month}.${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} Uhr · ${match.location}';
    final score = Row(
      children: [
        Expanded(child: _TeamName(name: home, compact: compact)),
        Text(
          homeGoals == null ? '–' : '$homeGoals',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: compact ? 27 : 38,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 14),
          child: Text(':',
              style: TextStyle(
                color: Colors.white54,
                fontSize: compact ? 22 : 32,
              )),
        ),
        Text(
          awayGoals == null ? '–' : '$awayGoals',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: compact ? 27 : 38,
          ),
        ),
        Expanded(child: _TeamName(name: away, compact: compact)),
      ],
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 20,
        vertical: compact ? 9 : 22,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.blue],
        ),
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
      ),
      child: compact
          ? Column(
              children: [
                score,
                const SizedBox(height: 2),
                Text(
                  dateLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .64),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : score,
    );
  }
}

class _MatchdayTabBar extends StatelessWidget {
  const _MatchdayTabBar({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return const TabBar(
        isScrollable: true,
        tabs: [
          Tab(icon: Icon(Icons.info_outline_rounded), text: 'Übersicht'),
          Tab(icon: Icon(Icons.groups_rounded), text: 'Kader'),
          Tab(
            icon: Icon(Icons.dashboard_customize_rounded),
            text: 'Aufstellung',
          ),
          Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Autopilot'),
          Tab(icon: Icon(Icons.bolt_rounded), text: 'Liveticker'),
        ],
      );
    }

    return const TabBar(
      isScrollable: false,
      labelPadding: EdgeInsets.zero,
      tabs: [
        _CompactMatchTab(icon: Icons.info_outline_rounded, label: 'Info'),
        _CompactMatchTab(icon: Icons.groups_rounded, label: 'Kader'),
        _CompactMatchTab(
          icon: Icons.dashboard_customize_rounded,
          label: 'Elf',
        ),
        _CompactMatchTab(icon: Icons.auto_awesome_rounded, label: 'Auto'),
        _CompactMatchTab(icon: Icons.bolt_rounded, label: 'Live'),
      ],
    );
  }
}

class _CompactMatchTab extends StatelessWidget {
  const _CompactMatchTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _TeamName extends StatelessWidget {
  const _TeamName({required this.name, required this.compact});
  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 14),
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ).copyWith(fontSize: compact ? 15 : 18),
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
      (
        Icons.emoji_events_outlined,
        'Wettbewerb',
        details?.competition ?? 'Nicht angegeben'
      ),
      (
        Icons.format_list_numbered_rounded,
        'Spieltag',
        details?.matchDay ?? 'Nicht angegeben'
      ),
      (Icons.location_on_outlined, 'Spielstätte', match.location),
      (Icons.sports_rounded, 'Platz', details?.pitch ?? 'Nicht angegeben'),
      (
        Icons.timer_outlined,
        'Spielzeit',
        '${details?.periodCount ?? 2} × ${details?.periodMinutes ?? 30} Minuten',
      ),
      (
        Icons.person_outline_rounded,
        'Schiedsrichter',
        details?.referee ?? 'Nicht angegeben'
      ),
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
  String? _teamFilterId;
  final Set<String> _attendanceSaving = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = _selectionFrom(widget.match);
    _teamFilterId = widget.allPlayers.any(
      (player) => player.teamId == widget.match.teamId,
    )
        ? widget.match.teamId
        : null;
  }

  @override
  void didUpdateWidget(covariant _SquadTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving &&
        _squadFingerprint(oldWidget.match) != _squadFingerprint(widget.match)) {
      _selected = _selectionFrom(widget.match);
    }
    if (_teamFilterId != null &&
        !widget.allPlayers.any((player) => player.teamId == _teamFilterId)) {
      _teamFilterId = null;
    }
  }

  List<PlayerModel> get _visiblePlayers => _teamFilterId == null
      ? widget.allPlayers
      : widget.allPlayers
          .where((player) => player.teamId == _teamFilterId)
          .toList();

  List<({String id, String name})> get _availableTeams {
    final teams = <String, String>{};
    for (final player in widget.allPlayers) {
      final id = player.teamId;
      if (id != null && id.isNotEmpty) {
        teams[id] = player.teamCode;
      }
    }
    final result = teams.entries
        .map((entry) => (id: entry.key, name: entry.value))
        .toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    if (!widget.editable) {
      final members = widget.match.squad?.members
              .where((member) => member.status == NominationStatus.nominated)
              .toList() ??
          const [];
      if (widget.match.squad?.publishedAt == null) {
        return const EmptyState(
          icon: Icons.visibility_off_outlined,
          title: 'Kader noch nicht veröffentlicht',
          message:
              'Das Trainerteam veröffentlicht die Nominierung zu einem späteren Zeitpunkt.',
        );
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final member in members)
            Card(
              margin: EdgeInsets.only(bottom: compact ? 4 : 8),
              child: ListTile(
                dense: compact,
                visualDensity:
                    compact ? const VisualDensity(vertical: -3) : null,
                leading: CircleAvatar(
                  radius: compact ? 18 : null,
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
    final visiblePlayers = _visiblePlayers;
    final availableTeams = _availableTeams;
    return Column(
      children: [
        if (availableTeams.length > 1) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: compact
                ? DropdownButton<String?>(
                    value: _teamFilterId,
                    hint: const Text('Alle Mannschaften'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Alle Mannschaften'),
                      ),
                      for (final team in availableTeams)
                        DropdownMenuItem<String?>(
                          value: team.id,
                          child: Text(team.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _teamFilterId = value),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Alle Mannschaften'),
                        selected: _teamFilterId == null,
                        onSelected: (_) => setState(() => _teamFilterId = null),
                      ),
                      for (final team in availableTeams)
                        ChoiceChip(
                          label: Text(team.name),
                          selected: _teamFilterId == team.id,
                          onSelected: (_) =>
                              setState(() => _teamFilterId = team.id),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                '${_selected.length} ausgewählt · ${visiblePlayers.length} sichtbar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (compact) ...[
              IconButton(
                onPressed:
                    _saving || visiblePlayers.isEmpty ? null : _selectAll,
                tooltip: 'Alle auswählen',
                icon: const Icon(Icons.select_all_rounded),
              ),
              IconButton(
                onPressed: _saving || _selected.isEmpty ? null : _deselectAll,
                tooltip: 'Alle abwählen',
                icon: const Icon(Icons.deselect_rounded),
              ),
              IconButton(
                onPressed: _saving ? null : _publish,
                tooltip: 'Veröffentlichen',
                icon: const Icon(Icons.campaign_outlined),
              ),
              IconButton.filled(
                onPressed: _saving ? null : _save,
                tooltip: 'Kader speichern',
                icon: const Icon(Icons.save_outlined),
              ),
            ] else
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _saving || visiblePlayers.isEmpty ? null : _selectAll,
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
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Die automatische Startelf berücksichtigt nur zugesagte Spieler. '
            'Trainer können Rückmeldungen hier direkt korrigieren.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
          ),
        ),
        SizedBox(height: compact ? 6 : 12),
        Expanded(
          child: widget.allPlayers.isEmpty
              ? EmptyState(
                  icon: Icons.group_off_outlined,
                  title: 'Noch keine Spieler verfügbar',
                  message: 'In deinen freigegebenen Mannschaften gibt es noch '
                      'keine aktiven Spielerprofile. Lege die Spieler unter '
                      '„Team“ an oder lade die Daten erneut.',
                  action: OutlinedButton.icon(
                    onPressed: widget.onReload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Spieler neu laden'),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final player in visiblePlayers)
                      Card(
                        margin: EdgeInsets.only(bottom: compact ? 3 : 8),
                        child: ListTile(
                          dense: compact,
                          visualDensity: compact
                              ? const VisualDensity(vertical: -4)
                              : null,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 16,
                            vertical: compact ? 0 : 4,
                          ),
                          leading: CircleAvatar(
                            radius: compact ? 17 : null,
                            child: Text(player.shirtNumber?.toString() ?? 'FC'),
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(player.displayName)),
                              _AttendanceMenu(
                                status: _attendanceStatus(player.id),
                                saving: _attendanceSaving.contains(player.id),
                                onSelected: (status) =>
                                    _setAttendance(player, status),
                              ),
                            ],
                          ),
                          subtitle: Wrap(
                            spacing: 7,
                            runSpacing: compact ? 1 : 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              PlayerTeamChip(player: player, compact: true),
                              Text(
                                player.status == PlayerStatus.injured
                                    ? 'Verletzt · ${player.position ?? 'Spieler'}'
                                    : player.position ?? 'Spieler',
                              ),
                            ],
                          ),
                          trailing: Checkbox(
                            value: _selected.containsKey(player.id),
                            onChanged: (value) => setState(() {
                              if (value == true) {
                                _selected[player.id] =
                                    NominationStatus.nominated;
                              } else {
                                _selected.remove(player.id);
                              }
                            }),
                          ),
                          onTap: () => setState(() {
                            if (_selected.containsKey(player.id)) {
                              _selected.remove(player.id);
                            } else {
                              _selected[player.id] = NominationStatus.nominated;
                            }
                          }),
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
            .map(
              (item) => (
                playerId: item.key,
                status: item.value,
                plannedMinutes: null,
              ),
            )
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
      // Reconcile the complete match after applying the immediate response.
      // This also refreshes a server-generated default lineup without making
      // the successful squad save depend on a second request.
      unawaited(widget.onReload());
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
      for (final player in _visiblePlayers) {
        _selected[player.id] = NominationStatus.nominated;
      }
    });
  }

  void _deselectAll() => setState(() {
        for (final player in _visiblePlayers) {
          _selected.remove(player.id);
        }
      });

  AttendanceStatus _attendanceStatus(String playerId) =>
      widget.match.attendance
          .where((reply) => reply.playerId == playerId)
          .map((reply) => reply.status)
          .firstOrNull ??
      AttendanceStatus.unknown;

  Future<void> _setAttendance(
    PlayerModel player,
    AttendanceStatus status,
  ) async {
    setState(() => _attendanceSaving.add(player.id));
    try {
      await ref.read(repositoryProvider).setAttendance(
            eventId: widget.match.id,
            playerId: player.id,
            status: status,
          );
      await widget.onReload();
      if (mounted) _message('Zusage für ${player.displayName} gespeichert.');
    } catch (_) {
      if (mounted) _message('Rückmeldung konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _attendanceSaving.remove(player.id));
    }
  }

  Map<String, NominationStatus> _selectionFrom(MatchdayModel match) => {
        for (final member in match.squad?.members ?? const <SquadMemberModel>[])
          member.player.id: member.status,
      };

  String _squadFingerprint(MatchdayModel match) {
    final members = match.squad?.members ?? const <SquadMemberModel>[];
    return members
        .map((member) => '${member.player.id}:${member.status.name}')
        .join('|');
  }
}

class _AttendanceMenu extends StatelessWidget {
  const _AttendanceMenu({
    required this.status,
    required this.saving,
    required this.onSelected,
  });

  final AttendanceStatus status;
  final bool saving;
  final ValueChanged<AttendanceStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      AttendanceStatus.yes => (
          'Zusage',
          AppColors.success,
          Icons.check_rounded
        ),
      AttendanceStatus.no => ('Absage', Colors.red, Icons.close_rounded),
      AttendanceStatus.maybe => (
          'Vielleicht',
          Colors.orange,
          Icons.help_outline_rounded
        ),
      AttendanceStatus.unknown => (
          'Offen',
          AppColors.muted,
          Icons.schedule_rounded
        ),
    };
    if (saving) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LogoLoadingIndicator(
          size: 22,
          semanticsLabel: 'Rückmeldung wird gespeichert',
        ),
      );
    }
    return PopupMenuButton<AttendanceStatus>(
      tooltip: 'Zusage bearbeiten',
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: AttendanceStatus.yes,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.check_circle_outline_rounded),
            title: Text('Zusage'),
          ),
        ),
        PopupMenuItem(
          value: AttendanceStatus.maybe,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.help_outline_rounded),
            title: Text('Vielleicht'),
          ),
        ),
        PopupMenuItem(
          value: AttendanceStatus.no,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.cancel_outlined),
            title: Text('Absage'),
          ),
        ),
        PopupMenuItem(
          value: AttendanceStatus.unknown,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.schedule_rounded),
            title: Text('Offen'),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
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
  Timer? _positionSaveDebounce;

  int get _fieldSize => widget.match.gameFormat.playerCount;
  List<String> get _formationOptions => <String>{
        if (widget.match.teamDefaultFormation != null)
          widget.match.teamDefaultFormation!,
        ...widget.match.teamFormationOptions,
        ...widget.match.gameFormat.formations,
        _formation,
      }.toList();
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
    _formation = lineup?.formation ??
        widget.match.teamDefaultFormation ??
        widget.match.gameFormat.defaultFormation;
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
    _formation = lineup?.formation ??
        widget.match.teamDefaultFormation ??
        widget.match.gameFormat.defaultFormation;
    _positions = lineup?.positions.toList() ?? _initialPositions();
  }

  @override
  void dispose() {
    _positionSaveDebounce?.cancel();
    super.dispose();
  }

  List<LineupPositionModel> _initialPositions() {
    return planInitialLineup(
      players: _nominatedPlayers,
      fieldSize: _fieldSize,
      formation: _formation,
    );
  }

  void _applyFormation(String formation) {
    final starters = _positions.map((position) => position.player).toList();
    setState(() {
      _formation = formation;
      _positions = planInitialLineup(
        players: starters.isEmpty ? _nominatedPlayers : starters,
        fieldSize: _fieldSize,
        formation: formation,
      );
    });
    _schedulePositionSave();
  }

  String _formationLabel(String formation) =>
      formation == widget.match.teamDefaultFormation
          ? 'Stammformation · $formation'
          : formation;

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
                  items: _formationOptions
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_formationLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _applyFormation(value);
                  },
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
                              formation: _formation,
                            );
                          }),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Nach Positionen aufstellen'),
                ),
              ];
              final actions = <Widget>[
                OutlinedButton.icon(
                  onPressed: _showLineupFullscreen,
                  icon: const Icon(Icons.open_in_full_rounded),
                  label: const Text('Vollbild'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(LineupStatus.draft),
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
              if (constraints.maxWidth < 700) {
                final compact = constraints.maxWidth < 600;
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: compact ? 42 : 48,
                            padding: const EdgeInsets.only(left: 12, right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: ValueKey('lineup-formation-$_formation'),
                                value: _formation,
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.expand_more_rounded,
                                  size: 20,
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                                items: _formationOptions
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          _formationLabel(value),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) _applyFormation(value);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                    _positions = planInitialLineup(
                                      players: _nominatedPlayers,
                                      fieldSize: _fieldSize,
                                      formation: _formation,
                                    );
                                    _schedulePositionSave();
                                  }),
                          tooltip: 'Nach Positionen aufstellen',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.auto_awesome_rounded),
                        ),
                        IconButton(
                          onPressed: _showLineupFullscreen,
                          tooltip: 'Aufstellung im Vollbild',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.open_in_full_rounded),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 4 : 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _save(LineupStatus.draft),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Speichern'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(0, compact ? 40 : 44),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _save(LineupStatus.published),
                            icon: const Icon(Icons.publish_rounded),
                            label: const Text('Freigeben'),
                            style: FilledButton.styleFrom(
                              minimumSize: Size(0, compact ? 40 : 44),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
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
        SizedBox(height: MediaQuery.sizeOf(context).width < 600 ? 6 : 12),
        if (lineup?.usesTeamDefault == true) ...[
          _AutomaticLineupNotice(
            replacements: lineup!.automaticReplacements,
            compact: MediaQuery.sizeOf(context).width < 600,
          ),
          SizedBox(height: MediaQuery.sizeOf(context).width < 600 ? 6 : 12),
        ],
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
              final compact = constraints.maxWidth < 600;
              final benchHeight = compact ? 94.0 : 128.0;
              final pitchHeight = min(
                constraints.maxHeight - benchHeight - 18,
                pitchWidth * (compact ? .96 : .88),
              ).toDouble();
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  Center(
                    child: _buildPitch(
                      pitchWidth,
                      max(280, pitchHeight).toDouble(),
                      showHint: !compact,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  SizedBox(
                    height: benchHeight,
                    width: double.infinity,
                    child: _buildBench(vertical: false),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPitch(
    double width,
    double height, {
    StateSetter? fullscreenSetState,
    bool showHint = true,
  }) {
    final markerWidth = (_fieldSize >= 9 ? width * .105 : width * .17)
        .clamp(58.0, 82.0)
        .toDouble();
    const markerHeight = 54.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editable && showHint)
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
                  left: _positions[index].x * (width - markerWidth),
                  top: _positions[index].y * (height - markerHeight),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.editable
                        ? () async {
                            await _editPosition(index);
                            if (fullscreenSetState != null) {
                              fullscreenSetState(() {});
                            }
                          }
                        : null,
                    onPanUpdate: widget.editable
                        ? (details) {
                            setState(() {
                              final item = _positions[index];
                              _positions[index] = _copyPosition(
                                item,
                                x: (item.x +
                                        details.delta.dx /
                                            max(1, width - markerWidth))
                                    .clamp(0, 1)
                                    .toDouble(),
                                y: (item.y +
                                        details.delta.dy /
                                            max(1, height - markerHeight))
                                    .clamp(0, 1)
                                    .toDouble(),
                              );
                            });
                            fullscreenSetState?.call(() {});
                          }
                        : null,
                    onPanEnd:
                        widget.editable ? (_) => _schedulePositionSave() : null,
                    child: _PlayerMarker(
                      position: _positions[index],
                      width: markerWidth,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBench({
    required bool vertical,
    StateSetter? fullscreenSetState,
  }) {
    final players = _benchPlayers;
    final compact = !vertical;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 7 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_seat_rounded, size: compact ? 17 : 24),
                SizedBox(width: compact ? 5 : 8),
                Text(
                  'Ersatzbank · ${players.length}',
                  style: compact
                      ? Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          )
                      : Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            SizedBox(height: compact ? 3 : 8),
            Expanded(
              child: players.isEmpty
                  ? const Center(child: Text('Keine Ersatzspieler'))
                  : vertical
                      ? ListView(
                          children: [
                            for (final player in players)
                              _benchPlayerTile(
                                player,
                                fullscreenSetState: fullscreenSetState,
                              ),
                          ],
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: players.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) => SizedBox(
                            width: 148,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: _benchPlayerTile(
                                players[index],
                                compact: true,
                                fullscreenSetState: fullscreenSetState,
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _benchPlayerTile(
    MatchPlayer player, {
    bool compact = false,
    StateSetter? fullscreenSetState,
  }) {
    final onTap = widget.editable
        ? () async {
            await _bringOntoField(player);
            fullscreenSetState?.call(() {});
            _schedulePositionSave();
          }
        : null;
    if (compact) {
      return Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.yellowSoft,
                  foregroundColor: AppColors.black,
                  child: Text(
                    player.shirtNumber?.toString() ?? 'FC',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        player.position ?? 'FLEX',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.editable)
                  const Icon(Icons.swap_horiz_rounded, size: 18),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      color: AppColors.background,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          child: Text(player.shirtNumber?.toString() ?? 'FC'),
        ),
        title: Text(player.name),
        subtitle: Text('Position: ${player.position ?? 'FLEX'}'),
        trailing: widget.editable ? const Icon(Icons.swap_horiz_rounded) : null,
        onTap: onTap,
      ),
    );
  }

  Future<void> _showLineupFullscreen() async {
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setFullscreenState) => Scaffold(
            appBar: AppBar(
              title: Text('Aufstellung · $_formation'),
              actions: [
                if (widget.editable)
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            await _save(LineupStatus.draft);
                            setFullscreenState(() {});
                          },
                    tooltip: 'Aufstellung speichern',
                    icon: _saving
                        ? const LogoLoadingIndicator(
                            size: 24,
                            semanticsLabel: 'Aufstellung wird gespeichert',
                          )
                        : const Icon(Icons.save_outlined),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  tooltip: 'Vollbild schließen',
                  icon: const Icon(Icons.close_fullscreen_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final landscape =
                      constraints.maxWidth > constraints.maxHeight * 1.15;
                  if (landscape) {
                    final pitchWidth =
                        min(constraints.maxWidth * .68, 900.0).toDouble();
                    final pitchHeight =
                        min(constraints.maxHeight - 24, pitchWidth * .68)
                            .toDouble();
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Center(
                              child: _buildPitch(
                                pitchWidth,
                                pitchHeight,
                                fullscreenSetState: setFullscreenState,
                                showHint: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width:
                                min(300, constraints.maxWidth * .28).toDouble(),
                            child: _buildBench(
                              vertical: true,
                              fullscreenSetState: setFullscreenState,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final pitchWidth =
                      min(constraints.maxWidth - 20, 720.0).toDouble();
                  final pitchHeight = min(
                    max(220, constraints.maxHeight - 154),
                    pitchWidth * 1.16,
                  ).toDouble();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: _buildPitch(
                              pitchWidth,
                              pitchHeight,
                              fullscreenSetState: setFullscreenState,
                              showHint: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 122,
                          width: double.infinity,
                          child: _buildBench(
                            vertical: false,
                            fullscreenSetState: setFullscreenState,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _schedulePositionSave() {
    if (!widget.editable) return;
    _positionSaveDebounce?.cancel();
    _positionSaveDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_saving) {
        _schedulePositionSave();
        return;
      }
      unawaited(_save(LineupStatus.draft, quiet: true));
    });
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
                  onChanged: (value) => setDialogState(() => isCaptain = value),
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
      _schedulePositionSave();
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
    _schedulePositionSave();
  }

  Future<void> _bringOntoField(MatchPlayer player) async {
    if (_positions.any((position) => position.player.id == player.id)) return;
    if (_positions.length < _fieldSize) {
      final slots = lineupSlots(_fieldSize, formation: _formation);
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
      _schedulePositionSave();
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
    _schedulePositionSave();
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

  Future<void> _save(
    LineupStatus status, {
    bool quiet = false,
  }) async {
    final repository = ref.read(repositoryProvider);
    setState(() => _saving = true);
    try {
      final savedLineup = await repository.saveLineup(
        eventId: widget.match.id,
        formation: _formation,
        fieldSize: _fieldSize,
        status: status,
        positions: _positions,
        plannedSubstitutions:
            widget.match.squad?.lineup?.substitutions ?? const [],
      );
      if (!_samePositions(_positions, savedLineup.positions)) {
        throw StateError(
          'Die gespeicherte Aufstellung entspricht nicht dem Entwurf.',
        );
      }
      if (!mounted) return;
      await widget.onSaved(savedLineup);
      if (mounted && !quiet) {
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
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aufstellung konnte nicht gespeichert werden.')),
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

class _AutomaticLineupNotice extends StatelessWidget {
  const _AutomaticLineupNotice({
    required this.replacements,
    this.compact = false,
  });

  final int replacements;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 7 : 11,
        ),
        decoration: BoxDecoration(
          color: replacements > 0
              ? AppColors.yellowSoft
              : AppColors.teal.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: replacements > 0
                ? AppColors.yellow.withValues(alpha: .55)
                : AppColors.teal.withValues(alpha: .25),
          ),
        ),
        child: Row(
          children: [
            Icon(
              replacements > 0
                  ? Icons.swap_horiz_rounded
                  : Icons.auto_awesome_rounded,
              color: replacements > 0 ? AppColors.blue : AppColors.teal,
              size: compact ? 18 : 24,
            ),
            SizedBox(width: compact ? 7 : 10),
            Expanded(
              child: Text(
                compact
                    ? replacements > 0
                        ? 'Stammformation aktiv · $replacements Ersatz'
                        : 'Stammformation automatisch übernommen'
                    : replacements > 0
                        ? 'Stammformation der Mannschaft übernommen · '
                            '$replacements ${replacements == 1 ? 'Spieler wurde' : 'Spieler wurden'} '
                            'positionsgetreu ersetzt.'
                        : 'Stammformation der Mannschaft wurde automatisch übernommen.',
                maxLines: compact ? 1 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : null,
                ),
              ),
            ),
          ],
        ),
      );
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
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * .14, paint);
    canvas.drawRect(
        Rect.fromLTWH(size.width * .2, 0, size.width * .6, size.height * .16),
        paint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * .2, size.height * .84, size.width * .6,
          size.height * .16),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({required this.position, required this.width});
  final LineupPositionModel position;
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
        label: position.isCaptain
            ? '${position.player.name}, Kapitän'
            : position.player.name,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: width,
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
                      fontSize: 10.5,
                    ),
                  ),
                  Text(
                    position.player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5),
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
  late final StableElapsedClock _stableElapsedClock;
  int _lastRenderedElapsedSeconds = -1;
  late final ValueNotifier<_TickerFocusData> _focusData;
  final Set<int> _warnedPeriods = {};
  LiveTickerModel? _optimisticTicker;

  @override
  void initState() {
    super.initState();
    _stableElapsedClock = StableElapsedClock();
    _synchronizeClock(_ticker);
    _focusData = ValueNotifier(_tickerFocusData(_ticker));
    unawaited(_loadPending());
    _queuePoller = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (mounted) unawaited(_synchronizePending());
      },
    );
    _scheduleNextClockTick(immediate: true);
  }

  @override
  void didUpdateWidget(covariant _TickerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverTicker = widget.match.ticker;
    final previousServerSequence = oldWidget.match.ticker?.lastSequence ?? 0;
    if (_optimisticTicker != null &&
        serverTicker != null &&
        serverTicker.lastSequence > previousServerSequence) {
      _optimisticTicker = null;
    }
    final ticker = _ticker;
    final previousTicker = oldWidget.match.ticker;
    final elapsedBeforeSync = _effectiveElapsedSeconds();
    _synchronizeClock(_ticker);
    final timelineChanged =
        (previousTicker?.status ?? TickerStatus.notStarted) != ticker.status ||
            (previousTicker?.currentPeriod ?? 1) != ticker.currentPeriod ||
            oldWidget.match.details?.periodMinutes !=
                widget.match.details?.periodMinutes ||
            ticker.elapsedSeconds > elapsedBeforeSync + 10;
    if (timelineChanged) {
      _lastRenderedElapsedSeconds = -1;
      _scheduleNextClockTick(immediate: true);
    } else {
      // Score and event polls refresh the focus view, but deliberately leave
      // the already aligned clock timer untouched.
      Timer.run(() {
        if (mounted) _tickClock(force: true);
      });
    }
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
      _optimisticTicker ??
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

  void _applyOptimisticTickerAction(TickerEventType type, {int? period}) {
    final current = _ticker;
    final elapsed = _effectiveElapsedSeconds();
    final status = switch (type) {
      TickerEventType.matchStart ||
      TickerEventType.resume ||
      TickerEventType.periodStart =>
        TickerStatus.live,
      TickerEventType.periodEnd => TickerStatus.halfTime,
      TickerEventType.interruption ||
      TickerEventType.injury =>
        TickerStatus.interrupted,
      TickerEventType.matchEnd => TickerStatus.finished,
      _ => current.status,
    };
    if (status == current.status && period == null) return;
    _optimisticTicker = LiveTickerModel(
      status: status,
      currentPeriod: period ?? current.currentPeriod,
      elapsedSeconds: elapsed,
      ourGoals: current.ourGoals,
      theirGoals: current.theirGoals,
      lastSequence: current.lastSequence,
      events: current.events,
    );
    _synchronizeClock(_optimisticTicker!);
    _lastRenderedElapsedSeconds = -1;
    _scheduleNextClockTick(immediate: true);
    _focusData.value = _tickerFocusData(_optimisticTicker!);
  }

  void _synchronizeClock(LiveTickerModel ticker) {
    _stableElapsedClock.synchronize(ticker);
  }

  int _effectiveElapsedSeconds() => _stableElapsedClock.elapsedSeconds;

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

  void _scheduleNextClockTick({bool immediate = false}) {
    _clockTimer?.cancel();
    if (!mounted) return;
    final delay = immediate
        ? Duration.zero
        : Duration(
            milliseconds: _stableElapsedClock.millisecondsUntilNextSecond + 2,
          );
    _clockTimer = Timer(delay, () {
      if (!mounted) return;
      _tickClock(force: immediate);
      if (_ticker.status == TickerStatus.live) {
        _scheduleNextClockTick();
      }
    });
  }

  void _tickClock({bool force = false}) {
    if (!mounted) return;
    final elapsedSeconds = _effectiveElapsedSeconds();
    if (!force && elapsedSeconds == _lastRenderedElapsedSeconds) return;
    _lastRenderedElapsedSeconds = elapsedSeconds;
    final ticker = _ticker;
    final clock = calculateMatchClock(
      ticker: ticker,
      periodMinutes: widget.match.details?.periodMinutes ?? 30,
      effectiveElapsedSeconds: elapsedSeconds,
    );
    final shouldWarn = widget.editable &&
        ticker.status == TickerStatus.live &&
        clock.expired &&
        _warnedPeriods.add(ticker.currentPeriod);
    if (shouldWarn) {
      unawaited(playTickerEndSignal());
    }
    _focusData.value = _tickerFocusData(ticker);
  }

  Widget _liveCountdownCard() => ValueListenableBuilder<_TickerFocusData>(
        valueListenable: _focusData,
        builder: (context, data, _) => _CountdownCard(
          clock: data.clock,
          periodLabel: data.periodLabel,
          status: data.status,
          onExpand: _showFocusMode,
        ),
      );

  Widget _liveElapsedMetric() => ValueListenableBuilder<_TickerFocusData>(
        valueListenable: _focusData,
        builder: (context, data, _) => _TickerMetric(
          label: 'GESPIELT',
          value: _formatElapsed(data.clock.elapsedSeconds),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ticker = _ticker;
    final fcIsHome = widget.match.details?.isHome != false;
    final scores = _displayedScores(ticker);
    final connected = widget.online && !_queueOffline;
    final periodCount = widget.match.details?.periodCount ?? 2;
    final nextPeriod = ticker.currentPeriod < periodCount
        ? ticker.currentPeriod + 1
        : periodCount;
    final canStartNextPeriod = ticker.status == TickerStatus.notStarted ||
        (ticker.status == TickerStatus.halfTime &&
            ticker.currentPeriod < periodCount);
    final mobile = MediaQuery.sizeOf(context).width < 700;
    if (mobile) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 20),
        children: [
          Center(
            child: _ConnectionChip(
              online: connected,
              syncing: _syncing,
              pending: _pending.length,
            ),
          ),
          if (widget.match.canDelegateTicker) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _manageDelegation,
              icon: const Icon(Icons.supervisor_account_rounded),
              label: const Text('Eltern-Freigabe verwalten'),
            ),
          ],
          const SizedBox(height: 8),
          _liveCountdownCard(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _TickerMetric(
                label: 'SPIELSTAND',
                value: '${scores.ours}:${scores.theirs}',
              ),
              _liveElapsedMetric(),
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
            const SizedBox(height: 12),
            _mobileGoalButtons(),
            const SizedBox(height: 8),
            _mobileTickerControls(
              ticker: ticker,
              canStartNextPeriod: canStartNextPeriod,
              nextPeriod: nextPeriod,
            ),
          ],
          if (_pending.isNotEmpty) ...[
            const SizedBox(height: 10),
            _pendingActionsPanel(),
          ],
          const SizedBox(height: 14),
          Text(
            'Spielverlauf',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          if (ticker.events.isEmpty)
            const SizedBox(
              height: 220,
              child: EmptyState(
                icon: Icons.bolt_outlined,
                title: 'Noch keine Tickerereignisse',
                message:
                    'Zum Spielstart erscheinen hier alle Aktionen chronologisch.',
              ),
            )
          else
            for (final event in ticker.events.reversed)
              _tickerEventCard(event, fcIsHome: fcIsHome),
        ],
      );
    }
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
        if (widget.match.canDelegateTicker) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _manageDelegation,
            icon: const Icon(Icons.supervisor_account_rounded),
            label: const Text('Elternteil für dieses Spiel freigeben'),
          ),
        ],
        const SizedBox(height: 10),
        _liveCountdownCard(),
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
            _liveElapsedMetric(),
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
                  onPressed:
                      _busy ? null : () => _send(TickerEventType.interruption),
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
              if (widget.match.canDelegateTicker)
                OutlinedButton.icon(
                  onPressed: _busy ||
                          (ticker.status == TickerStatus.notStarted &&
                              ticker.events.isEmpty)
                      ? null
                      : _confirmReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Spiel zurücksetzen'),
                ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _confirmEnd(context),
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
                  message:
                      'Zum Spielstart erscheinen hier alle Aktionen chronologisch.',
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
                          child:
                              Icon(_eventIcon(event.type), color: Colors.white),
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

  Widget _mobileGoalButtons() => Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _goal(true),
              icon: const Icon(Icons.sports_soccer_rounded),
              label: const Text('Tor FC Teugn'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _goal(false),
              icon: const Icon(Icons.sports_soccer_rounded),
              label: const Text('Tor Gegner'),
            ),
          ),
        ],
      );

  Widget _mobileTickerControls({
    required LiveTickerModel ticker,
    required bool canStartNextPeriod,
    required int nextPeriod,
  }) {
    final controls = <Widget>[
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
          onPressed: _busy ? null : () => _send(TickerEventType.interruption),
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
      if (widget.match.canDelegateTicker)
        OutlinedButton.icon(
          onPressed: _busy ||
                  (ticker.status == TickerStatus.notStarted &&
                      ticker.events.isEmpty)
              ? null
              : _confirmReset,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Spiel zurücksetzen'),
        ),
      FilledButton.tonalIcon(
        onPressed: _busy ? null : () => _confirmEnd(context),
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Spiel beenden'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final control in controls)
            SizedBox(
              width: constraints.maxWidth > 460
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth,
              child: control,
            ),
        ],
      ),
    );
  }

  Widget _pendingActionsPanel() => Container(
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
      );

  Widget _tickerEventCard(
    TickerEventModel event, {
    required bool fcIsHome,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 5),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: _eventColor(event.type),
            child: Icon(_eventIcon(event.type), color: Colors.white),
          ),
          title: Text(_eventTitle(event, fcIsHome: fcIsHome)),
          subtitle: _eventSubtitle(event, fcIsHome: fcIsHome),
          trailing: Text(
            "${event.elapsedSeconds ~/ 60}'\n"
            '${event.ourGoals}:${event.theirGoals}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );

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

  Future<void> _manageDelegation() async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(repositoryProvider);
      final delegation = await repository.tickerDelegation(widget.match.id);
      if (!mounted) return;
      var selectedId = delegation.delegate?.id ?? '';
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Liveticker einmalig freigeben'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Das ausgewählte Elternteil darf ausschließlich den Verlauf dieses Spiels erfassen. Nach Spielende endet die Berechtigung automatisch.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: selectedId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Elternteil (optional)',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Keine Freigabe'),
                      ),
                      for (final candidate in delegation.candidates)
                        DropdownMenuItem(
                          value: candidate.id,
                          child: Text(
                            '${candidate.name} · ${candidate.email}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedId = value ?? ''),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await repository.saveTickerDelegation(
                    eventId: widget.match.id,
                    parentId: selectedId.isEmpty ? null : selectedId,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Freigabe speichern'),
              ),
            ],
          ),
        ),
      );
      if (saved == true && mounted) {
        _message(
          selectedId.isEmpty
              ? 'Die Liveticker-Freigabe wurde aufgehoben.'
              : 'Das Elternteil ist nur für dieses Spiel freigeschaltet.',
        );
      }
    } catch (_) {
      if (mounted) {
        _message('Die spielbezogene Freigabe konnte nicht gespeichert werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final actionElapsedSeconds = _effectiveElapsedSeconds();
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
    _applyOptimisticTickerAction(type, period: period);
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
          elapsedSeconds: actionElapsedSeconds,
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
              elapsedSeconds: action.elapsedSeconds,
            );
          } on DioException catch (error) {
            final status = error.response?.statusCode;
            if (status != null && [400, 403, 404, 409, 422].contains(status)) {
              final data = error.response?.data;
              final message = data is Map<String, dynamic>
                  ? data['message'] as String?
                  : null;
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
        content: const Text(
            'Der Endstand wird gespeichert und das Spiel als beendet markiert.'),
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

  Future<void> _confirmReset() async {
    if (!widget.online || _pending.isNotEmpty) {
      _message(
        'Das Spiel kann nur mit Verbindung und ohne offene Tickeraktionen '
        'zurückgesetzt werden.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded, size: 34),
        title: const Text('Spiel zurücksetzen?'),
        content: const Text(
          'Uhr, Spielabschnitt, Spielstand und der komplette Tickerverlauf '
          'werden auf den Ausgangszustand zurückgesetzt. Tore und Vorlagen '
          'werden aus den Statistiken entfernt. Kader und Aufstellung bleiben '
          'erhalten. Eine bestehende Eltern-Freigabe wird aufgehoben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Jetzt zurücksetzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).resetTicker(widget.match.id);
      _warnedPeriods.clear();
      await widget.onChanged();
      if (mounted) {
        _message(
          'Das Spiel wurde zurückgesetzt. Kader und Aufstellung sind erhalten.',
        );
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      final message =
          data is Map<String, dynamic> ? data['message'] as String? : null;
      _message(message ?? 'Das Spiel konnte nicht zurückgesetzt werden.');
    } catch (_) {
      if (mounted) {
        _message('Das Spiel konnte nicht zurückgesetzt werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            child: _SmoothClockProgress(
              value: clock.progress,
              minHeight: 7,
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
    final expired = data.clock.expired && data.status == TickerStatus.live;
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
                                child: _SmoothClockProgress(
                                  value: data.clock.progress,
                                  minHeight: 10,
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

class _SmoothClockProgress extends StatelessWidget {
  const _SmoothClockProgress({
    required this.value,
    required this.minHeight,
    required this.color,
  });

  final double value;
  final double minHeight;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: value, end: value),
        duration: const Duration(milliseconds: 950),
        curve: Curves.linear,
        builder: (context, animatedValue, _) => LinearProgressIndicator(
          value: animatedValue,
          minHeight: minHeight,
          backgroundColor: Colors.white12,
          color: color,
        ),
      );
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
            const LogoLoadingIndicator(
              size: 22,
              semanticsLabel: 'Spielstand wird synchronisiert',
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
            Text(label,
                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            Text(value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
}) =>
    switch (event.type) {
      TickerEventType.homeGoal ||
      TickerEventType.awayGoal =>
        _isOurGoal(event.type, fcIsHome: fcIsHome)
            ? 'Tor durch ${event.scorer?.name ?? 'FC Teugn'}!'
            : 'Tor für den Gegner',
      TickerEventType.matchStart => 'Das Spiel läuft',
      TickerEventType.periodEnd => 'Abschnitt beendet',
      TickerEventType.periodStart ||
      TickerEventType.resume =>
        'Spiel fortgesetzt',
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
      TickerEventType.homeGoal ||
      TickerEventType.awayGoal =>
        Icons.sports_soccer_rounded,
      TickerEventType.matchStart ||
      TickerEventType.resume =>
        Icons.play_arrow_rounded,
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
