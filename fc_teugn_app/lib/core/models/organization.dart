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
        primaryColor: json['primaryColor'] as String? ?? '#176B87',
        accentColor: json['accentColor'] as String? ?? '#FFB000',
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

  factory AgeGroupSummary.fromJson(Map<String, dynamic> json) => AgeGroupSummary(
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
    this.shortName,
    this.level,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? shortName;
  final String? level;
  final bool isActive;
  final AgeGroupSummary ageGroup;
  final String seasonName;

  String get displayName => '${ageGroup.code}-Jugend · $name';

  factory TeamSummary.fromJson(Map<String, dynamic> json) => TeamSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        shortName: json['shortName'] as String?,
        level: json['level'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        ageGroup: AgeGroupSummary.fromJson(
          json['ageGroup'] as Map<String, dynamic>,
        ),
        seasonName:
            (json['season'] as Map<String, dynamic>?)?['name'] as String? ?? '',
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
        season:
            SeasonSummary.fromJson(json['season'] as Map<String, dynamic>),
        currentTeam:
            TeamSummary.fromJson(json['currentTeam'] as Map<String, dynamic>),
        ageGroups: (json['ageGroups'] as List<dynamic>? ?? [])
            .map((item) =>
                AgeGroupSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        teams: (json['teams'] as List<dynamic>? ?? [])
            .map(
                (item) => TeamSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        permissions: (json['permissions'] as List<dynamic>? ?? [])
            .map((item) => item as String)
            .toSet(),
        metrics: OrganizationMetrics.fromJson(
          json['metrics'] as Map<String, dynamic>? ?? const {},
        ),
      );
}
