class OpponentModel {
  const OpponentModel({
    required this.id,
    required this.ageGroupId,
    required this.clubName,
    required this.teamDesignation,
    required this.displayName,
    this.teamId,
    this.shortName,
    this.venue,
    this.address,
    this.logoUrl,
  });

  final String id;
  final String ageGroupId;
  final String? teamId;
  final String clubName;
  final String teamDesignation;
  final String displayName;
  final String? shortName;
  final String? venue;
  final String? address;
  final String? logoUrl;

  factory OpponentModel.fromJson(Map<String, dynamic> json) => OpponentModel(
        id: json['id'] as String,
        ageGroupId: json['ageGroupId'] as String,
        teamId: json['teamId'] as String?,
        clubName: json['clubName'] as String? ?? '',
        teamDesignation: json['teamDesignation'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        shortName: json['shortName'] as String?,
        venue: json['venue'] as String?,
        address: json['address'] as String?,
        logoUrl: json['logoUrl'] as String?,
      );
}

class LeagueModel {
  const LeagueModel({
    required this.id,
    required this.name,
    required this.ageGroupId,
    required this.entries,
    required this.matches,
    required this.standings,
  });
  final String id;
  final String name;
  final String ageGroupId;
  final List<LeagueEntryModel> entries;
  final List<LeagueMatchModel> matches;
  final List<LeagueStandingModel> standings;

  factory LeagueModel.fromJson(Map<String, dynamic> json) => LeagueModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Liga',
        ageGroupId: json['ageGroupId'] as String,
        entries: (json['entries'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LeagueEntryModel.fromJson)
            .toList(),
        matches: (json['matches'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LeagueMatchModel.fromJson)
            .toList(),
        standings: (json['standings'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LeagueStandingModel.fromJson)
            .toList(),
      );
}

class LeagueEntryModel {
  const LeagueEntryModel({
    required this.id,
    required this.displayName,
    required this.isOwnTeam,
    this.ownTeamId,
    this.opponentId,
    this.logoUrl,
  });
  final String id;
  final String displayName;
  final bool isOwnTeam;
  final String? ownTeamId;
  final String? opponentId;
  final String? logoUrl;

  factory LeagueEntryModel.fromJson(Map<String, dynamic> json) =>
      LeagueEntryModel(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        isOwnTeam: json['isOwnTeam'] as bool? ?? false,
        ownTeamId: json['ownTeamId'] as String?,
        opponentId: json['opponentId'] as String?,
        logoUrl: json['logoUrl'] as String?,
      );
}

class LeagueMatchModel {
  const LeagueMatchModel({
    required this.id,
    required this.homeEntryId,
    required this.awayEntryId,
    required this.homeName,
    required this.awayName,
    required this.status,
    this.startsAt,
    this.homeGoals,
    this.awayGoals,
    this.eventId,
    this.externalUid,
  });
  final String id;
  final String homeEntryId;
  final String awayEntryId;
  final String homeName;
  final String awayName;
  final String status;
  final DateTime? startsAt;
  final int? homeGoals;
  final int? awayGoals;
  final String? eventId;
  final String? externalUid;

  factory LeagueMatchModel.fromJson(Map<String, dynamic> json) =>
      LeagueMatchModel(
        id: json['id'] as String,
        homeEntryId: json['homeEntryId'] as String,
        awayEntryId: json['awayEntryId'] as String,
        homeName: (json['homeEntry'] as Map<String, dynamic>?)?['displayName']
                as String? ??
            '',
        awayName: (json['awayEntry'] as Map<String, dynamic>?)?['displayName']
                as String? ??
            '',
        status: json['status'] as String? ?? 'SCHEDULED',
        startsAt: json['startsAt'] == null
            ? null
            : DateTime.parse(json['startsAt'] as String).toLocal(),
        homeGoals: json['homeGoals'] as int?,
        awayGoals: json['awayGoals'] as int?,
        eventId: json['eventId'] as String?,
        externalUid: json['externalUid'] as String?,
      );
}

class LeagueStandingModel {
  const LeagueStandingModel({
    required this.rank,
    required this.name,
    required this.isOwnTeam,
    required this.games,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.points,
  });
  final int rank;
  final String name;
  final bool isOwnTeam;
  final int games;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDifference;
  final int points;

  factory LeagueStandingModel.fromJson(Map<String, dynamic> json) =>
      LeagueStandingModel(
        rank: json['rank'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        isOwnTeam: json['isOwnTeam'] as bool? ?? false,
        games: json['games'] as int? ?? 0,
        goalsFor: json['goalsFor'] as int? ?? 0,
        goalsAgainst: json['goalsAgainst'] as int? ?? 0,
        goalDifference: json['goalDifference'] as int? ?? 0,
        points: json['points'] as int? ?? 0,
      );
}

class BfvSyncConfigModel {
  const BfvSyncConfigModel({
    required this.teamId,
    required this.enabled,
    required this.syncIntervalMinutes,
    required this.lastStatus,
    required this.lastCreatedCount,
    required this.lastUpdatedCount,
    required this.lastSkippedCount,
    required this.lastConflictCount,
    this.id,
    this.teamPageUrl,
    this.icalUrl,
    this.officialViewUrl,
    this.widgetTeamId,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.lastMessage,
  });

  final String? id;
  final String teamId;
  final String? teamPageUrl;
  final String? icalUrl;
  final String? officialViewUrl;
  final String? widgetTeamId;
  final bool enabled;
  final int syncIntervalMinutes;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final String lastStatus;
  final String? lastMessage;
  final int lastCreatedCount;
  final int lastUpdatedCount;
  final int lastSkippedCount;
  final int lastConflictCount;

  factory BfvSyncConfigModel.fromJson(Map<String, dynamic> json) =>
      BfvSyncConfigModel(
        id: json['id'] as String?,
        teamId: json['teamId'] as String,
        teamPageUrl: json['teamPageUrl'] as String?,
        icalUrl: json['icalUrl'] as String?,
        officialViewUrl: json['officialViewUrl'] as String?,
        widgetTeamId: json['widgetTeamId'] as String?,
        enabled: json['enabled'] as bool? ?? true,
        syncIntervalMinutes: json['syncIntervalMinutes'] as int? ?? 30,
        lastAttemptAt: _optionalDate(json['lastAttemptAt']),
        lastSuccessAt: _optionalDate(json['lastSuccessAt']),
        lastStatus: json['lastStatus'] as String? ?? 'NOT_CONFIGURED',
        lastMessage: json['lastMessage'] as String?,
        lastCreatedCount: json['lastCreatedCount'] as int? ?? 0,
        lastUpdatedCount: json['lastUpdatedCount'] as int? ?? 0,
        lastSkippedCount: json['lastSkippedCount'] as int? ?? 0,
        lastConflictCount: json['lastConflictCount'] as int? ?? 0,
      );

  static DateTime? _optionalDate(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
