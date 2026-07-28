import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/matchday.dart';
import '../../core/models/player.dart';
import '../../core/offline_ticker.dart';
import '../../core/providers.dart';
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
  String? _error;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _refreshTicker());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = ref.read(authProvider).user?.id;
    try {
      final repository = ref.read(repositoryProvider);
      final match = await repository.match(widget.matchId);
      List<PlayerModel> players = const [];
      if (widget.staffView) {
        try {
          players = await repository.players();
        } catch (_) {
          // The matchday and offline queue remain usable without a fresh roster.
        }
      }
      if (userId != null) {
        try {
          await ref.read(tickerOfflineQueueProvider).cacheMatch(
                userId: userId,
                match: match,
              );
        } catch (_) {
          // A storage failure must never turn a successful network load into
          // an offline error.
        }
      }
      if (!mounted) return;
      setState(() {
        _match = match;
        _players = players;
        _loading = false;
        _online = true;
        _usingOfflineSnapshot = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      MatchdayModel? cached;
      if (userId != null) {
        try {
          cached = await ref.read(tickerOfflineQueueProvider).cachedMatch(
                userId: userId,
                eventId: widget.matchId,
              );
        } catch (_) {
          cached = null;
        }
      }
      if (!mounted) return;
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
    if (!mounted || _match == null) return;
    try {
      final ticker = await ref.read(repositoryProvider).ticker(widget.matchId);
      if (!mounted) return;
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
          squad: current.squad,
          ticker: ticker,
        );
        _online = true;
        _usingOfflineSnapshot = false;
      });
      final userId = ref.read(authProvider).user?.id;
      if (userId != null) {
        try {
          await ref.read(tickerOfflineQueueProvider).cacheMatch(
                userId: userId,
                match: _match!,
              );
        } catch (_) {
          // Keep the live ticker usable even if local cache storage fails.
        }
      }
    } catch (_) {
      if (mounted) setState(() => _online = false);
    }
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
                    onSaved: _load,
                  ),
                  _LineupTab(
                    match: match,
                    editable: widget.staffView,
                    onSaved: _load,
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
  });
  final MatchdayModel match;
  final List<PlayerModel> allPlayers;
  final bool editable;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_SquadTab> createState() => _SquadTabState();
}

