class StatisticsOverview {
  const StatisticsOverview({
    required this.team,
    required this.players,
    required this.matches,
    required this.individualScope,
    required this.seasons,
    this.selectedSeason,
    this.performanceCenter,
  });

  final TeamStatistics team;
  final List<PlayerSeasonStatistic> players;
  final List<MatchResultStatistic> matches;
  final String individualScope;
  final List<StatisticsSeason> seasons;
  final StatisticsSeason? selectedSeason;
  final PerformanceCenter? performanceCenter;

  factory StatisticsOverview.fromJson(Map<String, dynamic> json) =>
      StatisticsOverview(
        team: TeamStatistics.fromJson(json['team'] as Map<String, dynamic>),
        players: (json['players'] as List<dynamic>? ?? const [])
            .map(
              (item) => PlayerSeasonStatistic.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        matches: (json['matches'] as List<dynamic>? ?? const [])
            .map(
              (item) => MatchResultStatistic.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        individualScope: (json['privacy']
                as Map<String, dynamic>?)?['individualScope'] as String? ??
            'OWN_PLAYERS',
        seasons: (json['seasons'] as List<dynamic>? ?? const [])
            .map(
              (item) => StatisticsSeason.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        selectedSeason: json['selectedSeason'] == null
            ? null
            : StatisticsSeason.fromJson(
                json['selectedSeason'] as Map<String, dynamic>,
              ),
        performanceCenter: json['performanceCenter'] == null
            ? null
            : PerformanceCenter.fromJson(
                json['performanceCenter'] as Map<String, dynamic>,
              ),
      );
}

class PerformanceCenter {
  const PerformanceCenter({
    required this.ratedMatches,
    required this.unratedMatches,
    required this.players,
    this.teamAverage,
  });

  final double? teamAverage;
  final int ratedMatches;
  final int unratedMatches;
  final List<PlayerPerformance> players;

  factory PerformanceCenter.fromJson(Map<String, dynamic> json) =>
      PerformanceCenter(
        teamAverage: (json['teamAverage'] as num?)?.toDouble(),
        ratedMatches: (json['ratedMatches'] as num?)?.toInt() ?? 0,
        unratedMatches: (json['unratedMatches'] as num?)?.toInt() ?? 0,
        players: (json['players'] as List<dynamic>? ?? const [])
            .map(
              (item) => PlayerPerformance.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class PlayerPerformance {
  const PlayerPerformance({
    required this.playerId,
    required this.name,
    required this.average,
    required this.ratedMatches,
    required this.trend,
    required this.recent,
    this.shirtNumber,
    this.lastScore,
  });

  final String playerId;
  final String name;
  final int? shirtNumber;
  final double average;
  final int ratedMatches;
  final int? lastScore;
  final double trend;
  final List<RecentPerformance> recent;

  factory PlayerPerformance.fromJson(Map<String, dynamic> json) =>
      PlayerPerformance(
        playerId: json['playerId'] as String,
        name: json['name'] as String? ?? 'Spieler',
        shirtNumber: (json['shirtNumber'] as num?)?.toInt(),
        average: (json['average'] as num?)?.toDouble() ?? 0,
        ratedMatches: (json['ratedMatches'] as num?)?.toInt() ?? 0,
        lastScore: (json['lastScore'] as num?)?.toInt(),
        trend: (json['trend'] as num?)?.toDouble() ?? 0,
        recent: (json['recent'] as List<dynamic>? ?? const [])
            .map(
              (item) => RecentPerformance.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class RecentPerformance {
  const RecentPerformance({
    required this.eventId,
    required this.startAt,
    required this.opponent,
    required this.score,
  });

  final String eventId;
  final DateTime startAt;
  final String opponent;
  final int score;

  factory RecentPerformance.fromJson(Map<String, dynamic> json) =>
      RecentPerformance(
        eventId: json['eventId'] as String,
        startAt: DateTime.parse(json['startAt'] as String).toLocal(),
        opponent: json['opponent'] as String? ?? 'Gegner',
        score: (json['score'] as num).toInt(),
      );
}

class StatisticsSeason {
  const StatisticsSeason({
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

  factory StatisticsSeason.fromJson(Map<String, dynamic> json) =>
      StatisticsSeason(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Saison',
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        isActive: json['isActive'] as bool? ?? false,
      );
}

class TeamStatistics {
  const TeamStatistics({
    required this.matches,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.winRate,
    required this.goalsPerMatch,
    required this.form,
  });

  final int matches;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final double winRate;
  final double goalsPerMatch;
  final List<String> form;

  factory TeamStatistics.fromJson(Map<String, dynamic> json) => TeamStatistics(
        matches: json['matches'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        draws: json['draws'] as int? ?? 0,
        losses: json['losses'] as int? ?? 0,
        goalsFor: json['goalsFor'] as int? ?? 0,
        goalsAgainst: json['goalsAgainst'] as int? ?? 0,
        winRate: (json['winRate'] as num?)?.toDouble() ?? 0,
        goalsPerMatch: (json['goalsPerMatch'] as num?)?.toDouble() ?? 0,
        form: (json['form'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}

class PlayerSeasonStatistic {
  const PlayerSeasonStatistic({
    required this.id,
    required this.name,
    required this.appearances,
    required this.starts,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.cleanSheets,
    required this.cleanSheetEligible,
    this.shirtNumber,
    this.career,
  });

  final String id;
  final String name;
  final int? shirtNumber;
  final int appearances;
  final int starts;
  final int minutes;
  final int goals;
  final int assists;
  final int cleanSheets;
  final bool cleanSheetEligible;
  final PlayerStatisticTotals? career;

  factory PlayerSeasonStatistic.fromJson(Map<String, dynamic> json) =>
      PlayerSeasonStatistic(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Spieler',
        shirtNumber: json['shirtNumber'] as int?,
        appearances: json['appearances'] as int? ?? 0,
        starts: json['starts'] as int? ?? 0,
        minutes: json['minutes'] as int? ?? 0,
        goals: json['goals'] as int? ?? 0,
        assists: json['assists'] as int? ?? 0,
        cleanSheets: json['cleanSheets'] as int? ?? 0,
        cleanSheetEligible: json['cleanSheetEligible'] as bool? ?? false,
        career: json['career'] == null
            ? null
            : PlayerStatisticTotals.fromJson(
                json['career'] as Map<String, dynamic>,
              ),
      );
}

class PlayerStatisticTotals {
  const PlayerStatisticTotals({
    required this.appearances,
    required this.starts,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.cleanSheets,
    required this.cleanSheetEligible,
  });

  final int appearances;
  final int starts;
  final int minutes;
  final int goals;
  final int assists;
  final int cleanSheets;
  final bool cleanSheetEligible;

  factory PlayerStatisticTotals.fromJson(Map<String, dynamic> json) =>
      PlayerStatisticTotals(
        appearances: json['appearances'] as int? ?? 0,
        starts: json['starts'] as int? ?? 0,
        minutes: json['minutes'] as int? ?? 0,
        goals: json['goals'] as int? ?? 0,
        assists: json['assists'] as int? ?? 0,
        cleanSheets: json['cleanSheets'] as int? ?? 0,
        cleanSheetEligible: json['cleanSheetEligible'] as bool? ?? false,
      );
}

class MatchResultStatistic {
  const MatchResultStatistic({
    required this.id,
    required this.startAt,
    required this.opponent,
    required this.ourGoals,
    required this.theirGoals,
    required this.result,
    required this.isHome,
    this.competition,
  });

  final String id;
  final DateTime startAt;
  final String opponent;
  final String? competition;
  final int ourGoals;
  final int theirGoals;
  final String result;
  final bool isHome;

  factory MatchResultStatistic.fromJson(Map<String, dynamic> json) =>
      MatchResultStatistic(
        id: json['id'] as String,
        startAt: DateTime.parse(json['startAt'] as String),
        opponent: json['opponent'] as String? ?? 'Gegner',
        competition: json['competition'] as String?,
        ourGoals: json['ourGoals'] as int? ?? 0,
        theirGoals: json['theirGoals'] as int? ?? 0,
        result: json['result'] as String? ?? 'DRAW',
        isHome: json['isHome'] as bool? ?? true,
      );
}
