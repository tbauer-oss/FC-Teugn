import '../team_game_format.dart';

class ClubSummary {
  const ClubSummary({
    required this.id,
    required this.name,
    required this.shortName,
    required this.primaryColor,
    required this.accentColor,
  });

  final String id;
  final String name;
  final String shortName;
  final String primaryColor;
  final String accentColor;

  factory ClubSummary.fromJson(Map<String, dynamic> json) => ClubSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        shortName: json['shortName'] as String? ?? '',
        primaryColor: json['primaryColor'] as String? ?? '#171918',
        accentColor: json['accentColor'] as String? ?? '#FFE600',
      );
}

class SeasonSummary {
  const SeasonSummary({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        isActive: json['isActive'] as bool? ?? false,
      );
}

class AgeGroupSummary {
  const AgeGroupSummary({
    required this.id,
    required this.name,
    required this.code,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String code;
  final int sortOrder;

  factory AgeGroupSummary.fromJson(Map<String, dynamic> json) =>
      AgeGroupSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        sortOrder: json['sortOrder'] as int? ?? 0,
      );
}

class TeamSummary {
  const TeamSummary({
    required this.id,
    required this.name,
    required this.ageGroup,
    required this.seasonName,
    this.teamNumber = 1,
    this.apiDisplayName,
    this.shortName,
    this.level,
    this.isActive = true,
    this.teamType = 'COMPETITIVE',
    this.gender = 'MIXED',
    this.gameFormat = TeamGameFormat.football7,
    this.periodCount = 2,
    this.periodMinutes = 30,
    this.defaultLineup,
    this.customFormations = const [],
    this.birthYears = const [],
    this.description,
    this.trainingLocation,
    this.trainingTimes = const [],
    this.trainingPartnerIds = const [],
    this.matchdayTimes = const [],
    this.seasonStartDate,
    this.seasonEndDate,
    this.indoorSeasonStartDate,
    this.indoorSeasonEndDate,
    this.indoorTrainingLocation,
    this.indoorTrainingTimes = const [],
    this.indoorTrainingPartnerIds = const [],
    this.homeVenue,
    this.bfvTeamId,
    this.dfbnetTeamId,
    this.bfvTeamUrl,
    this.photoUrl,
    this.staff = const [],
  });

  final String id;
  final String name;
  final int teamNumber;
  final String? apiDisplayName;
  final String? shortName;
  final String? level;
  final bool isActive;
  final String teamType;
  final String gender;
  final TeamGameFormat gameFormat;
  final int periodCount;
  final int periodMinutes;
  final TeamDefaultLineup? defaultLineup;
  final List<String> customFormations;
  final List<int> birthYears;
  final String? description;
  final String? trainingLocation;
  final List<String> trainingTimes;
  final List<String> trainingPartnerIds;
  final List<String> matchdayTimes;
  final DateTime? seasonStartDate;
  final DateTime? seasonEndDate;
  final DateTime? indoorSeasonStartDate;
  final DateTime? indoorSeasonEndDate;
  final String? indoorTrainingLocation;
  final List<String> indoorTrainingTimes;
  final List<String> indoorTrainingPartnerIds;
  final String? homeVenue;
  final String? bfvTeamId;
  final String? dfbnetTeamId;
  final String? bfvTeamUrl;
  final String? photoUrl;
  final List<TeamStaffMember> staff;
  final AgeGroupSummary ageGroup;
  final String seasonName;

  String get displayName {
    if (apiDisplayName?.isNotEmpty == true) return apiDisplayName!;
    final compactName = name.trim();
    if (RegExp(
      '^${RegExp.escape(ageGroup.code)}\\d+\$',
      caseSensitive: false,
    ).hasMatch(compactName)) {
      return '$compactName-Jugend';
    }
    if (compactName.toLowerCase().endsWith('-jugend')) return compactName;
    return '${ageGroup.code}-Jugend · $compactName';
  }

  List<String> get formationOptions => <String>{
        if (defaultLineup != null) defaultLineup!.formation,
        ...customFormations,
        ...gameFormat.formations,
      }.toList();