class _SquadTabState extends ConsumerState<_SquadTab> {
  late Map<String, NominationStatus> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final member in widget.match.squad?.members ?? const <SquadMemberModel>[])
        member.player.id: member.status,
    };
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
        Row(
          children: [
            Expanded(
              child: Text(
                '${_selected.length} Spieler ausgewählt',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _publish,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Veröffentlichen'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Kader speichern'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final player in widget.allPlayers)
                Card(
                  child: CheckboxListTile(
                    value: _selected.containsKey(player.id),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected[player.id] = NominationStatus.nominated;
                      } else {
                        _selected.remove(player.id);
                      }
                    }),
                    secondary: CircleAvatar(
                      child: Text(player.shirtNumber?.toString() ?? 'FC'),
                    ),
                    title: Text(player.displayName),
                    subtitle: Text(
                      player.status == PlayerStatus.injured
                          ? 'Verletzt · ${player.position ?? 'Spieler'}'
                          : player.position ?? 'Spieler',
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveMatchSquad(
            eventId: widget.match.id,
            members: _selected.entries
                .map((item) => (playerId: item.key, status: item.value))
                .toList(),
          );
      await widget.onSaved();
      if (mounted) _message('Kader wurde gespeichert.');
    } catch (_) {
      if (mounted) _message('Kader konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    await _save();
    try {
      await ref.read(repositoryProvider).publishMatchSquad(widget.match.id);
      await widget.onSaved();
      if (mounted) _message('Nominierung wurde veröffentlicht.');
    } catch (_) {
      if (mounted) _message('Nominierung konnte nicht veröffentlicht werden.');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _LineupTab extends ConsumerStatefulWidget {
  const _LineupTab({
    required this.match,
    required this.editable,
    required this.onSaved,
  });
  final MatchdayModel match;
  final bool editable;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends ConsumerState<_LineupTab> {
  late List<LineupPositionModel> _positions;
  String _formation = '2-3-1';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final lineup = widget.match.squad?.lineup;
    _formation = lineup?.formation ?? '2-3-1';
    _positions = lineup?.positions.toList() ?? _initialPositions();
  }

  List<LineupPositionModel> _initialPositions() {
    final members = widget.match.squad?.members
            .where((item) => item.status == NominationStatus.nominated)
            .take(7)
            .toList() ??
        const [];
    const slots = [
      (.5, .9, 'TW'),
      (.3, .7, 'LV'),
      (.7, .7, 'RV'),
      (.2, .45, 'LM'),
      (.5, .5, 'ZM'),
      (.8, .45, 'RM'),
      (.5, .18, 'ST'),
    ];
    return [
      for (var index = 0; index < members.length; index++)
        LineupPositionModel(
          player: members[index].player,
          positionCode: slots[index].$3,
          x: slots[index].$1,
          y: slots[index].$2,
          period: 1,
          isStarter: true,
          isGoalkeeper: index == 0,
          isCaptain: index == 1,
        ),
    ];
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
          Row(
            children: [
              DropdownButton<String>(
                value: _formation,
                items: const ['3-3', '2-3-1', '3-2-1', '3-4-1', '4-3-1', '4-4-2']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setState(() => _formation = value!),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _save(LineupStatus.draft),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Entwurf'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(LineupStatus.published),
                icon: const Icon(Icons.publish_rounded),
                label: const Text('Veröffentlichen'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = min(constraints.maxWidth, 720.0);
              return Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: width,
                  height: min(constraints.maxHeight, width * 1.25),
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
                          top: _positions[index].y *
                              (min(constraints.maxHeight, width * 1.25) - 62),
                          child: GestureDetector(
                            onPanUpdate: widget.editable
                                ? (details) {
                                    setState(() {
                                      final item = _positions[index];
                                      _positions[index] = LineupPositionModel(
                                        player: item.player,
                                        positionCode: item.positionCode,
                                        x: (item.x + details.delta.dx / width)
                                            .clamp(0, 1)
                                            .toDouble(),
                                        y: (item.y +
                                                details.delta.dy /
                                                    min(constraints.maxHeight, width * 1.25))
                                            .clamp(0, 1)
                                            .toDouble(),
                                        period: item.period,
                                        isStarter: item.isStarter,
                                        isGoalkeeper: item.isGoalkeeper,
                                        isCaptain: item.isCaptain,
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
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _save(LineupStatus status) async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveLineup(
            eventId: widget.match.id,
            formation: _formation,
            fieldSize: 7,
            status: status,
            positions: _positions,
          );
      await widget.onSaved();
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
  Widget build(BuildContext context) => Container(
        width: 76,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
        decoration: BoxDecoration(
          color: position.isGoalkeeper ? AppColors.orange : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${position.player.shirtNumber ?? '–'} · ${position.positionCode}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
            ),
            Text(
              position.player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
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
  DateTime? _lastQueuedAt;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPending());
    _queuePoller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_synchronizePending()),
    );
  }

  @override
  void didUpdateWidget(covariant _TickerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.online && widget.online) {
      unawaited(_synchronizePending());
    }
  }

  @override
  void dispose() {
    _queuePoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticker = widget.match.ticker ??
        const LiveTickerModel(
          status: TickerStatus.notStarted,
          currentPeriod: 1,
          elapsedSeconds: 0,
          ourGoals: 0,
          theirGoals: 0,
          lastSequence: 0,
          events: [],
        );
    final minute = ticker.elapsedSeconds ~/ 60;
    final fcIsHome = widget.match.details?.isHome != false;
    final pendingOurGoals = _pending.where((action) {
      return (fcIsHome && action.type == TickerEventType.homeGoal) ||
          (!fcIsHome && action.type == TickerEventType.awayGoal);
    }).length;
    final pendingTheirGoals = _pending.where((action) {
      return (fcIsHome && action.type == TickerEventType.awayGoal) ||
          (!fcIsHome && action.type == TickerEventType.homeGoal);
    }).length;
    final displayedOurGoals = ticker.ourGoals + pendingOurGoals;
    final displayedTheirGoals = ticker.theirGoals + pendingTheirGoals;
    final connected = widget.online && !_queueOffline;
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            _TickerMetric(
              label: 'SPIELSTAND',
              value: '$displayedOurGoals:$displayedTheirGoals',
            ),
            _TickerMetric(label: 'SPIELMINUTE', value: "$minute'"),
            _TickerMetric(label: 'ABSCHNITT', value: '${ticker.currentPeriod}'),
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
                onPressed: _busy
                    ? null
                    : () => _send(
                          ticker.status == TickerStatus.notStarted
                              ? TickerEventType.matchStart
                              : TickerEventType.resume,
                        ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  ticker.status == TickerStatus.notStarted ? 'Spiel starten' : 'Fortsetzen',
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _send(TickerEventType.periodEnd),
                icon: const Icon(Icons.pause_rounded),
                label: const Text('Halbzeit'),
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
                        title: Text(_eventTitle(event)),
                        subtitle: event.comment == null ? null : Text(event.comment!),
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

  Future<void> _goal(bool ours) async {
    final members = widget.match.squad?.members
            .where((item) => item.status == NominationStatus.nominated)
            .toList() ??
        const [];
    String? scorerId;
    if (ours && members.isNotEmpty && mounted) {
      scorerId = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.flash_on_rounded),
                title: const Text('Sofort ohne Torschütze speichern'),
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final member in members)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(member.player.shirtNumber?.toString() ?? 'FC'),
                  ),
                  title: Text(member.player.name),
                  onTap: () => Navigator.pop(context, member.player.id),
                ),
            ],
          ),
        ),
      );
      if (scorerId == null) return;
    }
    await _send(
      ours
          ? (widget.match.details?.isHome != false
              ? TickerEventType.homeGoal
              : TickerEventType.awayGoal)
          : (widget.match.details?.isHome != false
              ? TickerEventType.awayGoal
              : TickerEventType.homeGoal),
      scorerId: scorerId?.isEmpty == true ? null : scorerId,
    );
  }

  Future<void> _send(TickerEventType type, {String? scorerId}) async {
    final now = DateTime.now();
    if (_lastQueuedAt != null &&
        now.difference(_lastQueuedAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      _message('Die Sitzung ist abgelaufen. Bitte erneut anmelden.');
      return;
    }
    setState(() => _busy = true);
    try {
      _lastQueuedAt = now;
      await ref.read(tickerOfflineQueueProvider).enqueue(
            QueuedTickerAction(
              userId: userId,
              eventId: widget.match.id,
              clientEventId: '${now.microsecondsSinceEpoch}-${type.name}',
              type: type,
              scorerId: scorerId,
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
    try {
      final pending = await ref.read(tickerOfflineQueueProvider).pending(
            userId: userId,
            eventId: widget.match.id,
          );
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      if (mounted) setState(() => _queueOffline = true);
    }
  }

  Future<void> _synchronizePending({bool showSuccess = true}) async {
    if (_syncing || _pending.isEmpty) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _syncing = true);
    TickerQueueSyncResult result;
    try {
      result = await ref.read(tickerOfflineQueueProvider).synchronize(
            userId: userId,
            eventId: widget.match.id,
            send: (action) async {
              try {
                await ref.read(repositoryProvider).sendTickerEvent(
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
                if (status != null &&
                    [400, 403, 404, 409, 422].contains(status)) {
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
        setState(() {
          _syncing = false;
          _queueOffline = true;
        });
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
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).undoTickerEvent(
            eventId: widget.match.id,
            clientEventId: '${DateTime.now().microsecondsSinceEpoch}-undo',
          );
      await widget.onChanged();
    } catch (_) {
      if (mounted) _message('Die letzte Aktion konnte nicht rückgängig gemacht werden.');
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
    if (confirmed == true) await _send(TickerEventType.matchEnd);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

String _eventTitle(TickerEventModel event) => switch (event.type) {
      TickerEventType.homeGoal =>
        event.scorer == null ? 'Tor FC Teugn!' : 'Tor durch ${event.scorer!.name}!',
      TickerEventType.awayGoal => 'Tor für den Gegner',
      TickerEventType.matchStart => 'Das Spiel läuft',
      TickerEventType.periodEnd => 'Abschnitt beendet',
      TickerEventType.periodStart || TickerEventType.resume => 'Spiel fortgesetzt',
      TickerEventType.matchEnd => 'Abpfiff',
      TickerEventType.eventRevoked => 'Aktion korrigiert',
      TickerEventType.comment => 'Ticker-Update',
      _ => 'Spielereignis',
    };

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
