import 'api_client.dart';
import 'models/event.dart';
import 'models/player.dart';
import 'models/user.dart';
import 'models/organization.dart';
import 'models/matchday.dart';
import 'models/statistics.dart';
import 'models/training.dart';
import 'models/communication.dart';
import 'models/competition_import.dart';

class DataRepository {
  final ApiClient client;

  DataRepository(this.client);

  Future<OrganizationContext> organizationContext() async {
    final res = await client.dio.get('/organization/context');
    return OrganizationContext.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TeamSummary> createTeam({
    required String ageGroupId,
    required String name,
    String? shortName,
    String? level,
  }) async {
    final res = await client.dio.post('/organization/teams', data: {
      'ageGroupId': ageGroupId,
      'name': name,
      'shortName': shortName,
      'level': level,
    });
    return TeamSummary.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<RuleProfileModel>> ruleProfiles() async {
    final res = await client.dio.get('/organization/rule-profiles');
    return (res.data as List<dynamic>)
        .map((item) =>
            RuleProfileModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<RuleProfileModel> createRuleProfile({
    required String teamId,
    required String name,
    required DateTime validFrom,
    required String gameFormat,
    required int teamSize,
    required int periodCount,
    required int periodMinutes,
    int? maxSquadSize,
    String? sourceNote,
    bool festivalMode = false,
    bool showResults = true,
    bool showTable = true,
  }) async {
    final res = await client.dio.post('/organization/rule-profiles', data: {
      'teamId': teamId,
      'name': name,
      'validFrom': validFrom.toIso8601String(),
      'gameFormat': gameFormat,
      'teamSize': teamSize,
      'maxSquadSize': maxSquadSize,
      'periodCount': periodCount,
      'periodMinutes': periodMinutes,
      'festivalMode': festivalMode,
      'showResults': showResults,
      'showTable': showTable,
      'sourceNote': sourceNote,
    });
    return RuleProfileModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> approveRuleProfile(String id) async {
    await client.dio.post('/organization/rule-profiles/$id/approve');
  }

  Future<List<SeasonTransitionModel>> seasonTransitions() async {
    final res = await client.dio.get('/organization/season-transitions');
    return (res.data as List<dynamic>)
        .map((item) =>
            SeasonTransitionModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SeasonTransitionModel> previewSeasonTransition({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final res =
        await client.dio.post('/organization/season-transitions/preview', data: {
      'name': name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'idempotencyKey':
          'season-$name-${DateTime.now().microsecondsSinceEpoch}',
    });
    return SeasonTransitionModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SeasonTransitionModel> applySeasonTransition(String id) async {
    final res =
        await client.dio.post('/organization/season-transitions/$id/apply');
    return SeasonTransitionModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<PlayerModel>> players() async {
    final res = await client.dio.get('/players');
    return (res.data as List<dynamic>)
        .map((e) => PlayerModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlayerModel> player(String id) async {
    final res = await client.dio.get('/players/$id');
    return PlayerModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlayerModel> createPlayer({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    String? preferredName,
    String? nationality,
    String? position,
    String? secondaryPosition,
    DominantFoot dominantFoot = DominantFoot.unknown,
    int? shirtNumber,
    PlayerStatus status = PlayerStatus.active,
    DateTime? joinedAt,
  }) async {
    final res = await client.dio.post('/players', data: {
      'firstName': firstName,
      'lastName': lastName,
      'birthDate': birthDate?.toIso8601String(),
      'preferredName': preferredName,
      'nationality': nationality,
      'position': position,
      'secondaryPosition': secondaryPosition,
      'dominantFoot': dominantFootApi(dominantFoot),
      'shirtNumber': shirtNumber,
      'status': playerStatusApi(status),
      'joinedAt': joinedAt?.toIso8601String(),
    });
    return PlayerModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlayerModel> updatePlayer(PlayerModel player) async {
    final res = await client.dio.put('/players/${player.id}', data: {
      'firstName': player.firstName,
      'lastName': player.lastName,
      'preferredName': player.preferredName,
      'birthDate': player.birthDate?.toIso8601String(),
      'nationality': player.nationality,
      'position': player.position,
      'secondaryPosition': player.secondaryPosition,
      'dominantFoot': dominantFootApi(player.dominantFoot),
      'shirtNumber': player.shirtNumber,
      'status': playerStatusApi(player.status),
      'joinedAt': player.joinedAt?.toIso8601String(),
      'photoUrl': player.photoUrl,
    });
    return PlayerModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> updateMedicalProfile({
    required String playerId,
    String? allergies,
    String? medications,
    String? conditions,
    String? physicianName,
    String? physicianPhone,
    String? emergencyNotes,
  }) async {
    await client.dio.put('/players/$playerId/medical', data: {
      'allergies': allergies,
      'medications': medications,
      'conditions': conditions,
      'physicianName': physicianName,
      'physicianPhone': physicianPhone,
      'emergencyNotes': emergencyNotes,
    });
  }

  Future<void> addEmergencyContact({
    required String playerId,
    required String name,
    required String phone,
    String? relationship,
    int priority = 1,
    bool isAuthorizedPickup = false,
  }) async {
    await client.dio.post('/players/$playerId/emergency-contacts', data: {
      'name': name,
      'phone': phone,
      'relationship': relationship,
      'priority': priority,
      'isAuthorizedPickup': isAuthorizedPickup,
    });
  }

  Future<void> addDevelopmentNote({
    required String playerId,
    required String title,
    required String notes,
    required String category,
    required String visibility,
    int? rating,
    DateTime? observedAt,
  }) async {
    await client.dio.post('/players/$playerId/development-notes', data: {
      'title': title,
      'notes': notes,
      'category': category,
      'visibility': visibility,
      'rating': rating,
      'observedAt': observedAt?.toIso8601String(),
    });
  }

  Future<void> updateConsent({
    required String playerId,
    required String type,
    required String status,
    String? note,
    DateTime? expiresAt,
  }) async {
    await client.dio.put('/players/$playerId/consents/$type', data: {
      'status': status,
      'note': note,
      'expiresAt': expiresAt?.toIso8601String(),
    });
  }

  Future<List<EventModel>> events({
    DateTime? from,
    DateTime? to,
    List<String> teamIds = const [],
    List<EventCategory> categories = const [],
  }) async {
    final res = await client.dio.get('/events', queryParameters: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (teamIds.isNotEmpty) 'teamIds': teamIds.join(','),
      if (categories.isNotEmpty)
        'categories': categories.map((item) => item.apiName).join(','),
    });
    return (res.data as List<dynamic>)
        .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EventModel> event(String eventId) async {
    final res = await client.dio.get('/events/$eventId');
    return EventModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<EventModel>> createEvent(EventWriteData data) async {
    final res = await client.dio.post('/events', data: data.toJson());
    if (res.data is List<dynamic>) {
      return (res.data as List<dynamic>)
          .map((item) => EventModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [EventModel.fromJson(res.data as Map<String, dynamic>)];
  }

  Future<EventModel> updateEvent({
    required String eventId,
    required EventWriteData data,
    bool entireSeries = false,
  }) async {
    final res = await client.dio.put(
      '/events/$eventId',
      queryParameters: {'scope': entireSeries ? 'series' : 'single'},
      data: data.toJson()..remove('recurrence'),
    );
    return EventModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> cancelEvent({
    required String eventId,
    required String reason,
    bool entireSeries = false,
  }) async {
    await client.dio.delete(
      '/events/$eventId',
      queryParameters: {'scope': entireSeries ? 'series' : 'single'},
      data: {'reason': reason},
    );
  }

  Future<void> setAttendance({
    required String eventId,
    required String playerId,
    required AttendanceStatus status,
    String? reason,
    bool? goalkeeperAvailable,
  }) async {
    await client.dio.post('/events/$eventId/attendance', data: {
      'playerId': playerId,
      'status': status.apiName,
      'reason': reason,
      'goalkeeperAvailable': goalkeeperAvailable,
    });
  }

  Future<void> finalizeAttendance(String eventId) async {
    await client.dio.post('/events/$eventId/attendance/finalize');
  }

  Future<({int recipients, int missingPlayers})> sendAttendanceReminders(
    String eventId, {
    String? message,
  }) async {
    final res = await client.dio.post(
      '/events/$eventId/attendance/reminders',
      data: {'message': message},
    );
    final data = res.data as Map<String, dynamic>;
    return (
      recipients: data['recipients'] as int? ?? 0,
      missingPlayers: data['missingPlayers'] as int? ?? 0,
    );
  }

  Future<String> createCalendarSubscription() async {
    final res = await client.dio.post('/events/calendar-subscription');
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  Future<void> createCarpoolOffer({
    required String eventId,
    required int seatsTotal,
    required String departureLocation,
    required DateTime departureAt,
    String? notes,
  }) async {
    await client.dio.post('/events/$eventId/carpool-offers', data: {
      'seatsTotal': seatsTotal,
      'departureLocation': departureLocation,
      'departureAt': departureAt.toUtc().toIso8601String(),
      'notes': notes,
    });
  }

  Future<void> requestCarpoolSeat({
    required String eventId,
    required String offerId,
    required String playerId,
  }) async {
    await client.dio.post(
      '/events/$eventId/carpool-offers/$offerId/passengers',
      data: {'playerId': playerId},
    );
  }

  Future<void> updateCarpoolPassenger({
    required String eventId,
    required String offerId,
    required String passengerId,
    required CarpoolRequestStatus status,
  }) async {
    await client.dio.patch(
      '/events/$eventId/carpool-offers/$offerId/passengers/$passengerId',
      data: {'status': status.name.toUpperCase()},
    );
  }

  Future<void> updateMatchDetails({
    required String eventId,
    required String opponent,
    required bool isHome,
    String? competition,
    String? notes,
    int? ourGoals,
    int? theirGoals,
  }) async {
    await client.dio.put('/events/$eventId/match-details', data: {
      'opponent': opponent,
      'isHome': isHome,
      'competition': competition,
      'notes': notes,
      'ourGoals': ourGoals,
      'theirGoals': theirGoals,
    });
  }

  Future<void> updateSquad({
    required String eventId,
    String? name,
    String? formation,
    List<String>? playerIds,
  }) async {
    await client.dio.put('/events/$eventId/squad', data: {
      'name': name,
      'formation': formation,
      'playerIds': playerIds,
    });
  }

  Future<List<MatchdayModel>> matches() async {
    final res = await client.dio.get('/matches');
    return (res.data as List<dynamic>)
        .map((item) => MatchdayModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MatchdayModel> match(String eventId) async {
    final res = await client.dio.get('/matches/$eventId');
    return MatchdayModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> saveMatchSquad({
    required String eventId,
    required List<({String playerId, NominationStatus status})> members,
    String? formation,
  }) async {
    await client.dio.put('/matches/$eventId/squad', data: {
      'formation': formation,
      'members': members
          .map(
            (member) => {
              'playerId': member.playerId,
              'status': apiEnum(member.status),
            },
          )
          .toList(),
    });
  }

  Future<void> publishMatchSquad(String eventId) async {
    await client.dio.post('/matches/$eventId/squad/publish');
  }

  Future<void> saveLineup({
    required String eventId,
    required String formation,
    required int fieldSize,
    required LineupStatus status,
    required List<LineupPositionModel> positions,
    String? publicNote,
    String? tacticalNote,
  }) async {
    await client.dio.put('/matches/$eventId/lineup', data: {
      'formation': formation,
      'fieldSize': fieldSize,
      'status': apiEnum(status),
      'publicNote': publicNote,
      'tacticalNote': tacticalNote,
      'positions': positions
          .map(
            (position) => {
              'playerId': position.player.id,
              'period': position.period,
              'positionCode': position.positionCode,
              'x': position.x,
              'y': position.y,
              'isStarter': position.isStarter,
              'isGoalkeeper': position.isGoalkeeper,
              'isCaptain': position.isCaptain,
              'shirtNumber': position.player.shirtNumber,
            },
          )
          .toList(),
    });
  }

  Future<LiveTickerModel> ticker(String eventId, {int after = 0}) async {
    final res = await client.dio.get(
      '/matches/$eventId/ticker',
      queryParameters: {'after': after},
    );
    return LiveTickerModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> sendTickerEvent({
    required String eventId,
    required String clientEventId,
    required TickerEventType type,
    String? scorerId,
    String? assistId,
    String? comment,
    int? period,
  }) async {
    await client.dio.post('/matches/$eventId/ticker/events', data: {
      'clientEventId': clientEventId,
      'type': apiEnum(type),
      'scorerId': scorerId,
      'assistId': assistId,
      'comment': comment,
      'period': period,
    });
  }

  Future<void> undoTickerEvent({
    required String eventId,
    required String clientEventId,
  }) async {
    await client.dio.post('/matches/$eventId/ticker/undo', data: {
      'clientEventId': clientEventId,
    });
  }

  Future<StatisticsOverview> statistics({
    DateTime? from,
    DateTime? to,
    List<String> teamIds = const [],
    String? competition,
    String? kind,
  }) async {
    final res = await client.dio.get('/statistics', queryParameters: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (teamIds.isNotEmpty) 'teamIds': teamIds.join(','),
      if (competition?.trim().isNotEmpty == true) 'competition': competition,
      if (kind?.trim().isNotEmpty == true) 'kind': kind,
    });
    return StatisticsOverview.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> recalculateMatchStatistics(String matchId) async {
    await client.dio.post('/statistics/matches/$matchId/recalculate');
  }

  Future<List<TrainingModel>> trainings() async {
    final res = await client.dio.get('/trainings');
    return (res.data as List<dynamic>)
        .map((item) => TrainingModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TrainingModel> training(String trainingId) async {
    final res = await client.dio.get('/trainings/$trainingId');
    return TrainingModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<TrainingExerciseModel>> trainingExercises() async {
    final res = await client.dio.get('/trainings/exercises');
    return (res.data as List<dynamic>)
        .map(
          (item) =>
              TrainingExerciseModel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> saveTrainingPlan({
    required String trainingId,
    required List<String> focusAreas,
    required int durationMinutes,
    required List<TrainingPlanItemModel> items,
    String? learningGoals,
    String? participantNotes,
    String? coaches,
    String? materials,
    String? pitchSetup,
    String? feedback,
  }) async {
    await client.dio.put('/trainings/$trainingId/plan', data: {
      'focusAreas': focusAreas,
      'durationMinutes': durationMinutes,
      'learningGoals': learningGoals,
      'participantNotes': participantNotes,
      'coaches': coaches,
      'materials': materials,
      'pitchSetup': pitchSetup,
      'feedback': feedback,
      'items': items
          .map(
            (item) => {
              'title': item.title,
              'phase': trainingApiEnum(item.phase),
              'durationMinutes': item.durationMinutes,
              'exerciseId': item.exerciseId,
              'notes': item.notes,
            },
          )
          .toList(),
    });
  }

  Future<void> saveTrainingAttendance({
    required String trainingId,
    required Map<String, TrainingAttendanceStatus> entries,
  }) async {
    await client.dio.put('/trainings/$trainingId/attendance', data: {
      'entries': entries.entries
          .map(
            (item) => {
              'playerId': item.key,
              'status': trainingApiEnum(item.value),
            },
          )
          .toList(),
    });
  }

  Future<void> saveTrainingExercise({
    String? exerciseId,
    required String teamId,
    required String title,
    required String category,
    required int durationMinutes,
    required String setup,
    required String instructions,
    String? materials,
    String? coachingPoints,
    String? variations,
    int? minPlayers,
    int? maxPlayers,
    bool isFavorite = false,
  }) async {
    final data = {
      'teamId': teamId,
      'title': title,
      'category': category,
      'durationMinutes': durationMinutes,
      'setup': setup,
      'instructions': instructions,
      'materials': materials,
      'coachingPoints': coachingPoints,
      'variations': variations,
      'minPlayers': minPlayers,
      'maxPlayers': maxPlayers,
      'isFavorite': isFavorite,
    };
    if (exerciseId == null) {
      await client.dio.post('/trainings/exercises', data: data);
    } else {
      await client.dio.put('/trainings/exercises/$exerciseId', data: data);
    }
  }

  Future<List<AppUser>> pendingUsers() async {
    final res = await client.dio.get('/admin/pending-users');
    return (res.data as List<dynamic>)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppUser>> members() async {
    final res = await client.dio.get('/admin/members');
    return (res.data as List<dynamic>)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveUser(
    String userId, {
    AccountStatus status = AccountStatus.approved,
    UserRole? role,
    List<String>? teamIds,
    String? playerId,
    String? relationship,
    String? adminNote,
    String? applicantMessage,
    RegistrationReviewStatus? reviewStatus,
  }) async {
    await client.dio.post('/admin/approve', data: {
      'userId': userId,
      'status': accountStatusApi(status),
      'role': role == null ? null : userRoleApi(role),
      'teamIds': teamIds,
      'playerId': playerId,
      'relationship': relationship,
      'adminNote': adminNote,
      'applicantMessage': applicantMessage,
      'reviewStatus': switch (reviewStatus) {
        RegistrationReviewStatus.newRequest => 'NEW',
        RegistrationReviewStatus.inReview => 'IN_REVIEW',
        RegistrationReviewStatus.needsInfo => 'NEEDS_INFO',
        RegistrationReviewStatus.completed => 'COMPLETED',
        null => null,
      },
    });
  }

  Future<void> assignParentPlayer({
    required String parentId,
    required String playerId,
    required String relationship,
    bool isLegalGuardian = true,
    bool canPickup = true,
    bool receivesCommunication = true,
  }) async {
    await client.dio.post('/admin/assign-parent-player', data: {
      'parentId': parentId,
      'playerId': playerId,
      'relationship': relationship,
      'isLegalGuardian': isLegalGuardian,
      'canPickup': canPickup,
      'receivesCommunication': receivesCommunication,
    });
  }

  Future<List<AnnouncementModel>> announcements({
    bool includeDrafts = false,
  }) async {
    final res = await client.dio.get(
      '/communications',
      queryParameters: {'includeDrafts': includeDrafts},
    );
    return (res.data as List<dynamic>)
        .map(
          (item) =>
              AnnouncementModel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> saveAnnouncement({
    required String title,
    required String body,
    required List<String> teamIds,
    required AnnouncementAudience audience,
    required AnnouncementPriority priority,
    required AnnouncementStatus status,
    DateTime? publishAt,
    bool requireReadReceipt = false,
    bool pushEnabled = true,
  }) async {
    await client.dio.post('/communications', data: {
      'title': title,
      'body': body,
      'teamIds': teamIds,
      'audience': communicationApiEnum(audience),
      'priority': communicationApiEnum(priority),
      'status': communicationApiEnum(status),
      'publishAt': publishAt?.toUtc().toIso8601String(),
      'requireReadReceipt': requireReadReceipt,
      'pushEnabled': pushEnabled,
    });
  }

  Future<void> markAnnouncementRead(String announcementId) async {
    await client.dio.post('/communications/$announcementId/read');
  }

  Future<List<AppNotificationModel>> notifications() async {
    final res = await client.dio.get('/notifications');
    return (res.data as List<dynamic>)
        .map(
          (item) =>
              AppNotificationModel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await client.dio.post('/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await client.dio.post('/notifications/read-all');
  }

  Future<List<NotificationPreferenceModel>> notificationPreferences() async {
    final res = await client.dio.get('/notifications/settings/preferences');
    return (res.data as List<dynamic>)
        .map(
          (item) => NotificationPreferenceModel.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<NotificationPreferenceModel>> saveNotificationPreferences(
    List<NotificationPreferenceModel> preferences,
  ) async {
    final res = await client.dio.put(
      '/notifications/settings/preferences',
      data: {
        'preferences': preferences
            .map(
              (item) => {
                'category': communicationApiEnum(item.category),
                'inApp': item.inApp,
                'push': item.push,
              },
            )
            .toList(),
      },
    );
    return (res.data as List<dynamic>)
        .map(
          (item) => NotificationPreferenceModel.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<PushConfiguration> pushConfiguration() async {
    final res = await client.dio.get('/notifications/settings/configuration');
    return PushConfiguration.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> registerWebPushSubscription(
    Map<String, dynamic> subscription,
  ) async {
    await client.dio.post('/notifications/settings/subscriptions', data: {
      'platform': 'WEB',
      'endpoint': subscription['endpoint'],
      'p256dh': subscription['p256dh'],
      'auth': subscription['auth'],
      'deviceName': 'FC Teugn Web-App',
    });
  }

  Future<CompetitionImportPreview> previewCompetitionImport({
    required String teamId,
    required CompetitionImportFormat format,
    required String provider,
    required String content,
    String? fileName,
  }) async {
    final res = await client.dio.post('/imports/competition/preview', data: {
      'teamId': teamId,
      'format': format.name.toUpperCase(),
      'provider': provider,
      'content': content,
      'fileName': fileName,
    });
    return CompetitionImportPreview.fromJson(
      res.data as Map<String, dynamic>,
    );
  }

  Future<void> applyCompetitionImport(
    String importId, {
    bool sourceWinsConflicts = false,
  }) async {
    await client.dio.post(
      '/imports/competition/$importId/apply',
      data: {
        'conflictPolicy': sourceWinsConflicts ? 'SOURCE_WINS' : 'SKIP',
      },
    );
  }
}