  factory TeamSummary.fromJson(Map<String, dynamic> json) => TeamSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 1,
        apiDisplayName: json['displayName'] as String?,
        shortName: json['shortName'] as String?,
        level: json['level'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        teamType: json['teamType'] as String? ?? 'COMPETITIVE',
        gender: json['gender'] as String? ?? 'MIXED',
        gameFormat: TeamGameFormat.fromApi(json['gameFormat']),
        periodCount: (json['periodCount'] as num?)?.toInt() ?? 2,
        periodMinutes: (json['periodMinutes'] as num?)?.toInt() ?? 30,
        defaultLineup: json['defaultLineup'] == null
            ? null
            : TeamDefaultLineup.fromJson(
                json['defaultLineup'] as Map<String, dynamic>,
              ),
        customFormations:
            (json['customFormations'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
        birthYears: (json['birthYears'] as List<dynamic>? ?? [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(),
        description: json['description'] as String?,
        trainingLocation: json['trainingLocation'] as String?,
        trainingTimes: (json['trainingTimes'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        trainingPartnerIds: (json['trainingPartnerIds'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        matchdayTimes: (json['matchdayTimes'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        seasonStartDate: DateTime.tryParse(
          json['seasonStartDate'] as String? ?? '',
        ),
        seasonEndDate: DateTime.tryParse(
          json['seasonEndDate'] as String? ?? '',
        ),
        indoorSeasonStartDate: DateTime.tryParse(
          json['indoorSeasonStartDate'] as String? ?? '',
        ),
        indoorSeasonEndDate: DateTime.tryParse(
          json['indoorSeasonEndDate'] as String? ?? '',
        ),
        indoorTrainingLocation: json['indoorTrainingLocation'] as String?,
        indoorTrainingTimes:
            (json['indoorTrainingTimes'] as List<dynamic>? ?? [])
                .whereType<String>()
                .toList(),
        indoorTrainingPartnerIds:
            (json['indoorTrainingPartnerIds'] as List<dynamic>? ?? [])
                .whereType<String>()
                .toList(),
        homeVenue: json['homeVenue'] as String?,
        bfvTeamId: json['bfvTeamId'] as String?,
        dfbnetTeamId: json['dfbnetTeamId'] as String?,
        bfvTeamUrl: json['bfvTeamUrl'] as String?,
        photoUrl: json['photoUrl'] as String?,
        staff: (json['staff'] as List<dynamic>? ?? [])
            .map((item) =>
                TeamStaffMember.fromJson(item as Map<String, dynamic>))
            .toList(),
        ageGroup: AgeGroupSummary.fromJson(
          json['ageGroup'] as Map<String, dynamic>,
        ),
        seasonName:
            (json['season'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      );
}

class TeamDefaultLineup {
  const TeamDefaultLineup({
    required this.formation,
    required this.positions,
  });

  final String formation;
  final List<TeamDefaultLineupPosition> positions;

  factory TeamDefaultLineup.fromJson(Map<String, dynamic> json) =>
      TeamDefaultLineup(
        formation: json['formation'] as String? ?? 'Individuell',
        positions: (json['positions'] as List<dynamic>? ?? const [])
            .map(
              (item) => TeamDefaultLineupPosition.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class TeamDefaultLineupPosition {
  const TeamDefaultLineupPosition({
    required this.player,
    required this.positionCode,
    required this.x,
    required this.y,
    required this.isGoalkeeper,
    required this.isCaptain,
    required this.sortOrder,
  });

  final TeamDefaultLineupPlayer player;
  final String positionCode;
  final double x;
  final double y;
  final bool isGoalkeeper;
  final bool isCaptain;
  final int sortOrder;

  factory TeamDefaultLineupPosition.fromJson(Map<String, dynamic> json) =>
      TeamDefaultLineupPosition(
        player: TeamDefaultLineupPlayer.fromJson(
          json['player'] as Map<String, dynamic>,
        ),
        positionCode: json['positionCode'] as String? ?? 'FELD',
        x: (json['x'] as num?)?.toDouble() ?? .5,
        y: (json['y'] as num?)?.toDouble() ?? .5,
        isGoalkeeper: json['isGoalkeeper'] as bool? ?? false,
        isCaptain: json['isCaptain'] as bool? ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

class TeamDefaultLineupPositionInput {
  const TeamDefaultLineupPositionInput({
    required this.playerId,
    required this.positionCode,
    required this.x,
    required this.y,
    required this.isGoalkeeper,
    required this.isCaptain,
  });

  final String playerId;
  final String positionCode;
  final double x;
  final double y;
  final bool isGoalkeeper;
  final bool isCaptain;

  Map<String, Object?> toJson() => {
        'playerId': playerId,
        'positionCode': positionCode,
        'x': x,
        'y': y,
        'isGoalkeeper': isGoalkeeper,
        'isCaptain': isCaptain,
      };
}

class TeamDefaultLineupPlayer {
  const TeamDefaultLineupPlayer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.status,
    this.preferredName,
    this.position,
    this.secondaryPosition,
    this.shirtNumber,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? position;
  final String? secondaryPosition;
  final int? shirtNumber;
  final String status;

  String get name => preferredName?.trim().isNotEmpty == true
      ? preferredName!.trim()
      : '$firstName $lastName'.trim();

  factory TeamDefaultLineupPlayer.fromJson(Map<String, dynamic> json) =>
      TeamDefaultLineupPlayer(
        id: json['id'] as String,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        preferredName: json['preferredName'] as String?,
        position: json['position'] as String?,
        secondaryPosition: json['secondaryPosition'] as String?,
        shirtNumber: (json['shirtNumber'] as num?)?.toInt(),
        status: json['status'] as String? ?? 'ACTIVE',
      );
}

class TeamStaffMember {
  const TeamStaffMember({
    required this.id,
    required this.name,
    required this.role,
    this.email,
  });

  final String id;
  final String name;
  final String role;
  final String? email;

  factory TeamStaffMember.fromJson(Map<String, dynamic> json) =>
      TeamStaffMember(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        email: json['email'] as String?,
      );
}

class OrganizationMetrics {
  const OrganizationMetrics({
    required this.players,
    required this.members,
    required this.upcomingEvents,
    required this.pendingApprovals,
  });

  final int players;
  final int members;
  final int upcomingEvents;
  final int pendingApprovals;

  factory OrganizationMetrics.fromJson(Map<String, dynamic> json) =>
      OrganizationMetrics(
        players: json['players'] as int? ?? 0,
        members: json['members'] as int? ?? 0,
        upcomingEvents: json['upcomingEvents'] as int? ?? 0,
        pendingApprovals: json['pendingApprovals'] as int? ?? 0,
      );
}

class OrganizationContext {
  const OrganizationContext({
    required this.club,
    required this.season,
    required this.currentTeam,
    required this.ageGroups,
    required this.teams,
    required this.permissions,
    required this.metrics,
  });

  final ClubSummary club;
  final SeasonSummary season;
  final TeamSummary currentTeam;
  final List<AgeGroupSummary> ageGroups;
  final List<TeamSummary> teams;
  final Set<String> permissions;
  final OrganizationMetrics metrics;

  bool can(String permission) => permissions.contains(permission);

  factory OrganizationContext.fromJson(Map<String, dynamic> json) =>
      OrganizationContext(
        club: ClubSummary.fromJson(json['club'] as Map<String, dynamic>),
        season: SeasonSummary.fromJson(json['season'] as Map<String, dynamic>),
        currentTeam:
            TeamSummary.fromJson(json['currentTeam'] as Map<String, dynamic>),
        ageGroups: (json['ageGroups'] as List<dynamic>? ?? [])
            .map((item) =>
                AgeGroupSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        teams: (json['teams'] as List<dynamic>? ?? [])
            .map((item) => TeamSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        permissions: (json['permissions'] as List<dynamic>? ?? [])
            .map((item) => item as String)
            .toSet(),
        metrics: OrganizationMetrics.fromJson(
          json['metrics'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

class RuleProfileModel {
  const RuleProfileModel({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.ageGroupCode,
    required this.name,
    required this.validFrom,
    required this.gameFormat,
    required this.teamSize,
    required this.periodCount,
    required this.periodMinutes,
    required this.version,
    required this.approved,
    this.maxSquadSize,
    this.sourceNote,
    this.approvedByName,
  });

  final String id;
  final String teamId;
  final String teamName;
  final String ageGroupCode;
  final String name;
  final DateTime validFrom;
  final String gameFormat;
  final int teamSize;
  final int? maxSquadSize;
  final int periodCount;
  final int periodMinutes;
  final int version;
  final bool approved;
  final String? sourceNote;
  final String? approvedByName;

  factory RuleProfileModel.fromJson(Map<String, dynamic> json) {
    final team = json['team'] as Map<String, dynamic>? ?? const {};
    final ageGroup = team['ageGroup'] as Map<String, dynamic>? ?? const {};
    final approvedBy = json['approvedBy'] as Map<String, dynamic>? ?? const {};
    return RuleProfileModel(
      id: json['id'] as String,
      teamId: json['teamId'] as String,
      teamName: team['name'] as String? ?? '',
      ageGroupCode: ageGroup['code'] as String? ?? '',
      name: json['name'] as String,
      validFrom: DateTime.parse(json['validFrom'] as String),
      gameFormat: json['gameFormat'] as String,
      teamSize: json['teamSize'] as int,
      maxSquadSize: json['maxSquadSize'] as int?,
      periodCount: json['periodCount'] as int,
      periodMinutes: json['periodMinutes'] as int,
      version: json['version'] as int? ?? 1,
      approved: json['approvedAt'] != null,
      sourceNote: json['sourceNote'] as String?,
      approvedByName: approvedBy['name'] as String?,
    );
  }
}

class SeasonTransitionModel {
  const SeasonTransitionModel({
    required this.id,
    required this.status,
    required this.idempotencyKey,
    required this.plan,
    required this.preview,
    required this.createdAt,
    this.result,
    this.actorName,
  });

  final String id;
  final String status;
  final String idempotencyKey;
  final Map<String, dynamic> plan;
  final Map<String, dynamic> preview;
  final Map<String, dynamic>? result;
  final DateTime createdAt;
  final String? actorName;

  String get targetSeasonName =>
      (plan['targetSeason'] as Map<String, dynamic>?)?['name'] as String? ?? '';
  bool get canApply => status == 'PREVIEWED';

  factory SeasonTransitionModel.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>? ?? const {};
    return SeasonTransitionModel(
      id: json['id'] as String,
      status: json['status'] as String,
      idempotencyKey: json['idempotencyKey'] as String,
      plan: Map<String, dynamic>.from(json['plan'] as Map),
      preview: Map<String, dynamic>.from(json['preview'] as Map),
      result: json['result'] == null
          ? null
          : Map<String, dynamic>.from(json['result'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      actorName: actor['name'] as String?,
    );
  }
}
