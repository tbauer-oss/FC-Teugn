class LiveMatchSurface {
  const LiveMatchSurface();

  bool get supported => false;

  Future<bool> update({
    required String matchId,
    required String homeTeam,
    required String awayTeam,
    required int homeScore,
    required int awayScore,
    required int minute,
    required String status,
    required bool finished,
    required String actionUrl,
  }) async =>
      false;

  Future<void> cancel(String matchId) async {}
}

const liveMatchSurface = LiveMatchSurface();
