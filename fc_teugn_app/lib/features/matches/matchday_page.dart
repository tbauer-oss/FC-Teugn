import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../../core/lineup_planner.dart';
import '../../core/live_goal_sound.dart';
import '../../core/match_clock.dart';
import '../../core/models/matchday.dart';
import '../../core/models/event.dart';
import '../../core/models/player.dart';
import '../../core/offline_outbox.dart';
import '../../core/offline_ticker.dart';
import '../../core/providers.dart';
import '../../core/push/live_match_surface.dart';
import '../../core/squad_selection.dart';
import '../../core/ticker_signal.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/captain_badge.dart';
import '../../core/widgets/player_team_chip.dart';
import '../../core/widgets/team_crest.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import 'matchday_autopilot_tab.dart';
import 'kit_laundry_duty_card.dart';

class MatchdayPage extends ConsumerStatefulWidget {
  const MatchdayPage({
    required this.matchId,
    required this.staffView,
    this.tournamentPlanning = false,
    this.initialTab,
    super.key,
  });

  final String matchId;
  final bool staffView;
  final bool tournamentPlanning;
  final String? initialTab;

  @override
  ConsumerState<MatchdayPage> createState() => _MatchdayPageState();
}

class _MatchdayPageState extends ConsumerState<MatchdayPage> {
  MatchdayModel? _match;
  List<PlayerModel> _players = const [];
  bool _loading = true;
  bool _loadingPlayers = false;
  bool _online = true;
  bool _usingOfflineSnapshot = false;
  bool _showingCachedPreview = false;
  bool _refreshingTicker = false;
  String? _error;
  bool _tickerLoopRunning = false;
  int _tickerLoopFailures = 0;
  Timer? _tickerDelayTimer;
  Completer<void>? _tickerDelayCompleter;
  int _loadRequest = 0;
  int _tournamentPlanningTab = 0;
  DateTime? _lastTickerConnectionAt;
  int _consecutiveTickerFailures = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_runTickerRefreshLoop());
  }

  @override
  void dispose() {
    _loadRequest += 1;
    _tickerDelayTimer?.cancel();
    final tickerDelayCompleter = _tickerDelayCompleter;
    if (tickerDelayCompleter != null && !tickerDelayCompleter.isCompleted) {
      tickerDelayCompleter.complete();
    }
    super.dispose();
  }

  Future<void> _load({bool refreshPlayers = false}) async {
    final request = ++_loadRequest;
    final userId = ref.read(authProvider).user?.id;
    final repository = ref.read(repositoryProvider);
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    final matchId = widget.matchId;
    final staffView = widget.staffView;
    if (refreshPlayers && staffView && _match != null && mounted) {
      setState(() => _loadingPlayers = true);
    }
    if (_match == null && userId != null) {
      unawaited(
        _showCachedMatchWhileLoading(
          request: request,
          userId: userId,
          matchId: matchId,
          offlineQueue: offlineQueue,
        ),
      );
    }
    try {
      final match = await repository.match(matchId);
      if (!mounted || request != _loadRequest) return;
      final endpointPlayers =
          staffView ? match.eligiblePlayers : const <PlayerModel>[];
      final sharedPlayersAreLoading = staffView &&
          (refreshPlayers || ref.read(playersProvider).asData == null);
      setState(() {
        _match = match;
        _players = endpointPlayers;
        _loadingPlayers = sharedPlayersAreLoading;
        _loading = false;
        _online = true;
        _usingOfflineSnapshot = false;
        _showingCachedPreview = false;
        _error = null;
        _lastTickerConnectionAt = DateTime.now();
        _consecutiveTickerFailures = 0;
      });
      _syncSystemLiveDisplay(match);
      if (userId != null) {
        unawaited(
          _cacheMatchInBackground(
            offlineQueue: offlineQueue,
            userId: userId,
            match: match,
          ),
        );
      }
      if (staffView) {
        unawaited(
          _loadSharedPlayersInBackground(
            request: request,
            match: match,
            refreshPlayers: refreshPlayers,
          ),
        );
      }
    } catch (error) {
      if (!mounted || request != _loadRequest) return;
      if (_match != null) {
        setState(() {
          _loading = false;
          _loadingPlayers = false;
          if (_showingCachedPreview) {
            _online = false;
            _usingOfflineSnapshot = true;
            _showingCachedPreview = false;
            return;
          }
          if (_isConnectivityFailure(error)) {
            _consecutiveTickerFailures += 1;
            final lastSuccess = _lastTickerConnectionAt;
            final stale = lastSuccess == null ||
                DateTime.now().difference(lastSuccess) >=
                    const Duration(seconds: 15);
            if (stale && _consecutiveTickerFailures >= 2) {
              _online = false;
            }
          }
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
        _loadingPlayers = false;
        _online = false;
        _usingOfflineSnapshot = cached != null;
        _showingCachedPreview = false;
        _match = cached;
        _error =
            cached == null ? 'Der Spieltag konnte nicht geladen werden.' : null;
      });
    }
  }

  Future<void> _showCachedMatchWhileLoading({
    required int request,
    required String userId,
    required String matchId,
    required TickerOfflineQueue offlineQueue,
  }) async {
    try {
      final cached = await offlineQueue.cachedMatch(
        userId: userId,
        eventId: matchId,
      );
      if (!mounted ||
          request != _loadRequest ||
          cached == null ||
          _match != null) {
        return;
      }
      setState(() {
        _match = cached;
        _players = widget.staffView ? cached.eligiblePlayers : const [];
        _loadingPlayers = widget.staffView;
        _loading = false;
        _online = true;
        _usingOfflineSnapshot = false;
        _showingCachedPreview = true;
        _error = null;
      });
    } catch (_) {
      // Der parallele Netzwerkabruf bleibt die verbindliche Datenquelle.
    }
  }

  Future<void> _cacheMatchInBackground({
    required TickerOfflineQueue offlineQueue,
    required String userId,
    required MatchdayModel match,
  }) async {
    try {
      await offlineQueue.cacheMatch(userId: userId, match: match);
    } catch (_) {
      // Browser- oder Gerätespeicher darf die sichtbare Seite nie verzögern.
    }
  }

  Future<void> _loadSharedPlayersInBackground({
    required int request,
    required MatchdayModel match,
    required bool refreshPlayers,
  }) async {
    if (refreshPlayers) ref.invalidate(playersProvider);
    try {
      // Die Spieltag-Antwort enthält bereits den vollständigen zulässigen
      // Kader. Die app-weite Spielerliste ergänzt ihn im Hintergrund, ohne
      // den ersten sichtbaren Aufbau des Spieltags zu blockieren.
      final cachedPlayers = ref.read(playersProvider).asData?.value;
      final List<PlayerModel> sharedPlayers =
          cachedPlayers ?? await ref.read(playersProvider.future);
      if (!mounted || request != _loadRequest || _match?.id != match.id) return;
      final players = _mergeEligiblePlayers(
        match.eligiblePlayers,
        sharedPlayers
            .where(
              (player) => player.ageGroupCode == match.playerPoolAgeGroupCode,
            )
            .toList(),
      );
      setState(() {
        _players = players;
        _loadingPlayers = false;
      });
    } catch (_) {
      // Die Spieltag-Antwort bleibt ein vollständiger, nutzbarer Fallback.
    } finally {
      if (mounted &&
          request == _loadRequest &&
          _match?.id == match.id &&
          _loadingPlayers) {
        setState(() => _loadingPlayers = false);
      }
    }
  }

  Future<void> _runTickerRefreshLoop() async {
    if (_tickerLoopRunning || widget.tournamentPlanning) return;
    _tickerLoopRunning = true;
    try {
      while (mounted && !widget.tournamentPlanning) {
        if (_match == null) {
          await _waitForTickerDelay(const Duration(milliseconds: 200));
          continue;
        }

        final successful = await _refreshTickerRequest(waitForChanges: true);
        if (!mounted) break;
        if (successful) {
          _tickerLoopFailures = 0;
          // Yield briefly before opening the next long-poll request. The
          // server keeps the preceding request open until an update arrives,
          // so this does not introduce a visible polling delay.
          await _waitForTickerDelay(const Duration(milliseconds: 75));
          continue;
        }

        _tickerLoopFailures += 1;
        const retrySeconds = [1, 2, 4, 8];
        final retryDelay =
            retrySeconds[min(_tickerLoopFailures - 1, retrySeconds.length - 1)];
        await _waitForTickerDelay(Duration(seconds: retryDelay));
      }
    } finally {
      _tickerLoopRunning = false;
    }
  }

  Future<void> _waitForTickerDelay(Duration duration) {
    final completer = Completer<void>();
    _tickerDelayCompleter = completer;
    _tickerDelayTimer = Timer(duration, () {
      if (identical(_tickerDelayCompleter, completer)) {
        _tickerDelayTimer = null;
        _tickerDelayCompleter = null;
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Future<void> _refreshTicker() async {
    await _refreshTickerRequest();
  }

  void _syncSystemLiveDisplay(MatchdayModel match) {
    final ticker = match.ticker;
    if (ticker == null || ticker.status == TickerStatus.notStarted) {
      unawaited(liveMatchSurface.cancel(match.id));
      return;
    }
    final details = match.details;
    final ownHome = details?.isHome != false;
    final opponent = details?.opponent ?? 'Gegner';
    final homeTeam = ownHome ? match.ownTeamName : opponent;
    final awayTeam = ownHome ? opponent : match.ownTeamName;
    final homeScore = ownHome ? ticker.ourGoals : ticker.theirGoals;
    final awayScore = ownHome ? ticker.theirGoals : ticker.ourGoals;
    final status = switch (ticker.status) {
      TickerStatus.live => 'Live',
      TickerStatus.halfTime => 'Pause',
      TickerStatus.paused => 'Pausiert',
      TickerStatus.interrupted => 'Unterbrochen',
      TickerStatus.finished => 'Abpfiff',
      TickerStatus.notStarted => 'Noch nicht gestartet',
    };
    unawaited(
      liveMatchSurface.update(
        matchId: match.id,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeScore: homeScore,
        awayScore: awayScore,
        minute:
            ticker.elapsedSeconds <= 0 ? 1 : ticker.elapsedSeconds ~/ 60 + 1,
        status: status,
        finished: ticker.status == TickerStatus.finished,
        actionUrl:
            '${widget.staffView ? '/trainer' : '/parent'}/matches/${match.id}?tab=live',
      ),
    );
  }

  Future<bool> _refreshTickerRequest({bool waitForChanges = false}) async {
    if (widget.tournamentPlanning ||
        !mounted ||
        _match == null ||
        _refreshingTicker) {
      return false;
    }
    final repository = ref.read(repositoryProvider);
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    final userId = ref.read(authProvider).user?.id;
    final matchId = widget.matchId;
    _refreshingTicker = true;
    try {
      final previousSequence = _match?.ticker?.lastSequence ?? 0;
      final incrementalTicker = await repository.ticker(
        matchId,
        after: previousSequence,
        waitForChanges: waitForChanges,
      );
      if (!mounted) return false;
      late final MatchdayModel updatedMatch;
      setState(() {
        final current = _match!;
        final ticker = mergeLiveTickerSnapshot(
          current.ticker,
          incrementalTicker,
        );
        updatedMatch = MatchdayModel(
          id: current.id,
          title: current.title,
          startAt: current.startAt,
          meetingAt: current.meetingAt,
          meetingLocation: current.meetingLocation,
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
          communicationStatus: current.communicationStatus,
          internalPublishedAt: current.internalPublishedAt,
          familyReleasedAt: current.familyReleasedAt,
          familyReleaseAudience: current.familyReleaseAudience,
          canPublishInternal: current.canPublishInternal,
          canNominateSquad: current.canNominateSquad,
          canReleaseFamily: current.canReleaseFamily,
          canRatePlayers: current.canRatePlayers,
          playerRatings: current.playerRatings,
          ownTeamName: current.ownTeamName,
          ownTeamShortName: current.ownTeamShortName,
          ownTeamLogoUrl: current.ownTeamLogoUrl,
          ownTeamIsPlayingCommunity: current.ownTeamIsPlayingCommunity,
        );
        _match = updatedMatch;
        _online = true;
        _usingOfflineSnapshot = false;
        _lastTickerConnectionAt = DateTime.now();
        _consecutiveTickerFailures = 0;
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
      _syncSystemLiveDisplay(updatedMatch);
      return true;
    } catch (error) {
      if (mounted && _isConnectivityFailure(error)) {
        setState(() {
          _consecutiveTickerFailures += 1;
          final lastSuccess = _lastTickerConnectionAt;
          final stale = lastSuccess == null ||
              DateTime.now().difference(lastSuccess) >=
                  const Duration(seconds: 15);
          if (stale && _consecutiveTickerFailures >= 2) {
            _online = false;
          }
        });
      }
      return false;
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
        meetingLocation: current.meetingLocation,
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
        communicationStatus: current.communicationStatus,
        internalPublishedAt: current.internalPublishedAt,
        familyReleasedAt: current.familyReleasedAt,
        familyReleaseAudience: current.familyReleaseAudience,
        canPublishInternal: current.canPublishInternal,
        canNominateSquad: current.canNominateSquad,
        canReleaseFamily: current.canReleaseFamily,
        canRatePlayers: current.canRatePlayers,
        playerRatings: current.playerRatings,
        ownTeamName: current.ownTeamName,
        ownTeamShortName: current.ownTeamShortName,
        ownTeamLogoUrl: current.ownTeamLogoUrl,
        ownTeamIsPlayingCommunity: current.ownTeamIsPlayingCommunity,
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
        meetingLocation: current.meetingLocation,
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
        communicationStatus: current.communicationStatus,
        internalPublishedAt: current.internalPublishedAt,
        familyReleasedAt: current.familyReleasedAt,
        familyReleaseAudience: current.familyReleaseAudience,
        canPublishInternal: current.canPublishInternal,
        canNominateSquad: current.canNominateSquad,
        canReleaseFamily: current.canReleaseFamily,
        canRatePlayers: current.canRatePlayers,
        playerRatings: current.playerRatings,
        ownTeamName: current.ownTeamName,
        ownTeamShortName: current.ownTeamShortName,
        ownTeamLogoUrl: current.ownTeamLogoUrl,
        ownTeamIsPlayingCommunity: current.ownTeamIsPlayingCommunity,
      );
    });
  }

  void _applyRatings(List<PlayerMatchRatingModel> ratings) {
    if (!mounted || _match == null) return;
    final current = _match!;
    setState(() {
      _match = MatchdayModel(
        id: current.id,
        title: current.title,
        startAt: current.startAt,
        meetingAt: current.meetingAt,
        meetingLocation: current.meetingLocation,
        location: current.location,
        teamId: current.teamId,
        details: current.details,
        squad: current.squad,
        ticker: current.ticker,
        eligiblePlayers: current.eligiblePlayers,
        attendance: current.attendance,
        playerPoolAgeGroupCode: current.playerPoolAgeGroupCode,
        gameFormat: current.gameFormat,
        teamDefaultFormation: current.teamDefaultFormation,
        teamFormationOptions: current.teamFormationOptions,
        canManageTicker: current.canManageTicker,
        canDelegateTicker: current.canDelegateTicker,
        communicationStatus: current.communicationStatus,
        internalPublishedAt: current.internalPublishedAt,
        familyReleasedAt: current.familyReleasedAt,
        familyReleaseAudience: current.familyReleaseAudience,
        canPublishInternal: current.canPublishInternal,
        canNominateSquad: current.canNominateSquad,
        canReleaseFamily: current.canReleaseFamily,
        canRatePlayers: current.canRatePlayers,
        playerRatings: ratings,
        ownTeamName: current.ownTeamName,
        ownTeamShortName: current.ownTeamShortName,
        ownTeamLogoUrl: current.ownTeamLogoUrl,
        ownTeamIsPlayingCommunity: current.ownTeamIsPlayingCommunity,
      );
    });
  }

  Future<void> _publishInternally() async {
    try {
      final repository = ref.read(repositoryProvider);
      final preview =
          await repository.internalPublicationPreview(widget.matchId);
      if (!mounted) return;
      final recipients = (preview['recipients'] as List<dynamic>? ?? const [])
          .map((item) => InternalPublicationRecipient.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList();
      if (recipients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Für diese Mannschaft ist noch kein zuständiges Trainerteam zugeordnet.',
            ),
          ),
        );
        return;
      }
      final selection = await showDialog<InternalPublicationSelection>(
        context: context,
        builder: (_) => InternalPublicationDialog(
          recipients: recipients,
          messagePreview: '${preview['messagePreview'] ?? ''}',
        ),
      );
      if (selection == null || !mounted) return;
      final result = await repository.publishMatchInternally(
        widget.matchId,
        recipientIds: selection.recipientIds,
        pushEnabled: selection.pushEnabled,
      );
      await _load();
      if (mounted) {
        final recipients = result['recipients'] as int? ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Intern an $recipients Verantwortliche veröffentlicht.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Interne Veröffentlichung fehlgeschlagen: $error'),
          ),
        );
      }
    }
  }

  Future<void> _releaseForFamilies() async {
    try {
      final repository = ref.read(repositoryProvider);
      final preview = await repository.familyReleasePreview(widget.matchId);
      if (!mounted) return;
      final requiresFullTeam = preview['audienceMode'] == 'FULL_TEAM_REQUIRED';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            widget.tournamentPlanning
                ? 'Turnier für Eltern und Spieler freigeben?'
                : 'Spiel für Eltern und Spieler freigeben?',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReleasePreviewRow('Mannschaft', '${preview['team'] ?? '–'}'),
                  _ReleasePreviewRow(
                    widget.tournamentPlanning ? 'Turnierart' : 'Spielart',
                    '${preview['category'] ?? '–'}',
                  ),
                  if (!widget.tournamentPlanning)
                    _ReleasePreviewRow(
                      'Gegner',
                      '${preview['opponent'] ?? '–'}',
                    ),
                  _ReleasePreviewRow(
                    widget.tournamentPlanning ? 'Beginn' : 'Anstoß',
                    _dateLine(_match!),
                  ),
                  _ReleasePreviewRow(
                    'Treffpunkt',
                    '${preview['meetingSummary'] ?? 'Treffpunkt noch offen'}',
                  ),
                  _ReleasePreviewRow(
                    widget.tournamentPlanning
                        ? 'Austragungsort'
                        : 'Spielstätte',
                    '${preview['location'] ?? 'Noch offen'}',
                  ),
                  _ReleasePreviewRow(
                    'Empfängerkreis',
                    requiresFullTeam
                        ? 'Gesamte Mannschaft'
                        : 'Nominierter Kader',
                  ),
                  _ReleasePreviewRow(
                    'Empfänger',
                    '${preview['recipients'] ?? 0} Benutzer',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nachrichtenvorschau',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text('${preview['messagePreview'] ?? ''}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Die Freigabe versendet verbindlich eine In-App- und Pushnachricht und wird nur einmal ausgeführt.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.family_restroom_rounded),
              label: const Text('Jetzt freigeben'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await repository.releaseMatchToFamilies(
        widget.matchId,
        fullTeam: requiresFullTeam,
      );
      ref.invalidate(personalResponsesProvider);
      ref.invalidate(eventsProvider);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['alreadyReleased'] == true
                  ? widget.tournamentPlanning
                      ? 'Das Turnier war bereits freigegeben; keine doppelte Nachricht wurde versendet.'
                      : 'Das Spiel war bereits freigegeben; keine doppelte Nachricht wurde versendet.'
                  : widget.tournamentPlanning
                      ? 'Turnier wurde für Eltern und Spieler freigegeben.'
                      : 'Spiel wurde für Eltern und Spieler freigegeben.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.tournamentPlanning ? 'Turnierfreigabe' : 'Spielfreigabe'} fehlgeschlagen: $error',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(manualDataRefreshProvider, (previous, next) {
      if (previous != null && previous != next && mounted) {
        unawaited(_load(refreshPlayers: widget.staffView));
      }
    });
    if (_loading) {
      return PageScaffold(
        title: widget.tournamentPlanning
            ? 'Turnier-Kader & Aufstellung'
            : 'Matchday Space',
        subtitle: widget.tournamentPlanning
            ? 'Turnierplanung wird vorbereitet …'
            : 'Spiel wird vorbereitet …',
        child: Center(
          child: LogoLoadingPanel(
            message: widget.tournamentPlanning
                ? 'Turnierplanung wird geladen …'
                : 'Spieltag wird geladen …',
          ),
        ),
      );
    }
    if (_error != null || _match == null) {
      return PageScaffold(
        title: widget.tournamentPlanning
            ? 'Turnier-Kader & Aufstellung'
            : 'Matchday Space',
        subtitle: widget.tournamentPlanning
            ? 'Die Turnierplanung ist gerade nicht verfügbar.'
            : 'Die Spieldaten sind gerade nicht verfügbar.',
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: widget.tournamentPlanning
              ? 'Turnierplanung nicht erreichbar'
              : 'Spieltag nicht erreichbar',
          message: _error!,
        ),
      );
    }
    final match = _match!;
    if (widget.tournamentPlanning) {
      final compactTournament =
          MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
      return PageScaffold(
        title: 'Turnier-Kader & Aufstellung',
        subtitle: '${match.title} · ${_dateLine(match)}',
        denseMobileHeader: true,
        fillRemaining: true,
        fillRemainingScrollable: true,
        child: Column(
          children: [
            if (!_online || _usingOfflineSnapshot) ...[
              _OfflineBanner(cached: _usingOfflineSnapshot),
              SizedBox(height: compactTournament ? 5 : 8),
            ],
            const _TournamentPlanningNotice(),
            if (widget.staffView &&
                (match.canPublishInternal || match.canReleaseFamily)) ...[
              SizedBox(height: compactTournament ? 5 : 8),
              MatchCommunicationActions(
                match: match,
                onPublishInternal: _publishInternally,
                onReleaseFamily: _releaseForFamilies,
                denseMobile: true,
              ),
            ],
            SizedBox(height: compactTournament ? 5 : 8),
            KitLaundryDutyCard(
              matchId: match.id,
              staffView: widget.staffView,
              compact: true,
            ),
            SizedBox(height: compactTournament ? 5 : 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                key: const ValueKey('tournament-planning-tabs'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.groups_rounded),
                    label: Text('Kader'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.account_tree_rounded),
                    label: Text('Aufstellung'),
                  ),
                ],
                selected: {_tournamentPlanningTab},
                onSelectionChanged: (selection) {
                  setState(() => _tournamentPlanningTab = selection.first);
                },
                style: compactTournament
                    ? const ButtonStyle(
                        minimumSize:
                            WidgetStatePropertyAll(Size.fromHeight(44)),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )
                    : null,
              ),
            ),
            SizedBox(height: compactTournament ? 3 : 6),
            Expanded(
              child: IndexedStack(
                index: _tournamentPlanningTab,
                children: [
                  MatchSquadTab(
                    match: match,
                    allPlayers: _players,
                    loadingPlayers: _loadingPlayers,
                    editable: widget.staffView,
                    tournamentPlanning: true,
                    onSaved: _applySavedSquad,
                    onReload: () => _load(refreshPlayers: true),
                  ),
                  _LineupTab(
                    match: match,
                    editable: widget.staffView,
                    onSaved: _applySavedLineup,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final opponent = match.details?.opponent ?? 'Gegner';
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final finished = match.details?.status == MatchStatus.finished ||
        match.details?.status == MatchStatus.recorded ||
        match.ticker?.status == TickerStatus.finished;
    final showParentRating = !widget.staffView && finished;
    final tabCount = widget.staffView ? 6 : (showParentRating ? 5 : 4);
    final initialTabIndex =
        widget.initialTab == 'live' ? (widget.staffView ? 4 : 3) : 0;
    return DefaultTabController(
      key: ValueKey('match-tabs-$tabCount'),
      length: tabCount,
      initialIndex: initialTabIndex,
      child: PageScaffold(
        title: match.details?.isHome == false
            ? '$opponent – ${match.ownTeamName}'
            : '${match.ownTeamName} – $opponent',
        subtitle: _dateLine(match),
        denseMobileHeader: true,
        hideMobileHeader: true,
        hideHeader: true,
        fillRemaining: true,
        fillRemainingScrollable: true,
        child: Column(
          children: [
            if (!_online || _usingOfflineSnapshot) ...[
              _OfflineBanner(cached: _usingOfflineSnapshot),
              const SizedBox(height: 12),
            ],
            _ScoreHero(match: match),
            if (widget.staffView &&
                (match.canPublishInternal || match.canReleaseFamily)) ...[
              const SizedBox(height: 6),
              MatchCommunicationActions(
                match: match,
                onPublishInternal: _publishInternally,
                onReleaseFamily: _releaseForFamilies,
                denseMobile: mobile,
              ),
            ],
            SizedBox(height: mobile ? 5 : 8),
            _MatchdayTabBar(
              compact: mobile,
              staffView: widget.staffView,
              showParentRating: showParentRating,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                children: [
                  MatchOverview(match: match, staffView: widget.staffView),
                  MatchSquadTab(
                    match: match,
                    allPlayers: _players,
                    loadingPlayers: _loadingPlayers,
                    editable: widget.staffView,
                    onSaved: _applySavedSquad,
                    onReload: () => _load(refreshPlayers: true),
                  ),
                  _LineupTab(
                    match: match,
                    editable: widget.staffView,
                    onSaved: _applySavedLineup,
                  ),
                  if (widget.staffView)
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
                    onChanged: _refreshTicker,
                  ),
                  if (widget.staffView)
                    _PlayerRatingsTab(
                      match: match,
                      onSaved: _applyRatings,
                    ),
                  if (showParentRating)
                    _ParentPlayerRatingsTab(matchId: match.id),
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

class _TournamentPlanningNotice extends StatelessWidget {
  const _TournamentPlanningNotice();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppBreakpoints.compact;
          final message = compact
              ? 'Kader & Aufstellung gelten fürs ganze Turnier. '
                  'Eine Planung je Partie bleibt optional.'
              : 'Kader und Aufstellung gelten für das gesamte Turnier. '
                  'Eine abweichende Planung je Partie bleibt in der '
                  'Turnierplanung optional möglich.';
          return Container(
            key: const ValueKey('tournament-planning-notice'),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 12,
              vertical: compact ? 7 : 10,
            ),
            decoration: BoxDecoration(
              color: AppColors.yellowSoft,
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.gold,
                  size: compact ? 18 : 22,
                ),
                SizedBox(width: compact ? 7 : 10),
                Expanded(
                  child: Text(
                    message,
                    style: (compact
                            ? Theme.of(context).textTheme.bodySmall
                            : Theme.of(context).textTheme.bodyMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _PlayerRatingsTab extends ConsumerStatefulWidget {
  const _PlayerRatingsTab({required this.match, required this.onSaved});

  final MatchdayModel match;
  final ValueChanged<List<PlayerMatchRatingModel>> onSaved;

  @override
  ConsumerState<_PlayerRatingsTab> createState() => _PlayerRatingsTabState();
}

class _PlayerRatingsTabState extends ConsumerState<_PlayerRatingsTab> {
  final Map<String, int?> _scores = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _syncScores();
  }

  @override
  void didUpdateWidget(covariant _PlayerRatingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.playerRatings != widget.match.playerRatings ||
        oldWidget.match.squad != widget.match.squad) {
      _syncScores();
    }
  }

  void _syncScores() {
    _scores
      ..clear()
      ..addEntries(
        widget.match.playerRatings.map(
          (rating) => MapEntry(rating.player.id, rating.score),
        ),
      );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final players = widget.match.squad?.members
              .where((member) => member.status == NominationStatus.nominated)
              .map((member) => member.player) ??
          const Iterable<MatchPlayer>.empty();
      final ratings = await ref.read(repositoryProvider).saveMatchRatings(
        eventId: widget.match.id,
        ratings: {
          for (final player in players) player.id: _scores[player.id],
        },
      );
      widget.onSaved(ratings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spielerbewertungen gespeichert.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Bewertungen konnten nicht gespeichert werden: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = widget.match.details?.status == MatchStatus.finished ||
        widget.match.details?.status == MatchStatus.recorded ||
        widget.match.ticker?.status == TickerStatus.finished;
    if (!widget.match.canRatePlayers) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Trainerinterner Bereich',
        message: 'Für dieses Konto ist die Spielerbewertung nicht freigegeben.',
      );
    }
    if (!finished) {
      return const EmptyState(
        icon: Icons.stars_rounded,
        title: 'Bewertung nach Abpfiff',
        message:
            'Nach Spielende können alle nominierten Spieler von 1 bis 10 bewertet werden.',
      );
    }
    final players = (widget.match.squad?.members ?? const [])
        .where((member) => member.status == NominationStatus.nominated)
        .map((member) => member.player)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (players.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'Kein nominierter Kader',
        message: 'Vor der Bewertung muss ein Kader nominiert sein.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.visibility_off_outlined, color: AppColors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Trainerintern · Die Bewertungen sind für Eltern und Spieler nicht sichtbar. Pro Spiel gilt eine gemeinsame, später korrigierbare Bewertung.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final player in players)
            Card(
              margin: const EdgeInsets.only(bottom: 7),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      child: Text(player.shirtNumber?.toString() ?? 'FC'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(player.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                          Text(
                            [player.position, player.secondaryPosition]
                                .whereType<String>()
                                .where((value) => value.trim().isNotEmpty)
                                .join(' / '),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 112,
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey(
                          'match-rating-${player.id}-${_scores[player.id]}',
                        ),
                        initialValue: _scores[player.id],
                        decoration: const InputDecoration(labelText: '1–10'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('–')),
                          for (var score = 1; score <= 10; score++)
                            DropdownMenuItem<int?>(
                                value: score, child: Text('$score / 10')),
                        ],
                        onChanged: _saving
                            ? null
                            : (score) =>
                                setState(() => _scores[player.id] = score),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                  _saving ? 'Wird gespeichert …' : 'Bewertungen speichern'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParentPlayerRatingsTab extends ConsumerStatefulWidget {
  const _ParentPlayerRatingsTab({required this.matchId});

  final String matchId;

  @override
  ConsumerState<_ParentPlayerRatingsTab> createState() =>
      _ParentPlayerRatingsTabState();
}

class _ParentPlayerRatingsTabState
    extends ConsumerState<_ParentPlayerRatingsTab> {
  ParentMatchRatingsModel? _data;
  final Map<String, int?> _scores = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data =
          await ref.read(repositoryProvider).parentMatchRatings(widget.matchId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _scores
          ..clear()
          ..addAll(data.ratings);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Die Elternbewertung konnte nicht geladen werden.';
      });
    }
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(repositoryProvider).saveParentMatchRatings(
        eventId: widget.matchId,
        ratings: {
          for (final player in data.players) player.id: _scores[player.id],
        },
      );
      if (!mounted) return;
      setState(() {
        _data = saved;
        _scores
          ..clear()
          ..addAll(saved.ratings);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deine anonyme Spielerbewertung wurde gespeichert.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Die Elternbewertung konnte nicht gespeichert werden: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Bewertung nicht verfügbar',
        message: _error!,
      );
    }
    final data = _data;
    if (data == null || !data.available) {
      return const EmptyState(
        icon: Icons.stars_rounded,
        title: 'Bewertung nach Abpfiff',
        message: 'Die optionale Bewertung wird nach Spielende freigeschaltet.',
      );
    }
    if (data.players.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'Keine Spieler zur Bewertung',
        message: 'Für dieses Spiel ist kein nominierter Kader hinterlegt.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Card(
            color: AppColors.yellowSoft,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.visibility_off_outlined, color: AppColors.gold),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Optional und anonym · Bewerte die nominierten Spieler wie das Trainerteam von 1 bis 10. Trainer sehen nur den zusammengefassten Elternwert – niemals, wer wie bewertet hat.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          for (final player in data.players)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    CircleAvatar(
                      child: Text(player.shirtNumber?.toString() ?? 'FC'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        player.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    SizedBox(
                      width: 108,
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey(
                          'parent-match-rating-${player.id}-${_scores[player.id]}',
                        ),
                        initialValue: _scores[player.id],
                        decoration: const InputDecoration(labelText: '1–10'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('–'),
                          ),
                          for (var score = 1; score <= 10; score++)
                            DropdownMenuItem<int?>(
                              value: score,
                              child: Text('$score / 10'),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (score) =>
                                setState(() => _scores[player.id] = score),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 7),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              _saving ? 'Wird gespeichert …' : 'Anonym speichern',
            ),
          ),
        ],
      ),
    );
  }
}

class InternalPublicationRecipient {
  const InternalPublicationRecipient({
    required this.id,
    required this.name,
    required this.functions,
    required this.teams,
    required this.isSender,
  });

  final String id;
  final String name;
  final List<String> functions;
  final List<String> teams;
  final bool isSender;

  factory InternalPublicationRecipient.fromJson(Map<String, dynamic> json) =>
      InternalPublicationRecipient(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Trainerteam-Mitglied',
        functions: (json['functions'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        teams: (json['teams'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        isSender: json['isSender'] as bool? ?? false,
      );
}

class InternalPublicationSelection {
  const InternalPublicationSelection({
    required this.recipientIds,
    required this.pushEnabled,
  });

  final List<String> recipientIds;
  final bool pushEnabled;
}

class InternalPublicationDialog extends StatefulWidget {
  const InternalPublicationDialog({
    super.key,
    required this.recipients,
    required this.messagePreview,
  });

  final List<InternalPublicationRecipient> recipients;
  final String messagePreview;

  @override
  State<InternalPublicationDialog> createState() =>
      _InternalPublicationDialogState();
}

class _InternalPublicationDialogState extends State<InternalPublicationDialog> {
  late final Set<String> _selectedIds;
  bool _pushEnabled = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.recipients.map((item) => item.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 420 ? 12 : 24,
        vertical: 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: size.height * .88,
        ),
        child: Padding(
          padding: EdgeInsets.all(size.width < 420 ? 16 : 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mit Trainerteam teilen',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Wähle die zuständigen Trainer, Co-Trainer und Mannschaftsverantwortlichen aus. Eltern und Spieler werden hier noch nicht informiert.',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nachrichtenvorschau',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(widget.messagePreview),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_selectedIds.length} von ${widget.recipients.length} Empfängern',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(widget.recipients.map((item) => item.id));
                      }),
                      icon: const Icon(Icons.select_all_rounded),
                      label: const Text('Alle auswählen'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(_selectedIds.clear),
                      icon: const Icon(Icons.deselect_rounded),
                      label: const Text('Alle abwählen'),
                    ),
                  ],
                ),
                const Divider(),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.recipients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final recipient = widget.recipients[index];
                    final selected = _selectedIds.contains(recipient.id);
                    final details = [
                      if (recipient.functions.isNotEmpty)
                        recipient.functions.join(' / '),
                      if (recipient.teams.isNotEmpty)
                        recipient.teams.join(', '),
                    ].join(' · ');
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selectedIds.add(recipient.id);
                        } else {
                          _selectedIds.remove(recipient.id);
                        }
                      }),
                      title: Text(
                        '${recipient.name}${recipient.isSender ? ' (Du)' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: details.isEmpty
                          ? null
                          : Text(
                              details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    );
                  },
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _pushEnabled,
                  onChanged: (value) => setState(() => _pushEnabled = value),
                  title: const Text(
                    'Zusätzlich als Pushnachricht senden',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_selectedIds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Bitte mindestens eine Person auswählen.',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  InternalPublicationSelection(
                                    recipientIds: _selectedIds.toList(),
                                    pushEnabled: _pushEnabled,
                                  ),
                                ),
                        icon: const Icon(Icons.campaign_rounded),
                        label: const Text('Mit Trainerteam teilen'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleasePreviewRow extends StatelessWidget {
  const _ReleasePreviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

@visibleForTesting
class MatchCommunicationActions extends StatelessWidget {
  const MatchCommunicationActions({
    super.key,
    required this.match,
    required this.onPublishInternal,
    required this.onReleaseFamily,
    this.denseMobile = false,
  });

  final MatchdayModel match;
  final VoidCallback onPublishInternal;
  final VoidCallback onReleaseFamily;
  final bool denseMobile;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final actionSpecs = <AdaptiveActionSpec>[
      if (match.canPublishInternal)
        AdaptiveActionSpec(
          label: 'Mit Trainerteam teilen',
          icon: Icons.admin_panel_settings_outlined,
          onPressed: onPublishInternal,
        ),
      if (match.canReleaseFamily && match.familyReleasedAt == null)
        AdaptiveActionSpec(
          label: 'Für Eltern & Spieler freigeben',
          icon: Icons.family_restroom_rounded,
          onPressed: onReleaseFamily,
          primary: true,
        )
    ];
    final releaseStatus = match.familyReleasedAt != null
        ? denseMobile
            ? Container(
                key: const ValueKey('compact-family-release-status'),
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppColors.teal.withValues(alpha: .24),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.teal,
                    ),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Familien freigegeben',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const Chip(
                avatar: Icon(Icons.verified_rounded, size: 17),
                label: Text('Familien freigegeben'),
              )
        : null;
    if (compact && denseMobile) {
      final buttons = <Widget>[
        if (match.canPublishInternal)
          Tooltip(
            message: 'Mit Trainerteam teilen',
            child: OutlinedButton.icon(
              key: const ValueKey('compact-internal-publication-action'),
              onPressed: onPublishInternal,
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
              label: const Text(
                'Trainerteam',
                maxLines: 1,
                semanticsLabel: 'Mit Trainerteam teilen',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        if (match.canReleaseFamily && match.familyReleasedAt == null)
          Tooltip(
            message: 'Für Eltern & Spieler freigeben',
            child: FilledButton.icon(
              key: const ValueKey('compact-family-release-action'),
              onPressed: onReleaseFamily,
              icon: const Icon(Icons.family_restroom_rounded, size: 17),
              label: const Text(
                'Familien',
                maxLines: 1,
                semanticsLabel: 'Für Eltern und Spieler freigeben',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
      ];
      final items = <Widget>[
        ...buttons,
        if (releaseStatus != null) releaseStatus,
      ];
      return Row(
        key: const ValueKey('match-communication-dense-mobile-actions'),
        children: [
          for (var index = 0; index < items.length; index++) ...[
            Expanded(child: items[index]),
            if (index != items.length - 1) const SizedBox(width: 5),
          ],
        ],
      );
    }
    if (compact) {
      return Column(
        key: const ValueKey('match-communication-mobile-actions'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actionSpecs.isNotEmpty)
            AdaptiveActionBar(actions: actionSpecs, spacing: 6),
          if (actionSpecs.isNotEmpty && releaseStatus != null)
            const SizedBox(height: 6),
          if (releaseStatus != null)
            Align(alignment: Alignment.center, child: releaseStatus),
        ],
      );
    }
    final actions = <Widget>[
      for (final action in actionSpecs)
        if (action.primary)
          FilledButton.icon(
            onPressed: action.onPressed,
            icon: Icon(action.icon, size: 17),
            label: AdaptiveButtonLabel(action.label),
          )
        else
          OutlinedButton.icon(
            onPressed: action.onPressed,
            icon: Icon(action.icon, size: 17),
            label: AdaptiveButtonLabel(action.label),
          ),
      if (releaseStatus != null) releaseStatus,
    ];
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: actions,
      ),
    );
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
    final home = details?.isHome != false
        ? match.ownTeamName
        : details?.opponent ?? 'Gegner';
    final away = details?.isHome != false
        ? details?.opponent ?? 'Gegner'
        : match.ownTeamName;
    final our = ticker?.ourGoals ?? details?.ourGoals;
    final their = ticker?.theirGoals ?? details?.theirGoals;
    final homeGoals = details?.isHome != false ? our : their;
    final awayGoals = details?.isHome != false ? their : our;
    final date = match.startAt.toLocal();
    final dateLine = '${date.day}.${date.month}.${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} Uhr · ${match.location}';
    final crestSize = compact ? 34.0 : 46.0;
    final score = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _ScoreTeam(
            name: home,
            isOwnTeam: details?.isHome != false,
            logoUrl: details?.isHome != false
                ? match.ownTeamLogoUrl
                : details?.opponentLogoUrl,
            ownTeamIsPlayingCommunity: match.ownTeamIsPlayingCommunity,
            crestSize: crestSize,
            compact: compact,
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: compact ? 4 : 14),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 14,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            '${homeGoals ?? '–'} : ${awayGoals ?? '–'}',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 22 : 30,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: _ScoreTeam(
            name: away,
            isOwnTeam: details?.isHome == false,
            logoUrl: details?.isHome == false
                ? match.ownTeamLogoUrl
                : details?.opponentLogoUrl,
            ownTeamIsPlayingCommunity: match.ownTeamIsPlayingCommunity,
            crestSize: crestSize,
            compact: compact,
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 16,
        vertical: compact ? 7 : 11,
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
                const SizedBox(height: 3),
                Text(
                  'MATCHDAY SPACE · $dateLine',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                score,
                const SizedBox(height: 5),
                Text(
                  'MATCHDAY SPACE · $dateLine',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );
  }
}

class _MatchdayTabBar extends StatelessWidget {
  const _MatchdayTabBar({
    required this.compact,
    required this.staffView,
    required this.showParentRating,
  });

  final bool compact;
  final bool staffView;
  final bool showParentRating;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return TabBar(
        isScrollable: true,
        tabs: [
          const _WideMatchTab(
            icon: Icons.info_outline_rounded,
            label: 'Übersicht',
          ),
          const _WideMatchTab(icon: Icons.groups_rounded, label: 'Kader'),
          const _WideMatchTab(
            icon: Icons.dashboard_customize_rounded,
            label: 'Aufstellung',
          ),
          if (staffView)
            const _WideMatchTab(
              icon: Icons.auto_awesome_rounded,
              label: 'Autopilot',
            ),
          const _WideMatchTab(icon: Icons.bolt_rounded, label: 'Liveticker'),
          if (staffView)
            const _WideMatchTab(icon: Icons.stars_rounded, label: 'Bewertung'),
          if (showParentRating)
            const _WideMatchTab(icon: Icons.stars_rounded, label: 'Bewertung'),
        ],
      );
    }

    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      tabs: [
        const _CompactMatchTab(icon: Icons.info_outline_rounded, label: 'Info'),
        const _CompactMatchTab(icon: Icons.groups_rounded, label: 'Kader'),
        const _CompactMatchTab(
          icon: Icons.dashboard_customize_rounded,
          label: 'Aufstellung',
        ),
        if (staffView)
          const _CompactMatchTab(
              icon: Icons.auto_awesome_rounded, label: 'Autopilot'),
        const _CompactMatchTab(icon: Icons.bolt_rounded, label: 'Liveticker'),
        if (staffView)
          const _CompactMatchTab(icon: Icons.stars_rounded, label: 'Bewertung'),
        if (showParentRating)
          const _CompactMatchTab(icon: Icons.stars_rounded, label: 'Bewertung'),
      ],
    );
  }
}

class _WideMatchTab extends StatelessWidget {
  const _WideMatchTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tab(
        height: 42,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(label),
          ],
        ),
      );
}

class _CompactMatchTab extends StatelessWidget {
  const _CompactMatchTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Tab(
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreTeam extends StatelessWidget {
  const _ScoreTeam({
    required this.name,
    required this.isOwnTeam,
    required this.logoUrl,
    required this.ownTeamIsPlayingCommunity,
    required this.crestSize,
    required this.compact,
  });
  final String name;
  final bool isOwnTeam;
  final String? logoUrl;
  final bool ownTeamIsPlayingCommunity;
  final double crestSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final crest = isOwnTeam
        ? TeamCrest.ownTeam(
            size: crestSize,
            logoUrl: logoUrl,
            isPlayingCommunity: ownTeamIsPlayingCommunity,
            darkSurface: true,
          )
        : TeamCrest.opponent(
            size: crestSize,
            logoUrl: logoUrl,
            darkSurface: true,
          );
    final label = Text(
      name,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: compact ? 11.5 : 14.5,
      ),
    );
    if (!compact) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          crest,
          const SizedBox(width: 10),
          Flexible(child: label),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [crest, const SizedBox(height: 3), label],
    );
  }
}

class MatchOverview extends StatelessWidget {
  const MatchOverview({
    required this.match,
    required this.staffView,
    this.showLaundryDuty = true,
    super.key,
  });

  final MatchdayModel match;
  final bool staffView;
  final bool showLaundryDuty;

  @override
  Widget build(BuildContext context) {
    final details = match.details;
    final start = match.startAt.toLocal();
    final startTime = '${start.hour.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')} Uhr';
    final date = '${start.day}.${start.month}.${start.year}';
    final location = _valueOrFallback(match.location);
    final competition = _valueOrFallback(details?.competition);
    final matchDay = _valueOrFallback(details?.matchDay);
    final pitch = _valueOrFallback(details?.pitch);
    final referee = _valueOrFallback(details?.referee);
    final essentials = <_OverviewEntry>[
      _OverviewEntry(
        Icons.schedule_rounded,
        'Anstoß',
        startTime,
        date,
      ),
      if (match.meetingAt != null)
        _OverviewEntry(
          Icons.groups_rounded,
          'Treffpunkt',
          '${match.meetingAt!.toLocal().hour.toString().padLeft(2, '0')}:'
              '${match.meetingAt!.toLocal().minute.toString().padLeft(2, '0')} Uhr',
          match.meetingLocation?.trim().isNotEmpty == true
              ? match.meetingLocation!.trim()
              : 'Gemeinsames Treffen',
        ),
      if (match.meetingAt == null &&
          match.meetingLocation?.trim().isNotEmpty == true)
        _OverviewEntry(
          Icons.groups_rounded,
          'Treffpunktort',
          match.meetingLocation!.trim(),
          'Uhrzeit noch offen',
        ),
      _OverviewEntry(
        Icons.timer_outlined,
        'Spielzeit',
        '${details?.periodCount ?? 2} × ${details?.periodMinutes ?? 30} Minuten',
        '${details?.durationMinutes ?? 60} Minuten gesamt',
      ),
    ];
    final organization = <_OverviewEntry>[
      _OverviewEntry(
        Icons.emoji_events_outlined,
        'Wettbewerb',
        competition,
        'Liga, Turnier oder Freundschaftsspiel',
        missing: _isMissing(details?.competition),
      ),
      _OverviewEntry(
        Icons.format_list_numbered_rounded,
        'Spieltag',
        matchDay,
        'Runde oder Spielnummer',
        missing: _isMissing(details?.matchDay),
      ),
      _OverviewEntry(
        Icons.location_on_outlined,
        'Spielstätte',
        location,
        'Austragungsort',
        missing: _isMissing(match.location),
      ),
      _OverviewEntry(
        Icons.sports_rounded,
        'Platz',
        pitch,
        'Zugewiesenes Spielfeld',
        missing: _isMissing(details?.pitch),
      ),
      _OverviewEntry(
        Icons.person_outline_rounded,
        'Schiedsrichter',
        referee,
        'Spielleitung',
        missing: _isMissing(details?.referee),
      ),
    ];
    final status = switch (details?.status) {
      MatchStatus.live ||
      MatchStatus.halfTime ||
      MatchStatus.interrupted =>
        'Läuft gerade',
      MatchStatus.finished || MatchStatus.recorded => 'Beendet',
      MatchStatus.postponed => 'Verschoben',
      MatchStatus.confirmed => 'Bestätigt',
      MatchStatus.cancelled => 'Abgesagt',
      _ => 'Geplant',
    };
    final statusColor = switch (details?.status) {
      MatchStatus.live ||
      MatchStatus.halfTime ||
      MatchStatus.interrupted =>
        const Color(0xFF0F8A5F),
      MatchStatus.cancelled => const Color(0xFFC62828),
      MatchStatus.finished || MatchStatus.recorded => AppColors.blue,
      _ => AppColors.yellowDark,
    };
    final statusIcon = switch (details?.status) {
      MatchStatus.live ||
      MatchStatus.halfTime ||
      MatchStatus.interrupted =>
        Icons.sensors_rounded,
      MatchStatus.cancelled => Icons.event_busy_rounded,
      MatchStatus.finished || MatchStatus.recorded => Icons.flag_rounded,
      _ => Icons.event_available_rounded,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 680
                ? 2
                : 1;
        final gap = compact ? 10.0 : 14.0;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Scrollbar(
          child: ListView(
            key: const ValueKey('match-overview-list'),
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(0, 4, 0, compact ? 44 : 30),
            children: [
              _OverviewStatusCard(
                status: status,
                statusColor: statusColor,
                statusIcon: statusIcon,
                fixtureKind:
                    details?.isHome != false ? 'Heimspiel' : 'Auswärtsspiel',
                dateLine: '$date · $startTime',
              ),
              if (showLaundryDuty) ...[
                SizedBox(height: compact ? 8 : 12),
                KitLaundryDutyCard(
                  matchId: match.id,
                  staffView: staffView,
                  compact: compact,
                ),
              ],
              SizedBox(height: compact ? 12 : 22),
              const _OverviewSectionHeader(
                icon: Icons.flash_on_rounded,
                title: 'Auf einen Blick',
                subtitle: 'Die wichtigsten Zeiten für den Spieltag',
              ),
              SizedBox(height: compact ? 7 : 10),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final entry in essentials)
                    SizedBox(
                      width: tileWidth,
                      child: _OverviewTile(entry: entry),
                    ),
                ],
              ),
              SizedBox(height: compact ? 16 : 28),
              const _OverviewSectionHeader(
                icon: Icons.assignment_outlined,
                title: 'Organisation',
                subtitle: 'Rahmendaten, Ort und Verantwortliche',
              ),
              SizedBox(height: compact ? 7 : 10),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final entry in organization)
                    SizedBox(
                      width: tileWidth,
                      child: _OverviewTile(entry: entry),
                    ),
                ],
              ),
              if (details?.notes?.trim().isNotEmpty == true) ...[
                SizedBox(height: compact ? 16 : 28),
                const _OverviewSectionHeader(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Hinweise',
                  subtitle: 'Wichtige Informationen für alle Beteiligten',
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(compact ? 16 : 20),
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.yellowDark.withValues(alpha: .2),
                    ),
                  ),
                  child: Text(
                    details!.notes!.trim(),
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OverviewStatusCard extends StatelessWidget {
  const _OverviewStatusCard({
    required this.status,
    required this.statusColor,
    required this.statusIcon,
    required this.fixtureKind,
    required this.dateLine,
  });

  final String status;
  final Color statusColor;
  final IconData statusIcon;
  final String fixtureKind;
  final String dateLine;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.appColors.surfaceRaised,
            AppColors.yellow.withValues(alpha: .08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.appColors.outline),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 50,
            height: compact ? 38 : 50,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: compact ? 20 : 25,
            ),
          ),
          SizedBox(width: compact ? 9 : 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SPIELSTATUS',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: (compact
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.titleLarge)
                      ?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  dateLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 11,
              vertical: compact ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              fixtureKind,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSectionHeader extends StatelessWidget {
  const _OverviewSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Row(
      children: [
        Container(
          width: compact ? 30 : 34,
          height: compact ? 30 : 34,
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: compact ? 16 : 18, color: AppColors.yellow),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: (compact
                        ? Theme.of(context).textTheme.titleSmall
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewEntry {
  const _OverviewEntry(
    this.icon,
    this.label,
    this.value,
    this.supporting, {
    this.missing = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String supporting;
  final bool missing;
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({required this.entry});

  final _OverviewEntry entry;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      key: ValueKey('match-overview-${entry.label}'),
      constraints: BoxConstraints(minHeight: compact ? 74 : 104),
      padding: EdgeInsets.all(compact ? 10 : 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.appColors.surfaceRaised,
            entry.missing
                ? context.appColors.surfaceMuted
                : AppColors.yellow.withValues(alpha: .035),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appColors.outline),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: .025),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 48,
            height: compact ? 38 : 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.yellow.withValues(alpha: .2),
                  AppColors.yellow.withValues(alpha: .08),
                ],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              entry.icon,
              color: AppColors.blue,
              size: compact ? 19 : 23,
            ),
          ),
          SizedBox(width: compact ? 9 : 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: entry.missing ? AppColors.muted : AppColors.navy,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.supporting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                        fontSize: 10.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _isMissing(String? value) => value == null || value.trim().isEmpty;

String _valueOrFallback(String? value) =>
    _isMissing(value) ? 'Noch nicht festgelegt' : value!.trim();

class MatchSquadTab extends ConsumerStatefulWidget {
  const MatchSquadTab({
    super.key,
    required this.match,
    required this.allPlayers,
    required this.editable,
    required this.onSaved,
    required this.onReload,
    this.tournamentPlanning = false,
    this.loadingPlayers = false,
  });
  final MatchdayModel match;
  final List<PlayerModel> allPlayers;
  final bool editable;
  final bool tournamentPlanning;
  final bool loadingPlayers;
  final Future<void> Function(MatchSquadModel squad) onSaved;
  final Future<void> Function() onReload;

  @override
  ConsumerState<MatchSquadTab> createState() => _SquadTabState();
}

class _SquadTeamFilter extends StatelessWidget {
  const _SquadTeamFilter({
    required this.value,
    required this.teams,
    required this.onChanged,
  });

  static const _allTeamsValue = '__all_teams__';

  final String? value;
  final List<({String id, String name})> teams;
  final ValueChanged<String?> onChanged;

  String get _selectedLabel =>
      teams
          .where((team) => team.id == value)
          .map((team) => team.name)
          .firstOrNull ??
      'Alle Mannschaften';

  Future<void> _openPicker(BuildContext context) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: min(MediaQuery.sizeOf(sheetContext).height * .72, 520),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.yellowSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.groups_2_rounded,
                      color: AppColors.gold,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Mannschaft auswählen',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text(
                          'Der Kader bleibt mannschaftsübergreifend erhalten.',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Auswahl schließen',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                shrinkWrap: true,
                children: [
                  _SquadTeamFilterOption(
                    key: const ValueKey('squad-team-filter-option-all'),
                    label: 'Alle Mannschaften',
                    selected: value == null,
                    onTap: () => Navigator.pop(sheetContext, _allTeamsValue),
                  ),
                  for (final team in teams)
                    _SquadTeamFilterOption(
                      key: ValueKey('squad-team-filter-option-${team.id}'),
                      label: team.name,
                      selected: value == team.id,
                      onTap: () => Navigator.pop(sheetContext, team.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !context.mounted) return;
    onChanged(selection == _allTeamsValue ? null : selection);
  }

  @override
  Widget build(BuildContext context) => Material(
        key: const ValueKey('squad-team-filter-dropdown'),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPicker(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.yellowSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 20,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mannschaft anzeigen',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        _selectedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );
}

class _SquadTeamFilterOption extends StatelessWidget {
  const _SquadTeamFilterOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? AppColors.yellowSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            dense: true,
            minTileHeight: 48,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: onTap,
            leading: Icon(
              selected ? Icons.check_circle_rounded : Icons.shield_outlined,
              color: selected ? AppColors.success : AppColors.muted,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
            trailing: selected
                ? const Text(
                    'Aktiv',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
        ),
      );
}

class _SquadTabState extends ConsumerState<MatchSquadTab> {
  late Map<String, NominationStatus> _selected;
  String? _teamFilterId;
  final Set<String> _attendanceSaving = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = _eligibleSelection(widget.match);
    _teamFilterId = widget.allPlayers.any(
      (player) => player.teamId == widget.match.teamId,
    )
        ? widget.match.teamId
        : null;
  }

  @override
  void didUpdateWidget(covariant MatchSquadTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving &&
        _squadFingerprint(oldWidget.match) != _squadFingerprint(widget.match)) {
      _selected = _eligibleSelection(widget.match);
    } else if (!_saving) {
      // Bereits gespeicherte Spieler können inzwischen pausiert, ausgetreten
      // oder in eine andere Jugend gewechselt sein. Solche unsichtbaren
      // Alt-Einträge dürfen den nächsten Speichervorgang nicht blockieren.
      _selected = retainEligibleSquadSelection(
        _selected,
        widget.allPlayers
            .where((player) => !_isDeclined(player.id))
            .map((player) => player.id),
      );
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

  List<PlayerModel> get _eligibleVisiblePlayers =>
      _visiblePlayers.where((player) => !_isDeclined(player.id)).toList();

  int get _visibleSelectedCount {
    final visibleIds =
        _eligibleVisiblePlayers.map((player) => player.id).toSet();
    return _selected.keys.where(visibleIds.contains).length;
  }

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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = AppBreakpoints.isCompact(constraints.maxWidth);
          if (!widget.editable) {
            final members = widget.match.squad?.members
                    .where(
                        (member) => member.status == NominationStatus.nominated)
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
                        child:
                            Text(member.player.shirtNumber?.toString() ?? 'FC'),
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
          final eligibleVisiblePlayers = _eligibleVisiblePlayers;
          final availableTeams = _availableTeams;
          return ListView(
            key: const ValueKey('squad-responsive-list'),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              if (widget.loadingPlayers) ...[
                const _SquadLoadingStatus(),
                SizedBox(height: compact ? 8 : 12),
              ],
              if (availableTeams.length > 1) ...[
                if (constraints.maxWidth < AppBreakpoints.narrow)
                  _SquadTeamFilter(
                    value: _teamFilterId,
                    teams: availableTeams,
                    onChanged: (value) => setState(() => _teamFilterId = value),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Alle Mannschaften'),
                          selected: _teamFilterId == null,
                          onSelected: (_) =>
                              setState(() => _teamFilterId = null),
                        ),
                        for (final team in availableTeams)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                              label: Text(team.name),
                              selected: _teamFilterId == team.id,
                              onSelected: (_) =>
                                  setState(() => _teamFilterId = team.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              if (compact) ...[
                Row(
                  key: const ValueKey('tournament-squad-compact-summary'),
                  children: [
                    Expanded(
                      child: Text(
                        '$_visibleSelectedCount/${eligibleVisiblePlayers.length} im Kader',
                        key: const ValueKey('squad-selection-summary'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('tournament-squad-select-all'),
                      tooltip: 'Alle auswählen',
                      onPressed: _saving || eligibleVisiblePlayers.isEmpty
                          ? null
                          : _selectAll,
                      icon: const Icon(Icons.select_all_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('tournament-squad-deselect-all'),
                      tooltip: 'Alle abwählen',
                      onPressed:
                          _saving || _selected.isEmpty ? null : _deselectAll,
                      icon: const Icon(Icons.deselect_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  key: const ValueKey('tournament-squad-compact-actions'),
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey(
                          'tournament-squad-nominate-action',
                        ),
                        onPressed: _saving || !widget.match.canNominateSquad
                            ? null
                            : _publish,
                        icon: const Icon(Icons.campaign_outlined, size: 17),
                        label: const Text('Nominieren'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('tournament-squad-save-action'),
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined, size: 17),
                        label: Text(_saving ? 'Speichert …' : 'Speichern'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  '$_visibleSelectedCount ausgewählt · '
                  '${eligibleVisiblePlayers.length} verfügbar',
                  key: const ValueKey('squad-selection-summary'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                AdaptiveActionBar(
                  key: const ValueKey('squad-adaptive-actions'),
                  actions: [
                    AdaptiveActionSpec(
                      label: 'Alle auswählen',
                      icon: Icons.select_all_rounded,
                      onPressed: _saving || eligibleVisiblePlayers.isEmpty
                          ? null
                          : _selectAll,
                    ),
                    AdaptiveActionSpec(
                      label: 'Alle abwählen',
                      icon: Icons.deselect_rounded,
                      onPressed:
                          _saving || _selected.isEmpty ? null : _deselectAll,
                    ),
                    AdaptiveActionSpec(
                      label: widget.tournamentPlanning
                          ? 'Turnier-Kader nominieren'
                          : 'Kader verbindlich nominieren',
                      icon: Icons.campaign_outlined,
                      onPressed: _saving || !widget.match.canNominateSquad
                          ? null
                          : _publish,
                    ),
                    AdaptiveActionSpec(
                      label: _saving ? 'Wird gespeichert …' : 'Kader speichern',
                      icon: Icons.save_outlined,
                      onPressed: _saving ? null : _save,
                      primary: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.tournamentPlanning
                        ? 'Diese Auswahl gilt für das gesamte Turnier. '
                            'Rückmeldungen können hier direkt korrigiert werden.'
                        : 'Die automatische Startelf berücksichtigt nur zugesagte Spieler. '
                            'Trainer können Rückmeldungen hier direkt korrigieren.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                  ),
                ),
              ],
              SizedBox(height: compact ? 6 : 12),
              if (widget.allPlayers.isEmpty && !widget.loadingPlayers)
                EmptyState(
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
              else
                for (final player in visiblePlayers)
                  Builder(
                    builder: (context) {
                      final declined = _isDeclined(player.id);
                      final unavailable =
                          declined || player.status != PlayerStatus.active;
                      return Card(
                        margin: EdgeInsets.only(bottom: compact ? 3 : 8),
                        child: ListTile(
                          enabled: !unavailable,
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
                          title: Text(
                            player.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Wrap(
                            spacing: 7,
                            runSpacing: compact ? 1 : 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              PlayerTeamChip(player: player, compact: true),
                              Text(
                                declined
                                    ? 'Abgesagt · nicht für den Kader verfügbar'
                                    : player.status == PlayerStatus.injured
                                        ? 'Verletzt · bis zur Aktivierung gesperrt'
                                        : player.position ?? 'Spieler',
                              ),
                              _AttendanceMenu(
                                status: _attendanceStatus(player.id),
                                saving: _attendanceSaving.contains(player.id),
                                onSelected: (status) =>
                                    _setAttendance(player, status),
                              ),
                            ],
                          ),
                          trailing: Checkbox(
                            value: unavailable
                                ? false
                                : _selected.containsKey(player.id),
                            onChanged: unavailable
                                ? null
                                : (value) => setState(() {
                                      if (value == true) {
                                        _selected[player.id] =
                                            NominationStatus.nominated;
                                      } else {
                                        _selected.remove(player.id);
                                      }
                                    }),
                          ),
                          onTap: unavailable
                              ? null
                              : () => setState(() {
                                    if (_selected.containsKey(player.id)) {
                                      _selected.remove(player.id);
                                    } else {
                                      _selected[player.id] =
                                          NominationStatus.nominated;
                                    }
                                  }),
                        ),
                      );
                    },
                  ),
            ],
          );
        },
      );

  Future<bool> _save() async {
    final repository = ref.read(repositoryProvider);
    setState(() => _saving = true);
    try {
      final eligibleIds = widget.allPlayers
          .where((player) => !_isDeclined(player.id))
          .map((player) => player.id)
          .toSet();
      final removedUnavailable =
          _selected.keys.where((id) => !eligibleIds.contains(id)).length;
      if (removedUnavailable > 0) {
        _selected = retainEligibleSquadSelection(_selected, eligibleIds);
      }
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
      if (mounted) {
        _message(
          removedUnavailable == 0
              ? 'Kader wurde gespeichert.'
              : 'Kader wurde gespeichert. $removedUnavailable nicht mehr '
                  'verfügbare Auswahl wurde entfernt.',
        );
      }
      // Reconcile the complete match after applying the immediate response.
      // This also refreshes a server-generated default lineup without making
      // the successful squad save depend on a second request.
      unawaited(widget.onReload());
      return true;
    } on DioException catch (error) {
      if (_isQueuedOfflineWrite(error)) {
        if (mounted) {
          _message(
            'Kader wurde offline gespeichert und wird automatisch '
            'übertragen, sobald die Verbindung wieder stabil ist.',
          );
        }
        return true;
      }
      if (mounted) _message(_squadSaveError(error));
      return false;
    } catch (error) {
      if (mounted) {
        _message(
          error is StateError
              ? 'Kader konnte nicht gespeichert werden: ${error.message}'
              : 'Kader konnte nicht gespeichert werden. Bitte erneut laden '
                  'und nochmals versuchen.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    final repository = ref.read(repositoryProvider);
    if (!await _save() || !mounted) return;
    late final Map<String, dynamic> preview;
    try {
      preview = await repository.nominationPreview(widget.match.id);
    } catch (error) {
      if (mounted) {
        _message(
            'Vorschau der Kadernominierung konnte nicht geladen werden: $error');
      }
      return;
    }
    if (!mounted) return;
    final players = (preview['players'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final isLateNomination = preview['isLateNomination'] == true;
    final hasNewPlayers = players.isNotEmpty;
    var pushEnabled = hasNewPlayers;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            isLateNomination
                ? 'Nachnominierte Spieler informieren?'
                : hasNewPlayers
                    ? widget.tournamentPlanning
                        ? 'Turnier-Kader nominieren?'
                        : 'Kader nominieren?'
                    : 'Kader aktualisieren?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tournamentPlanning
                      ? '${preview['title'] ?? widget.match.title}'
                      : '${preview['title'] ?? widget.match.title} · ${preview['opponent'] ?? widget.match.details?.opponent ?? 'Gegner'}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (hasNewPlayers) ...[
                  Text(
                    isLateNomination
                        ? 'Nur neu nachnominiert: ${players.map((item) => item['name']).join(', ')}'
                        : players.map((item) => item['name']).join(', '),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${preview['recipients'] ?? 0} zugehörige Spieleraccounts und Sorgeberechtigte erhalten eine neue Rückmeldungsanfrage. Bereits informierte Familien werden nicht erneut benachrichtigt.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: pushEnabled,
                    onChanged: (value) =>
                        setDialogState(() => pushEnabled = value),
                    title: const Text('Zusätzlich als Pushnachricht senden'),
                    subtitle: const Text(
                      'In-App wird die Anfrage immer bereitgestellt.',
                    ),
                  ),
                ] else
                  const Text(
                    'Alle nominierten Spieler wurden bereits informiert. Der Kader wird aktualisiert, ohne eine neue Rückmeldungsanfrage zu versenden.',
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
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.campaign_rounded),
              label: Text(
                isLateNomination
                    ? 'Nachnominierung veröffentlichen'
                    : hasNewPlayers
                        ? 'Verbindlich nominieren'
                        : 'Kader aktualisieren',
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await repository.publishMatchSquad(
        widget.match.id,
        pushEnabled: pushEnabled,
      );
      if (!mounted) return;
      ref.invalidate(personalResponsesProvider);
      ref.invalidate(eventsProvider);
      await widget.onReload();
      if (mounted) {
        final publication = result['publication'] as Map<String, dynamic>?;
        final recipients = publication?['recipients'] as int? ?? 0;
        final requestedPlayers =
            publication?['requestedPlayers'] as int? ?? players.length;
        final sent = publication?['sent'] as int? ?? 0;
        _message(
          requestedPlayers == 0
              ? 'Kader aktualisiert · keine erneute Benachrichtigung'
              : '${isLateNomination ? 'Nachnominierung' : 'Nominierung'} veröffentlicht · $requestedPlayers Spieler · $recipients Empfänger${pushEnabled ? ' · $sent Push zugestellt' : ' · ohne Push'}',
        );
      }
    } on DioException catch (error) {
      if (mounted) {
        _message(
          _isQueuedOfflineWrite(error)
              ? 'Veröffentlichung wurde offline gespeichert und wird '
                  'automatisch übertragen.'
              : 'Nominierung konnte nicht veröffentlicht werden: '
                  '${_dioMessage(error)}',
        );
      }
    } catch (_) {
      if (mounted) {
        _message('Nominierung konnte nicht veröffentlicht werden.');
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _selectAll() {
    setState(() {
      for (final player in _eligibleVisiblePlayers) {
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

  bool _isDeclined(String playerId) =>
      _attendanceStatus(playerId) == AttendanceStatus.no;

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
      if (status == AttendanceStatus.no && mounted) {
        setState(() => _selected.remove(player.id));
      }
      await widget.onReload();
      if (mounted) {
        _message('Rückmeldung für ${player.displayName} gespeichert.');
      }
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

  Map<String, NominationStatus> _eligibleSelection(MatchdayModel match) =>
      retainEligibleSquadSelection(
        _selectionFrom(match),
        widget.allPlayers.where((player) {
          final status = match.attendance
                  .where((reply) => reply.playerId == player.id)
                  .map((reply) => reply.status)
                  .firstOrNull ??
              AttendanceStatus.unknown;
          return status != AttendanceStatus.no;
        }).map((player) => player.id),
      );

  String _squadFingerprint(MatchdayModel match) {
    final members = match.squad?.members ?? const <SquadMemberModel>[];
    return members
        .map((member) => '${member.player.id}:${member.status.name}')
        .join('|');
  }
}

bool _isQueuedOfflineWrite(DioException error) =>
    error.error is OfflineWriteQueuedException;

String _dioMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map && data['message'] is String) {
    final message = (data['message'] as String).trim();
    if (message.isNotEmpty && message != 'Internal server error') {
      return message;
    }
  }
  return switch (error.response?.statusCode) {
    400 => 'Die Auswahl enthält einen nicht verfügbaren Spieler.',
    403 => 'Für diese Mannschaft fehlt die Berechtigung.',
    404 => 'Das Spiel wurde nicht gefunden.',
    408 => 'Die Speicherung hat das Zeitlimit des Servers überschritten.',
    429 => 'Der Server erhält gerade zu viele Anfragen. Bitte kurz warten.',
    500 =>
      'Die Vereinsverwaltung konnte die Speicherung nicht abschließen (500).',
    502 => 'Die Vereinsverwaltung war vorübergehend nicht erreichbar (502).',
    503 => 'Die Vereinsverwaltung ist vorübergehend ausgelastet (503).',
    504 =>
      'Die Speicherung wurde vom Server nicht rechtzeitig abgeschlossen (504).',
    _ => switch (error.type) {
        DioExceptionType.connectionTimeout =>
          'Die Verbindung zur Vereinsverwaltung konnte nicht rechtzeitig aufgebaut werden.',
        DioExceptionType.receiveTimeout =>
          'Die Vereinsverwaltung hat nicht rechtzeitig geantwortet.',
        DioExceptionType.connectionError =>
          'Die Vereinsverwaltung ist aktuell nicht erreichbar.',
        _ => 'Die Speicherung konnte nicht abgeschlossen werden.',
      },
  };
}

String _squadSaveError(DioException error) =>
    'Kader konnte nicht gespeichert werden: ${_dioMessage(error)}';

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
          'Offen',
          AppColors.muted,
          Icons.schedule_rounded
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
      return ListView(
        padding: EdgeInsets.zero,
        children: const [
          EmptyState(
            icon: Icons.group_add_outlined,
            title: 'Zuerst den Kader festlegen',
            message:
                'Die Aufstellung verwendet ausschließlich nominierte Spieler.',
          ),
        ],
      );
    }
    final lineup = widget.match.squad!.lineup;
    if (!widget.editable && lineup == null) {
      return ListView(
        padding: EdgeInsets.zero,
        children: const [
          EmptyState(
            icon: Icons.visibility_off_outlined,
            title: 'Aufstellung noch nicht veröffentlicht',
            message:
                'Sobald die Aufstellung freigegeben ist, erscheint sie hier.',
          ),
        ],
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
                  onPressed: _saving
                      ? null
                      : () => _save(LineupStatus.internallyApproved),
                  icon: const Icon(Icons.publish_rounded),
                  label: const Text('Aufstellung intern speichern'),
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
                              color: context.appColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(13),
                              border:
                                  Border.all(color: context.appColors.outline),
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
                    const SizedBox(height: 6),
                    Row(
                      key: compact
                          ? const ValueKey('compact-lineup-save-actions')
                          : null,
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _save(LineupStatus.draft),
                            icon: Icon(
                              Icons.save_outlined,
                              size: compact ? 16 : 18,
                            ),
                            label: const Text('Speichern'),
                            style: compact
                                ? OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _save(LineupStatus.internallyApproved),
                            icon: Icon(
                              Icons.publish_rounded,
                              size: compact ? 16 : 18,
                            ),
                            label: const Text('Intern speichern'),
                            style: compact
                                ? FilledButton.styleFrom(
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  )
                                : null,
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
              final hinge = verticalSeparatingFeatureFor(
                context,
                availableWidth: constraints.maxWidth,
              );
              if (hinge != null &&
                  hinge.left >= 250 &&
                  constraints.maxWidth - hinge.right >= 250) {
                final leftWidth = hinge.left;
                final rightWidth = constraints.maxWidth - hinge.right;
                final pitchWidth = min(leftWidth, 720.0).toDouble();
                final pitchHeight = min(
                  constraints.maxHeight - (widget.editable ? 32 : 0),
                  pitchWidth * .9,
                ).toDouble();
                return Row(
                  key: const ValueKey('matchday-foldable-lineup'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: leftWidth,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _buildPitch(pitchWidth, pitchHeight),
                      ),
                    ),
                    SizedBox(width: hinge.width),
                    SizedBox(
                      width: rightWidth,
                      height: constraints.maxHeight,
                      child: _buildBench(vertical: true),
                    ),
                  ],
                );
              }
              final wide = constraints.maxWidth >= 720;
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
                  child: Semantics(
                    button: widget.editable,
                    label:
                        '${_positions[index].player.name}, Position ${_positions[index].positionCode}',
                    hint: widget.editable
                        ? 'Antippen, um Spieler und Position zu bearbeiten.'
                        : null,
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
                      onPanEnd: widget.editable
                          ? (_) => _schedulePositionSave()
                          : null,
                      child: _PlayerMarker(
                        position: _positions[index],
                        width: markerWidth,
                      ),
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
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.appColors.outline),
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
      color: context.appColors.surfaceMuted,
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
              status == LineupStatus.internallyApproved
                  ? 'Aufstellung wurde intern gespeichert.'
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

class _SquadLoadingStatus extends StatelessWidget {
  const _SquadLoadingStatus();

  @override
  Widget build(BuildContext context) => Semantics(
        key: const ValueKey('squad-player-loading'),
        label: 'Kader wird geladen',
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.yellow.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(12, 9, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Kader wird geladen …',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ],
            ),
          ),
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
    if (player.status == PlayerStatus.active) {
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
  bool _syncRequested = false;
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
  late final LiveGoalSoundTracker _goalSoundTracker;
  late final LiveGoalSoundPlayer _goalSoundPlayer;

  @override
  void initState() {
    super.initState();
    _stableElapsedClock = StableElapsedClock();
    _synchronizeClock(_ticker);
    _goalSoundTracker = LiveGoalSoundTracker(
      fcIsHome: widget.match.details?.isHome != false,
    );
    _goalSoundTracker.observe(_ticker);
    _goalSoundPlayer = LiveGoalSoundPlayer();
    unawaited(_goalSoundPlayer.prepare());
    _focusData = ValueNotifier(_tickerFocusData(_ticker));
    unawaited(_loadPending());
    _queuePoller = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (mounted) {
          unawaited(_synchronizePending(showSuccess: false));
        }
      },
    );
    _scheduleNextClockTick(immediate: true);
  }

  @override
  void didUpdateWidget(covariant _TickerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverTicker = widget.match.ticker;
    final previousServerTicker = oldWidget.match.ticker;
    final previousServerSequence = oldWidget.match.ticker?.lastSequence ?? 0;
    _goalSoundTracker.updateSide(
      fcIsHome: widget.match.details?.isHome != false,
    );
    _handleGoalSoundUpdate(serverTicker);
    final serverReset = serverTicker != null &&
        isResetLiveTickerSnapshot(serverTicker) &&
        (previousServerTicker == null ||
            !isResetLiveTickerSnapshot(previousServerTicker));
    if (_optimisticTicker != null &&
        serverTicker != null &&
        (serverReset || serverTicker.lastSequence > previousServerSequence)) {
      _optimisticTicker = null;
    }
    final ticker = _ticker;
    final previousTicker = previousServerTicker;
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
    unawaited(_goalSoundPlayer.dispose());
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
      TickerEventType.interruption => TickerStatus.paused,
      TickerEventType.injury => TickerStatus.interrupted,
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
    final acknowledgedClientIds = ticker.events
        .map((event) => event.clientEventId)
        .whereType<String>()
        .toSet();
    final pendingOurGoals = _pending.where((action) {
      if (acknowledgedClientIds.contains(action.clientEventId)) return false;
      return (fcIsHome && action.type == TickerEventType.homeGoal) ||
          (!fcIsHome && action.type == TickerEventType.awayGoal);
    }).length;
    final pendingTheirGoals = _pending.where((action) {
      if (acknowledgedClientIds.contains(action.clientEventId)) return false;
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
      ownTeamName: widget.match.ownTeamName,
      ownTeamLogoUrl: widget.match.ownTeamLogoUrl,
      ownTeamIsPlayingCommunity: widget.match.ownTeamIsPlayingCommunity,
      opponent: widget.match.details?.opponent ?? 'Gegner',
      opponentLogoUrl: widget.match.details?.opponentLogoUrl,
      periodLabel: matchPeriodLabel(ticker.currentPeriod, periodCount),
      status: ticker.status,
      currentPeriod: ticker.currentPeriod,
      periodCount: periodCount,
    );
  }

  void _applyServerAcknowledgement(LiveTickerModel acknowledgement) {
    if (!mounted) return;
    final merged = mergeLiveTickerSnapshot(_ticker, acknowledgement);
    _handleGoalSoundUpdate(merged);
    setState(() => _optimisticTicker = merged);
    _synchronizeClock(merged);
    _lastRenderedElapsedSeconds = -1;
    _scheduleNextClockTick(immediate: true);
    _focusData.value = _tickerFocusData(merged);
  }

  void _handleGoalSoundUpdate(LiveTickerModel? ticker) {
    final newGoalSounds = _goalSoundTracker.observe(ticker);
    for (final sound in newGoalSounds) {
      unawaited(_goalSoundPlayer.play(sound));
    }
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
          ourGoals: data.ourGoals,
          theirGoals: data.theirGoals,
          ownTeamName: data.ownTeamName,
          ownTeamLogoUrl: data.ownTeamLogoUrl,
          ownTeamIsPlayingCommunity: data.ownTeamIsPlayingCommunity,
          opponent: data.opponent,
          opponentLogoUrl: data.opponentLogoUrl,
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
    return ListView(
      key: const ValueKey('desktop-live-ticker-scroll-view'),
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 24),
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
                label: Text('Tor ${widget.match.ownTeamShortName}'),
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
              if (ticker.status == TickerStatus.paused ||
                  ticker.status == TickerStatus.interrupted)
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
        Text(
          'Spielverlauf',
          key: const ValueKey('desktop-live-ticker-history-heading'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
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

  Widget _mobileGoalButtons() => Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _busy ? null : () => _goal(true),
              icon: const Icon(Icons.sports_soccer_rounded, size: 18),
              label: AdaptiveButtonLabel(
                'Tor ${widget.match.ownTeamShortName}',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _busy ? null : () => _goal(false),
              icon: const Icon(Icons.sports_soccer_rounded, size: 18),
              label: const AdaptiveButtonLabel('Tor Gegner'),
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
      if (ticker.status == TickerStatus.paused ||
          ticker.status == TickerStatus.interrupted)
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
          title: Text(
            _eventTitle(
              event,
              fcIsHome: fcIsHome,
              ownTeamName: widget.match.ownTeamName,
            ),
          ),
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
            builder: (context, data, _) {
              VoidCallback? onClockControl;
              var clockControlLabel = '';
              var clockControlIcon = Icons.play_arrow_rounded;
              final currentTicker = _ticker;
              final nextPeriod = min(
                data.currentPeriod + 1,
                data.periodCount,
              );
              switch (data.status) {
                case TickerStatus.notStarted:
                  clockControlLabel = 'Spiel starten';
                  onClockControl = () => unawaited(
                        _startPeriod(currentTicker, 1),
                      );
                case TickerStatus.live:
                  clockControlLabel = 'Uhr pausieren';
                  clockControlIcon = Icons.pause_rounded;
                  onClockControl = () => unawaited(
                        _send(TickerEventType.interruption),
                      );
                case TickerStatus.paused || TickerStatus.interrupted:
                  clockControlLabel = 'Uhr fortsetzen';
                  clockControlIcon = Icons.play_arrow_rounded;
                  onClockControl = () => unawaited(_resumeClock());
                case TickerStatus.halfTime:
                  if (data.currentPeriod < data.periodCount) {
                    clockControlLabel = 'Abschnitt $nextPeriod starten';
                    onClockControl = () => unawaited(
                          _startPeriod(currentTicker, nextPeriod),
                        );
                  }
                case TickerStatus.finished:
                  break;
              }
              return _TickerFocusView(
                data: data,
                editable: widget.editable,
                onClockControl: onClockControl,
                clockControlLabel: clockControlLabel,
                clockControlIcon: clockControlIcon,
                onOurGoal: () => _goal(true),
                onTheirGoal: () => _goal(false),
                onEnd: data.status == TickerStatus.finished
                    ? null
                    : () => unawaited(_confirmEnd(dialogContext)),
                onClose: () => Navigator.pop(dialogContext),
              );
            },
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
          title: Text('Tor für ${widget.match.ownTeamName}'),
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
      if (mounted) {
        setState(() => _pending = pending);
        _focusData.value = _tickerFocusData(_ticker);
      }
    } catch (_) {
      // A browser storage problem is not a network outage.
    }
  }

  Future<void> _synchronizePending({bool showSuccess = true}) async {
    if (_syncing) {
      _syncRequested = true;
      return;
    }
    if (_pending.isEmpty) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final offlineQueue = ref.read(tickerOfflineQueueProvider);
    final repository = ref.read(repositoryProvider);
    setState(() => _syncing = true);
    var totalSent = 0;
    var totalRejected = 0;
    var online = true;
    try {
      do {
        _syncRequested = false;
        final result = await offlineQueue.synchronize(
          userId: userId,
          eventId: widget.match.id,
          send: (action) async {
            try {
              final acknowledgement = await repository.sendTickerEvent(
                eventId: action.eventId,
                clientEventId: action.clientEventId,
                type: action.type,
                scorerId: action.scorerId,
                assistId: action.assistId,
                comment: action.comment,
                period: action.period,
                elapsedSeconds: action.elapsedSeconds,
              );
              _applyServerAcknowledgement(acknowledgement);
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
        totalSent += result.sent;
        totalRejected += result.rejected;
        online = result.online;
        await _loadPending();
      } while (mounted && online && _pending.isNotEmpty && _syncRequested);
    } catch (_) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncRequested = false;
        });
        _message(
          'Die Ticker-Synchronisierung konnte nicht abgeschlossen werden.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncRequested = false;
      _queueOffline = !online;
    });
    if (totalRejected > 0 && mounted) {
      _message(
        '$totalRejected vorgemerkte Aktionen wurden vom Server abgelehnt '
        'und nicht übernommen.',
      );
    }
    if (totalSent > 0) {
      unawaited(widget.onChanged());
      if (showSuccess && mounted) {
        _message('$totalSent vorgemerkte Aktionen synchronisiert.');
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
      final resetTicker =
          await ref.read(repositoryProvider).resetTicker(widget.match.id);
      if (!mounted) return;
      _warnedPeriods.clear();
      setState(() => _optimisticTicker = resetTicker);
      _synchronizeClock(resetTicker);
      _lastRenderedElapsedSeconds = -1;
      _scheduleNextClockTick(immediate: true);
      _focusData.value = _tickerFocusData(resetTicker);
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
    required this.ownTeamName,
    required this.ownTeamLogoUrl,
    required this.ownTeamIsPlayingCommunity,
    required this.opponent,
    required this.opponentLogoUrl,
    required this.periodLabel,
    required this.status,
    required this.currentPeriod,
    required this.periodCount,
  });

  final MatchClockValue clock;
  final int ourGoals;
  final int theirGoals;
  final String ownTeamName;
  final String? ownTeamLogoUrl;
  final bool ownTeamIsPlayingCommunity;
  final String opponent;
  final String? opponentLogoUrl;
  final String periodLabel;
  final TickerStatus status;
  final int currentPeriod;
  final int periodCount;
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.clock,
    required this.ourGoals,
    required this.theirGoals,
    required this.ownTeamName,
    required this.ownTeamLogoUrl,
    required this.ownTeamIsPlayingCommunity,
    required this.opponent,
    required this.opponentLogoUrl,
    required this.periodLabel,
    required this.status,
    required this.onExpand,
  });

  final MatchClockValue clock;
  final int ourGoals;
  final int theirGoals;
  final String ownTeamName;
  final String? ownTeamLogoUrl;
  final bool ownTeamIsPlayingCommunity;
  final String opponent;
  final String? opponentLogoUrl;
  final String periodLabel;
  final TickerStatus status;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final expired = clock.expired && status == TickerStatus.live;
    final accent = expired ? const Color(0xFFC2410C) : AppColors.yellow;
    return Container(
      width: min(MediaQuery.sizeOf(context).width, 620.0),
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 8 : 14,
        compact ? 8 : 14,
        compact ? 9 : 14,
      ),
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
                visualDensity:
                    compact ? VisualDensity.compact : VisualDensity.standard,
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 1 : 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TeamCrest.ownTeam(
                size: compact ? 30 : 42,
                logoUrl: ownTeamLogoUrl,
                isPlayingCommunity: ownTeamIsPlayingCommunity,
                darkSurface: true,
              ),
              SizedBox(width: compact ? 6 : 9),
              Flexible(
                child: Text(
                  ownTeamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14),
                child: Text(
                  '$ourGoals : $theirGoals',
                  style: TextStyle(
                    color: AppColors.yellow,
                    fontSize: compact ? 20 : 24,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  opponent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: compact ? 6 : 9),
              TeamCrest.opponent(
                size: compact ? 30 : 42,
                logoUrl: opponentLogoUrl,
                darkSurface: true,
              ),
            ],
          ),
          SizedBox(height: compact ? 5 : 10),
          Text(
            clock.countdown,
            style: TextStyle(
              color: accent,
              fontSize: compact ? 38 : 52,
              height: 1,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: compact ? 7 : 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: _SmoothClockProgress(
              value: clock.progress,
              minHeight: compact ? 5 : 7,
              color: accent,
            ),
          ),
          SizedBox(height: compact ? 4 : 7),
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
    required this.onClockControl,
    required this.clockControlLabel,
    required this.clockControlIcon,
    required this.onOurGoal,
    required this.onTheirGoal,
    required this.onEnd,
    required this.onClose,
  });

  final _TickerFocusData data;
  final bool editable;
  final VoidCallback? onClockControl;
  final String clockControlLabel;
  final IconData clockControlIcon;
  final VoidCallback onOurGoal;
  final VoidCallback onTheirGoal;
  final VoidCallback? onEnd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final expired = data.clock.expired && data.status == TickerStatus.live;
    final clockColor = expired ? const Color(0xFFFFA56B) : AppColors.yellow;
    final canRecordGoal = data.status != TickerStatus.notStarted &&
        data.status != TickerStatus.finished;
    return Material(
      color: AppColors.black,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.45),
            radius: 1.05,
            colors: [Color(0xFF24230C), AppColors.black],
            stops: [0, .72],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, pageConstraints) {
              final compactHeight = pageConstraints.maxHeight < 700;
              final compactWidth = pageConstraints.maxWidth < 430;
              final pagePadding = compactWidth ? 12.0 : 20.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  compactHeight ? 8 : 14,
                  pagePadding,
                  compactHeight ? 10 : 16,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClubLogo(size: compactHeight ? 38 : 46),
                        SizedBox(width: compactWidth ? 9 : 12),
                        Expanded(
                          child: Text(
                            'FC TEUGN · LIVE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compactWidth ? 16 : 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .8,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: onClose,
                          tooltip: 'Großansicht schließen',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_fullscreen_rounded),
                        ),
                      ],
                    ),
                    SizedBox(height: compactHeight ? 4 : 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final contentCompact =
                              compactHeight || constraints.maxHeight < 520;
                          final clockSize = min(
                            constraints.maxWidth * (compactWidth ? .22 : .19),
                            constraints.maxHeight *
                                (contentCompact ? .20 : .24),
                          ).clamp(54, 118);
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compactWidth ? 11 : 15,
                                      vertical: compactHeight ? 5 : 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: .07),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: .10),
                                      ),
                                    ),
                                    child: Text(
                                      '${data.periodLabel} · ${_tickerStatus(data.status)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: compactWidth ? 14 : 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: contentCompact ? 7 : 11),
                                  RepaintBoundary(
                                    child: Semantics(
                                      label:
                                          'Verbleibende Spielzeit ${data.clock.countdown}',
                                      child: ExcludeSemantics(
                                        child: Text(
                                          data.clock.countdown,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: clockColor,
                                            fontSize: clockSize.toDouble(),
                                            height: .96,
                                            letterSpacing: compactWidth ? 2 : 4,
                                            fontWeight: FontWeight.w900,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                            shadows: [
                                              Shadow(
                                                color: clockColor.withValues(
                                                  alpha: .22,
                                                ),
                                                blurRadius: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: contentCompact ? 9 : 14),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 720),
                                    child: RepaintBoundary(
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: _SmoothClockProgress(
                                          value: data.clock.progress,
                                          minHeight: contentCompact ? 6 : 8,
                                          color: clockColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: contentCompact ? 14 : 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _FocusTeamScore(
                                        team: data.ownTeamName,
                                        goals: data.ourGoals,
                                        isOwnTeam: true,
                                        logoUrl: data.ownTeamLogoUrl,
                                        ownTeamIsPlayingCommunity:
                                            data.ownTeamIsPlayingCommunity,
                                        highlighted: true,
                                        compact: contentCompact || compactWidth,
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: compactWidth ? 12 : 26,
                                        ),
                                        child: Text(
                                          ':',
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: compactWidth ? 42 : 54,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      ),
                                      _FocusTeamScore(
                                        team: data.opponent,
                                        goals: data.theirGoals,
                                        logoUrl: data.opponentLogoUrl,
                                        compact: contentCompact || compactWidth,
                                      ),
                                    ],
                                  ),
                                  if (expired) ...[
                                    SizedBox(height: contentCompact ? 8 : 14),
                                    const Text(
                                      'Abschnittszeit abgelaufen',
                                      style: TextStyle(
                                        color: Color(0xFFFFA56B),
                                        fontSize: 14,
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
                    if (editable) ...[
                      SizedBox(height: compactHeight ? 6 : 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    label:
                                        'Tor für ${data.ownTeamName} erfassen',
                                    child: SizedBox(
                                      height: compactHeight ? 48 : 54,
                                      child: FilledButton.icon(
                                        onPressed:
                                            canRecordGoal ? onOurGoal : null,
                                        style: FilledButton.styleFrom(
                                          foregroundColor: AppColors.black,
                                          backgroundColor: AppColors.yellow,
                                          disabledForegroundColor:
                                              Colors.white38,
                                          disabledBackgroundColor:
                                              Colors.white12,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: compactWidth ? 8 : 14,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add_circle_rounded,
                                        ),
                                        label: Text(
                                          compactWidth
                                              ? 'Tor ${data.ownTeamName}'
                                              : 'Tor für ${data.ownTeamName}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    label: 'Gegentor erfassen',
                                    child: SizedBox(
                                      height: compactHeight ? 48 : 54,
                                      child: FilledButton.icon(
                                        onPressed:
                                            canRecordGoal ? onTheirGoal : null,
                                        style: FilledButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor:
                                              const Color(0xFF7F1D1D),
                                          disabledForegroundColor:
                                              Colors.white38,
                                          disabledBackgroundColor:
                                              Colors.white12,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: compactWidth ? 8 : 14,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.sports_soccer_rounded,
                                        ),
                                        label: const Text(
                                          'Gegentor',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!canRecordGoal &&
                                data.status == TickerStatus.notStarted) ...[
                              const SizedBox(height: 5),
                              const Text(
                                'Toraktionen sind nach dem Spielstart verfügbar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            SizedBox(height: compactHeight ? 6 : 9),
                            LayoutBuilder(
                              builder: (context, controlConstraints) {
                                final controlWidth = min(
                                  (controlConstraints.maxWidth - 10) / 2,
                                  230.0,
                                );
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 7,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    if (onClockControl != null)
                                      SizedBox(
                                        width: controlWidth,
                                        height: compactHeight ? 42 : 46,
                                        child: FilledButton.tonalIcon(
                                          onPressed: onClockControl,
                                          style: FilledButton.styleFrom(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: compactWidth ? 8 : 12,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          icon: Icon(
                                            clockControlIcon,
                                            size: 20,
                                          ),
                                          label: Text(
                                            clockControlLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    if (onEnd != null)
                                      SizedBox(
                                        width: controlWidth,
                                        height: compactHeight ? 42 : 46,
                                        child: FilledButton.icon(
                                          onPressed: onEnd,
                                          style: FilledButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            backgroundColor:
                                                const Color(0xFFC2410C),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: compactWidth ? 8 : 12,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          icon: const Icon(
                                            Icons.stop_circle_outlined,
                                            size: 20,
                                          ),
                                          label: const Text(
                                            'Spiel beenden',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SmoothClockProgress extends StatefulWidget {
  const _SmoothClockProgress({
    required this.value,
    required this.minHeight,
    required this.color,
  });

  final double value;
  final double minHeight;
  final Color color;

  @override
  State<_SmoothClockProgress> createState() => _SmoothClockProgressState();
}

class _SmoothClockProgressState extends State<_SmoothClockProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _animation = AlwaysStoppedAnimation(widget.value);
  }

  @override
  void didUpdateWidget(covariant _SmoothClockProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final begin = _animation.value;
    _animation = Tween<double>(begin: begin, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _animation,
        builder: (context, _) => LinearProgressIndicator(
          value: _animation.value,
          minHeight: widget.minHeight,
          backgroundColor: Colors.white12,
          color: widget.color,
        ),
      );
}

class _FocusTeamScore extends StatelessWidget {
  const _FocusTeamScore({
    required this.team,
    required this.goals,
    this.isOwnTeam = false,
    this.logoUrl,
    this.ownTeamIsPlayingCommunity = false,
    this.highlighted = false,
    this.compact = false,
  });

  final String team;
  final int goals;
  final bool isOwnTeam;
  final String? logoUrl;
  final bool ownTeamIsPlayingCommunity;
  final bool highlighted;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: min(MediaQuery.sizeOf(context).width * .28, 240.0),
        child: Column(
          children: [
            isOwnTeam
                ? TeamCrest.ownTeam(
                    size: compact ? 50 : 64,
                    logoUrl: logoUrl,
                    isPlayingCommunity: ownTeamIsPlayingCommunity,
                    darkSurface: true,
                  )
                : TeamCrest.opponent(
                    size: compact ? 50 : 64,
                    logoUrl: logoUrl,
                    darkSurface: true,
                  ),
            SizedBox(height: compact ? 6 : 10),
            Text(
              '$goals',
              style: TextStyle(
                color: highlighted ? AppColors.yellow : Colors.white,
                fontSize: compact ? 50 : 64,
                height: 1,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: compact ? 5 : 8),
            Text(
              team,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
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
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
                semanticsLabel: 'Spielstand wird synchronisiert',
              ),
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
      TickerEventType.interruption => 'Pause',
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 18,
        vertical: compact ? 7 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          Text(value,
              style: TextStyle(
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.w900,
              )),
        ],
      ),
    );
  }
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
  required String ownTeamName,
}) =>
    switch (event.type) {
      TickerEventType.homeGoal ||
      TickerEventType.awayGoal =>
        _isOurGoal(event.type, fcIsHome: fcIsHome)
            ? 'Tor durch ${event.scorer?.name ?? ownTeamName}!'
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
