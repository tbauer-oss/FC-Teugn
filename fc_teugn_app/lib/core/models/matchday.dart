import 'player.dart';
import 'event.dart';
import '../team_game_format.dart';

enum MatchStatus {
  planned,
  confirmed,
  postponed,
  cancelled,
  live,
  halfTime,
  interrupted,
  finished,
  recorded,
}

enum NominationStatus { nominated, onCall, declined }

enum LineupStatus { draft, internallyApproved, published, archived }

enum TickerStatus { notStarted, live, paused, halfTime, interrupted, finished }

enum KitLaundryDutyStatus { open, proposed, confirmed, completed }

enum TickerEventType {
  matchStart,
  homeGoal,
  awayGoal,
  periodEnd,
  periodStart,
  interruption,
  resume,
  substitution,
  card,
  injury,
  penalty,
  ownGoal,
  comment,
  correction,
  eventRevoked,
  matchEnd,
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final normalized = raw?.toString().toLowerCase().replaceAll('_', '');
  return values
          .where((item) => item.name.toLowerCase() == normalized)
          .firstOrNull ??
      fallback;
}

class MatchdayModel {
  const MatchdayModel({
    required this.id,
    required this.title,
    required this.startAt,
    required this.location,
    required this.teamId,
    this.address,
    this.meetingAt,
    this.meetingLocation,
    this.details,
    this.squad,
    this.squadSummary,
    this.ticker,
    this.eligiblePlayers = const [],
    this.attendance = const [],
    this.playerPoolAgeGroupCode,
    this.gameFormat = TeamGameFormat.football7,
    this.teamDefaultFormation,
    this.teamFormationOptions = const [],
    this.canManageTicker = false,
    this.canDelegateTicker = false,
    this.communicationStatus = EventCommunicationStatus.draft,
    this.internalPublishedAt,
    this.familyReleasedAt,
    this.familyReleaseAudience,
    this.canPublishInternal = false,
    this.canNominateSquad = false,
    this.canReleaseFamily = false,
    this.canRatePlayers = false,
    this.playerRatings = const [],
    this.ownTeamName = 'FC Teugn',
    this.ownTeamShortName = 'FC Teugn',
    this.ownTeamLogoUrl,
    this.ownTeamIsPlayingCommunity = false,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime? meetingAt;
  final String? meetingLocation;
  final String location;
  final String? address;
  final String teamId;
  final MatchDetailsModel? details;
  final MatchSquadModel? squad;
  final MatchSquadSummaryModel? squadSummary;
  final LiveTickerModel? ticker;
  final List<PlayerModel> eligiblePlayers;
  final List<EventAttendance> attendance;
  final String? playerPoolAgeGroupCode;
  final TeamGameFormat gameFormat;
  final String? teamDefaultFormation;
  final List<String> teamFormationOptions;
  final bool canManageTicker;
  final bool canDelegateTicker;
  final EventCommunicationStatus communicationStatus;
  final DateTime? internalPublishedAt;
  final DateTime? familyReleasedAt;
  final String? familyReleaseAudience;
  final bool canPublishInternal;
  final bool canNominateSquad;
  final bool canReleaseFamily;
  final bool canRatePlayers;
  final List<PlayerMatchRatingModel> playerRatings;
  final String ownTeamName;
  final String ownTeamShortName;
  final String? ownTeamLogoUrl;
  final bool ownTeamIsPlayingCommunity;

  factory MatchdayModel.fromJson(Map<String, dynamic> json) {
    final squads = json['squads'] as List<dynamic>? ?? const [];
    final capabilities = json['capabilities'] as Map<String, dynamic>?;
    final ownTeam =
        json['ownTeam'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return MatchdayModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Spiel',
      startAt: DateTime.parse(json['startAt'] as String),
      meetingAt: json['meetingAt'] == null
          ? null
          : DateTime.parse(json['meetingAt'] as String),
      meetingLocation: json['meetingLocation'] as String?,
      location: json['location'] as String? ?? '',
      address: json['address'] as String?,
      teamId: json['teamId'] as String? ?? '',
      details: json['matchDetails'] == null
          ? null
          : MatchDetailsModel.fromJson(
              json['matchDetails'] as Map<String, dynamic>,
            ),
      squad: squads.isEmpty
          ? null
          : MatchSquadModel.fromJson(squads.first as Map<String, dynamic>),
      squadSummary: json['squadSummary'] == null
          ? null
          : MatchSquadSummaryModel.fromJson(
              json['squadSummary'] as Map<String, dynamic>,
            ),
      ticker: json['liveTicker'] == null
          ? null
          : LiveTickerModel.fromJson(
              json['liveTicker'] as Map<String, dynamic>,
            ),
      eligiblePlayers: (json['eligiblePlayers'] as List<dynamic>? ?? const [])
          .map(
            (item) => PlayerModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      attendance: (json['attendance'] as List<dynamic>? ?? const [])
          .map(
            (item) => EventAttendance.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      playerPoolAgeGroupCode: json['playerPoolAgeGroupCode'] as String?,
      gameFormat: TeamGameFormat.fromApi(json['teamGameFormat']),
      teamDefaultFormation: json['teamDefaultFormation'] as String?,
      teamFormationOptions:
          (json['teamFormationOptions'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      canManageTicker: capabilities?['canManageTicker'] as bool? ?? false,
      canDelegateTicker: capabilities?['canDelegateTicker'] as bool? ?? false,
      communicationStatus: _enum(
        EventCommunicationStatus.values,
        json['communicationStatus'],
        EventCommunicationStatus.draft,
      ),
      internalPublishedAt: json['internalPublishedAt'] == null
          ? null
          : DateTime.parse(json['internalPublishedAt'] as String).toLocal(),
      familyReleasedAt: json['familyReleasedAt'] == null
          ? null
          : DateTime.parse(json['familyReleasedAt'] as String).toLocal(),
      familyReleaseAudience: json['familyReleaseAudience'] as String?,
      canPublishInternal: capabilities?['canPublishInternal'] as bool? ?? false,
      canNominateSquad: capabilities?['canNominateSquad'] as bool? ?? false,
      canReleaseFamily: capabilities?['canReleaseFamily'] as bool? ?? false,
      canRatePlayers: capabilities?['canRatePlayers'] as bool? ?? false,
      playerRatings: (json['playerRatings'] as List<dynamic>? ?? const [])
          .map(
            (item) => PlayerMatchRatingModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      ownTeamName: ownTeam['name'] as String? ?? 'FC Teugn',
      ownTeamShortName: ownTeam['shortName'] as String? ??
          ownTeam['name'] as String? ??
          'FC Teugn',
      ownTeamLogoUrl: ownTeam['logoUrl'] as String?,
      ownTeamIsPlayingCommunity:
          ownTeam['isPlayingCommunity'] as bool? ?? false,
    );
  }

  DateTime? get squadPublishedAt =>
      squad?.publishedAt ?? squadSummary?.publishedAt;

  bool get hasSquad => squad != null || squadSummary != null;

  NominationStatus? nominationForPlayer(String playerId) {
    final fullMember = squad?.members
        .where((member) => member.player.id == playerId)
        .firstOrNull;
    return fullMember?.status ?? squadSummary?.memberStatus[playerId];
  }

  AttendanceStatus attendanceStatusForPlayer(String playerId) =>
      attendance
          .where((reply) => reply.playerId == playerId)
          .map((reply) => reply.status)
          .firstOrNull ??
      AttendanceStatus.unknown;

  bool hasConfirmedAttendance(String playerId) =>
      attendanceStatusForPlayer(playerId) == AttendanceStatus.yes;
}

class MatchSquadSummaryModel {
  const MatchSquadSummaryModel({
    required this.id,
    required this.memberStatus,
    this.publishedAt,
  });

  final String id;
  final DateTime? publishedAt;
  final Map<String, NominationStatus> memberStatus;

  factory MatchSquadSummaryModel.fromJson(Map<String, dynamic> json) =>
      MatchSquadSummaryModel(
        id: json['id'] as String,
        publishedAt: json['publishedAt'] == null
            ? null
            : DateTime.parse(json['publishedAt'] as String),
        memberStatus: {
          for (final item in (json['members'] as List<dynamic>? ?? const []))
            if ((item as Map<String, dynamic>)['playerId'] is String)
              item['playerId'] as String: _enum(
                NominationStatus.values,
                item['status'],
                NominationStatus.nominated,
              ),
        },
      );
}

class PlayerMatchRatingModel {
  const PlayerMatchRatingModel({
    required this.player,
    required this.score,
    this.ratedByName,
    this.updatedAt,
  });

  final MatchPlayer player;
  final int score;
  final String? ratedByName;
  final DateTime? updatedAt;

  factory PlayerMatchRatingModel.fromJson(Map<String, dynamic> json) =>
      PlayerMatchRatingModel(
        player: MatchPlayer.fromJson(json['player'] as Map<String, dynamic>),
        score: (json['score'] as num).toInt(),
        ratedByName:
            (json['ratedBy'] as Map<String, dynamic>?)?['name'] as String?,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String).toLocal(),
      );
}

class ParentMatchRatingsModel {
  const ParentMatchRatingsModel({
    required this.available,
    required this.players,
    required this.ratings,
  });

  final bool available;
  final List<MatchPlayer> players;
  final Map<String, int> ratings;

  factory ParentMatchRatingsModel.fromJson(Map<String, dynamic> json) =>
      ParentMatchRatingsModel(
        available: json['available'] as bool? ?? false,
        players: (json['players'] as List<dynamic>? ?? const [])
            .map(
              (item) => MatchPlayer.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        ratings: {
          for (final item in (json['ratings'] as List<dynamic>? ?? const []))
            if ((item as Map<String, dynamic>)['playerId'] is String &&
                item['score'] is num)
              item['playerId'] as String: (item['score'] as num).toInt(),
        },
      );
}

class TickerDelegateUser {
  const TickerDelegateUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory TickerDelegateUser.fromJson(Map<String, dynamic> json) =>
      TickerDelegateUser(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

class TickerDelegation {
  const TickerDelegation({this.delegate, this.candidates = const []});

  final TickerDelegateUser? delegate;
  final List<TickerDelegateUser> candidates;

  factory TickerDelegation.fromJson(Map<String, dynamic> json) =>
      TickerDelegation(
        delegate: json['delegate'] == null
            ? null
            : TickerDelegateUser.fromJson(
                json['delegate'] as Map<String, dynamic>,
              ),
        candidates: (json['candidates'] as List<dynamic>? ?? const [])
            .map(
              (item) => TickerDelegateUser.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class MatchDetailsModel {
  const MatchDetailsModel({
    required this.opponent,
    required this.isHome,
    required this.status,
    required this.durationMinutes,
    required this.periodMinutes,
    required this.periodCount,
    this.competition,
    this.opponentLogoUrl,
    this.division,
    this.matchDay,
    this.pitch,
    this.referee,
    this.ourGoals,
    this.theirGoals,
    this.notes,
  });

  final String opponent;
  final bool isHome;
  final MatchStatus status;
  final String? competition;
  final String? opponentLogoUrl;
  final String? division;
  final String? matchDay;
  final String? pitch;
  final String? referee;
  final int durationMinutes;
  final int periodMinutes;
  final int periodCount;
  final int? ourGoals;
  final int? theirGoals;
  final String? notes;

  factory MatchDetailsModel.fromJson(Map<String, dynamic> json) =>
      MatchDetailsModel(
        opponent: json['opponent'] as String? ?? 'Gegner',
        isHome: json['isHome'] as bool? ?? true,
        status: _enum(
          MatchStatus.values,
          json['status'],
          MatchStatus.planned,
        ),
        competition: json['competition'] as String?,
        opponentLogoUrl: json['opponentLogoUrl'] as String?,
        division: json['division'] as String?,
        matchDay: json['matchDay'] as String?,
        pitch: json['pitch'] as String?,
        referee: json['referee'] as String?,
        durationMinutes: json['durationMinutes'] as int? ?? 60,
        periodMinutes: json['periodMinutes'] as int? ?? 30,
        periodCount: json['periodCount'] as int? ?? 2,
        ourGoals: json['ourGoals'] as int?,
        theirGoals: json['theirGoals'] as int?,
        notes: json['notes'] as String?,
      );
}

class MatchPlayer {
  const MatchPlayer({
    required this.id,
    required this.name,
    this.shirtNumber,
    this.position,
    this.secondaryPosition,
    this.status,
  });

  final String id;
  final String name;
  final int? shirtNumber;
  final String? position;
  final String? secondaryPosition;
  final PlayerStatus? status;

  factory MatchPlayer.fromJson(Map<String, dynamic> json) => MatchPlayer(
        id: json['id'] as String,
        name: (json['preferredName'] as String?)?.trim().isNotEmpty == true
            ? json['preferredName'] as String
            : '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'.trim(),
        shirtNumber: json['shirtNumber'] as int?,
        position: json['position'] as String?,
        secondaryPosition: json['secondaryPosition'] as String?,
        status: json['status'] == null
            ? null
            : _enum(PlayerStatus.values, json['status'], PlayerStatus.active),
      );
}

class MatchSquadModel {
  const MatchSquadModel({
    required this.id,
    required this.members,
    this.name,
    this.formation,
    this.publishedAt,
    this.lineup,
  });

  final String id;
  final String? name;
  final String? formation;
  final DateTime? publishedAt;
  final List<SquadMemberModel> members;
  final LineupModel? lineup;

  factory MatchSquadModel.fromJson(Map<String, dynamic> json) =>
      MatchSquadModel(
        id: json['id'] as String,
        name: json['name'] as String?,
        formation: json['formation'] as String?,
        publishedAt: json['publishedAt'] == null
            ? null
            : DateTime.parse(json['publishedAt'] as String),
        members: (json['members'] as List<dynamic>? ?? const [])
            .map(
              (item) => SquadMemberModel.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        lineup: json['lineup'] == null
            ? null
            : LineupModel.fromJson(json['lineup'] as Map<String, dynamic>),
      );
}

class SquadMemberModel {
  const SquadMemberModel({
    required this.player,
    required this.status,
    this.note,
    this.plannedMinutes,
  });

  final MatchPlayer player;
  final NominationStatus status;
  final String? note;
  final int? plannedMinutes;

  factory SquadMemberModel.fromJson(Map<String, dynamic> json) =>
      SquadMemberModel(
        player: MatchPlayer.fromJson(json['player'] as Map<String, dynamic>),
        status: _enum(
          NominationStatus.values,
          json['status'],
          NominationStatus.nominated,
        ),
        note: json['note'] as String?,
        plannedMinutes: json['plannedMinutes'] as int?,
      );
}

class LineupModel {
  const LineupModel({
    required this.id,
    required this.formation,
    required this.fieldSize,
    required this.status,
    required this.positions,
    this.substitutions = const [],
    this.usesTeamDefault = false,
    this.automaticReplacements = 0,
    this.publicNote,
    this.tacticalNote,
  });

  final String id;
  final String formation;
  final int fieldSize;
  final LineupStatus status;
  final bool usesTeamDefault;
  final int automaticReplacements;
  final String? publicNote;
  final String? tacticalNote;
  final List<LineupPositionModel> positions;
  final List<PlannedSubstitutionModel> substitutions;

  factory LineupModel.fromJson(Map<String, dynamic> json) => LineupModel(
        id: json['id'] as String,
        formation: json['formation'] as String? ?? 'Individuell',
        fieldSize: json['fieldSize'] as int? ?? 7,
        status: _enum(
          LineupStatus.values,
          json['status'],
          LineupStatus.draft,
        ),
        usesTeamDefault: json['usesTeamDefault'] as bool? ?? false,
        automaticReplacements:
            (json['automaticReplacements'] as num?)?.toInt() ?? 0,
        publicNote: json['publicNote'] as String?,
        tacticalNote: json['tacticalNote'] as String?,
        positions: (json['positions'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  LineupPositionModel.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        substitutions: (json['substitutions'] as List<dynamic>? ?? const [])
            .map(
              (item) => PlannedSubstitutionModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class PlannedSubstitutionModel {
  const PlannedSubstitutionModel({
    required this.period,
    required this.playerInId,
    required this.playerOutId,
    this.id,
    this.minute,
    this.positionCode,
    this.note,
  });

  final String? id;
  final int period;
  final int? minute;
  final String playerInId;
  final String playerOutId;
  final String? positionCode;
  final String? note;

  String? get targetPositionCode {
    final explicit = positionCode?.trim().toUpperCase();
    if (explicit?.isNotEmpty == true) return explicit;
    final legacy = note?.split('·').first.trim().toUpperCase();
    if (legacy == null ||
        legacy.isEmpty ||
        !RegExp(r'^[A-ZÄÖÜ0-9]{1,8}$').hasMatch(legacy)) {
      return null;
    }
    return legacy;
  }

  factory PlannedSubstitutionModel.fromJson(Map<String, dynamic> json) =>
      PlannedSubstitutionModel(
        id: json['id'] as String?,
        period: (json['period'] as num?)?.toInt() ?? 1,
        minute: (json['minute'] as num?)?.toInt(),
        playerInId: json['playerInId'] as String? ?? '',
        playerOutId: json['playerOutId'] as String? ?? '',
        positionCode: json['positionCode'] as String?,
        note: json['note'] as String?,
      );
}

class LineupPositionModel {
  const LineupPositionModel({
    required this.player,
    required this.positionCode,
    required this.x,
    required this.y,
    required this.period,
    required this.isStarter,
    required this.isGoalkeeper,
    required this.isCaptain,
  });

  final MatchPlayer player;
  final String positionCode;
  final double x;
  final double y;
  final int period;
  final bool isStarter;
  final bool isGoalkeeper;
  final bool isCaptain;

  factory LineupPositionModel.fromJson(Map<String, dynamic> json) =>
      LineupPositionModel(
        player: MatchPlayer.fromJson(json['player'] as Map<String, dynamic>),
        positionCode: json['positionCode'] as String? ?? 'FELD',
        x: (json['x'] as num?)?.toDouble() ?? .5,
        y: (json['y'] as num?)?.toDouble() ?? .5,
        period: json['period'] as int? ?? 1,
        isStarter: json['isStarter'] as bool? ?? true,
        isGoalkeeper: json['isGoalkeeper'] as bool? ?? false,
        isCaptain: json['isCaptain'] as bool? ?? false,
      );
}

class LiveTickerModel {
  const LiveTickerModel({
    required this.status,
    required this.currentPeriod,
    required this.elapsedSeconds,
    required this.ourGoals,
    required this.theirGoals,
    required this.lastSequence,
    required this.events,
  });

  final TickerStatus status;
  final int currentPeriod;
  final int elapsedSeconds;
  final int ourGoals;
  final int theirGoals;
  final int lastSequence;
  final List<TickerEventModel> events;

  factory LiveTickerModel.fromJson(Map<String, dynamic> json) =>
      LiveTickerModel(
        status: _enum(
          TickerStatus.values,
          json['status'],
          TickerStatus.notStarted,
        ),
        currentPeriod: json['currentPeriod'] as int? ?? 1,
        elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
        ourGoals: json['ourGoals'] as int? ?? 0,
        theirGoals: json['theirGoals'] as int? ?? 0,
        lastSequence: json['lastSequence'] as int? ?? 0,
        events: (json['events'] as List<dynamic>? ?? const [])
            .map(
              (item) => TickerEventModel.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

class TickerEventModel {
  const TickerEventModel({
    required this.id,
    required this.sequence,
    required this.type,
    required this.elapsedSeconds,
    required this.ourGoals,
    required this.theirGoals,
    this.period = 1,
    this.comment,
    this.scorer,
    this.assist,
    this.clientEventId,
    this.correctsId,
  });

  final String id;
  final int sequence;
  final TickerEventType type;
  final int elapsedSeconds;
  final int ourGoals;
  final int theirGoals;
  final int period;
  final String? comment;
  final MatchPlayer? scorer;
  final MatchPlayer? assist;
  final String? clientEventId;
  final String? correctsId;

  factory TickerEventModel.fromJson(Map<String, dynamic> json) =>
      TickerEventModel(
        id: json['id'] as String,
        sequence: json['sequence'] as int? ?? 0,
        type: _enum(
          TickerEventType.values,
          json['type'],
          TickerEventType.comment,
        ),
        elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
        ourGoals: json['ourGoals'] as int? ?? 0,
        theirGoals: json['theirGoals'] as int? ?? 0,
        period: json['period'] as int? ?? 1,
        comment: json['comment'] as String?,
        clientEventId: json['clientEventId'] as String?,
        correctsId: json['correctsId'] as String?,
        scorer: json['scorer'] == null
            ? null
            : MatchPlayer.fromJson(json['scorer'] as Map<String, dynamic>),
        assist: json['assist'] == null
            ? null
            : MatchPlayer.fromJson(json['assist'] as Map<String, dynamic>),
      );
}

String apiEnum(Enum value) {
  return value.name
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toUpperCase();
}

class KitLaundryCandidateModel {
  const KitLaundryCandidateModel({
    required this.familyKey,
    required this.playerId,
    required this.playerNames,
    required this.guardianNames,
    required this.selected,
  });

  final String familyKey;
  final String playerId;
  final List<String> playerNames;
  final List<String> guardianNames;
  final bool selected;

  String get familyLabel => 'Familie ${playerNames.join(' & ')}';

  factory KitLaundryCandidateModel.fromJson(Map<String, dynamic> json) =>
      KitLaundryCandidateModel(
        familyKey: json['familyKey'] as String? ?? '',
        playerId: json['playerId'] as String? ?? '',
        playerNames: (json['playerNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        guardianNames: (json['guardianNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        selected: json['selected'] as bool? ?? false,
      );
}

class KitLaundryDutyModel {
  const KitLaundryDutyModel({
    required this.eventId,
    required this.title,
    required this.startAt,
    required this.status,
    required this.eligibleFamilyCount,
    required this.nominationPublished,
    required this.viewerEligible,
    required this.viewerAssigned,
    required this.canRespond,
    required this.canComplete,
    required this.canManage,
    this.assignedPlayerId,
    this.assignedPlayerName,
    this.assignedFamilyLabel,
    this.confirmedByName,
    this.assignmentSource = 'AUTOMATIC',
    this.candidates = const [],
  });

  final String eventId;
  final String title;
  final DateTime startAt;
  final KitLaundryDutyStatus status;
  final String assignmentSource;
  final String? assignedPlayerId;
  final String? assignedPlayerName;
  final String? assignedFamilyLabel;
  final String? confirmedByName;
  final int eligibleFamilyCount;
  final bool nominationPublished;
  final bool viewerEligible;
  final bool viewerAssigned;
  final bool canRespond;
  final bool canComplete;
  final bool canManage;
  final List<KitLaundryCandidateModel> candidates;

  factory KitLaundryDutyModel.fromJson(Map<String, dynamic> json) =>
      KitLaundryDutyModel(
        eventId: json['eventId'] as String? ?? '',
        title: json['title'] as String? ?? 'Spiel',
        startAt: DateTime.parse(json['startAt'] as String).toLocal(),
        status: _enum(
          KitLaundryDutyStatus.values,
          json['status'],
          KitLaundryDutyStatus.open,
        ),
        assignmentSource: json['assignmentSource'] as String? ?? 'AUTOMATIC',
        assignedPlayerId: json['assignedPlayerId'] as String?,
        assignedPlayerName: json['assignedPlayerName'] as String?,
        assignedFamilyLabel: json['assignedFamilyLabel'] as String?,
        confirmedByName: json['confirmedByName'] as String?,
        eligibleFamilyCount: json['eligibleFamilyCount'] as int? ?? 0,
        nominationPublished: json['nominationPublished'] as bool? ?? false,
        viewerEligible: json['viewerEligible'] as bool? ?? false,
        viewerAssigned: json['viewerAssigned'] as bool? ?? false,
        canRespond: json['canRespond'] as bool? ?? false,
        canComplete: json['canComplete'] as bool? ?? false,
        canManage: json['canManage'] as bool? ?? false,
        candidates: (json['candidates'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(KitLaundryCandidateModel.fromJson)
            .toList(),
      );
}
