import 'dart:typed_data';

import 'package:dio/dio.dart';

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
import 'models/team_operations.dart';
import 'models/emergency.dart';
import 'team_game_format.dart';

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
    String teamType = 'COMPETITIVE',
    String gender = 'MIXED',
    TeamGameFormat gameFormat = TeamGameFormat.football7,
    List<int> birthYears = const [],
    String? description,
    String? trainingLocation,
    List<String> trainingTimes = const [],
    String? homeVenue,
    String? bfvTeamId,
    String? dfbnetTeamId,
    String? bfvTeamUrl,
    bool isActive = true,
  }) async {
    final res = await client.dio.post('/organization/teams', data: {
      'ageGroupId': ageGroupId,
      'name': name,
      'shortName': shortName,
      'level': level,
      'teamType': teamType,
      'gender': gender,
      'gameFormat': gameFormat.apiValue,
      'birthYears': birthYears,
      'description': description,
      'trainingLocation': trainingLocation,
      'trainingTimes': trainingTimes,
      'homeVenue': homeVenue,
      'bfvTeamId': bfvTeamId,
      'dfbnetTeamId': dfbnetTeamId,
      'bfvTeamUrl': bfvTeamUrl,
      'isActive': isActive,
    });
    return TeamSummary.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TeamSummary> updateTeam({
    required String teamId,
    required String name,
    String? shortName,
    String? level,
    required String teamType,
    required String gender,
    required TeamGameFormat gameFormat,
    required List<int> birthYears,
    String? description,
    String? trainingLocation,
    required List<String> trainingTimes,
    String? homeVenue,
    String? bfvTeamId,
    String? dfbnetTeamId,
    String? bfvTeamUrl,
    required bool isActive,
  }) async {
    final res = await client.dio.patch('/organization/teams/$teamId', data: {
      'name': name,
      'shortName': shortName,
      'level': level,
      'teamType': teamType,
      'gender': gender,
      'gameFormat': gameFormat.apiValue,
      'birthYears': birthYears,
      'description': description,
      'trainingLocation': trainingLocation,
      'trainingTimes': trainingTimes,
      'homeVenue': homeVenue,
      'bfvTeamId': bfvTeamId,
      'dfbnetTeamId': dfbnetTeamId,
      'bfvTeamUrl': bfvTeamUrl,
      'isActive': isActive,
    });
    return TeamSummary.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TeamSummary> uploadTeamPhoto({
    required String teamId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final res = await client.dio.post(
      '/organization/teams/$teamId/photo',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType('image', 'jpeg'),
        ),
      }),
    );
    return TeamSummary.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> removeTeamPhoto(String teamId) async {
    await client.dio.delete('/organization/teams/$teamId/photo');
  }

  Future<Map<String, dynamic>> exportPersonalData() async {
    final res = await client.dio.get('/auth/privacy/export');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> privacyRequests() async {
    final res = await client.dio.get('/auth/privacy/requests');
    return (res.data as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> requestAccountErasure({
    required String confirmation,
    String? reason,
  }) async {
    final res = await client.dio.post(
      '/auth/privacy/erasure-requests',
      data: {'confirmation': confirmation, 'reason': reason},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> adminPrivacyRequests() async {
    final res = await client.dio.get('/admin/privacy-requests');
    return (res.data as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> reviewPrivacyRequest({
    required String requestId,
    required String status,
    String? reviewNote,
  }) async {
    await client.dio.patch('/admin/privacy-requests/$requestId', data: {
      'status': status,
      'reviewNote': reviewNote,
    });
  }

  Future<void> completeAccountErasure({
    required String requestId,
    String? reviewNote,
  }) async {
    await client.dio.post(
      '/admin/privacy-requests/$requestId/complete-erasure',
      data: {'reviewNote': reviewNote},
    );
  }

  Future<List<RuleProfileModel>> ruleProfiles() async {
    final res = await client.dio.get('/organization/rule-profiles');
    return (res.data as List<dynamic>)
        .map((item) => RuleProfileModel.fromJson(item as Map<String, dynamic>))
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
    final res = await client.dio
        .post('/organization/season-transitions/preview', data: {
      'name': name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'idempotencyKey': 'season-$name-${DateTime.now().microsecondsSinceEpoch}',
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

  Future<PlayerModel> uploadPlayerPhoto({
    required String playerId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    await client.dio.post(
      '/players/$playerId/photo',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType('image', 'jpeg'),
        ),
      }),
    );
    return player(playerId);
  }

  Future<void> removePlayerPhoto(String playerId) async {
    await client.dio.delete('/players/$playerId/photo');
  }

  Future<List<PlayerDocument>> playerDocuments(String playerId) async {
    final res = await client.dio.get('/players/$playerId/documents');
    return (res.data as List<dynamic>)
        .map((item) => PlayerDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> uploadPlayerDocument({
    required String playerId,
    required Uint8List bytes,
    required String fileName,
    required String type,
    required String title,
  }) async {
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'pdf' => DioMediaType('application', 'pdf'),
      'png' => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      _ => DioMediaType('image', 'jpeg'),
    };
    await client.dio.post(
      '/players/$playerId/documents',
      data: FormData.fromMap({
        'type': type,
        'title': title,
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: contentType,
        ),
      }),
    );
  }

  Future<void> deletePlayerDocument({
    required String playerId,
    required String documentId,
  }) async {
    await client.dio.delete(
      '/players/$playerId/documents/$documentId',
    );
  }

  Future<PlayerModel> createPlayer({
    required String teamId,
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
      'teamId': teamId,
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
      'teamId': player.teamId,
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

  Future<void> deletePlayer(String playerId) async {
    await client.dio.delete('/players/$playerId');
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

  Future<EmergencyAccessGrant> requestEmergencyAccess({
    required String eventId,
    required String password,
  }) async {
    final res = await client.dio.post(
      '/events/$eventId/emergency-access',
      data: {'password': password},
    );
    return EmergencyAccessGrant.fromJson(
      res.data as Map<String, dynamic>,
    );
  }

  Future<EmergencyView> emergencyView({
    required String eventId,
    required String accessToken,
  }) async {
    final res = await client.dio.get(
      '/events/$eventId/emergency-view',
      options: Options(headers: {
        'X-Emergency-Access-Token': accessToken,
      }),
    );
    return EmergencyView.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<EventModel>> createEvent(EventWriteData data) async {
    final res = await client.dio.post(
      '/events',
      data: data.toJson(),
      options: Options(
        receiveTimeout: data.recurrence == null
            ? const Duration(seconds: 15)
            : const Duration(seconds: 45),
      ),
    );
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

  Future<void> deleteEventPermanently({
    required String eventId,
    bool entireSeries = false,
  }) async {
    await client.dio.delete(
      '/events/$eventId',
      queryParameters: {
        'scope': entireSeries ? 'series' : 'single',
        'permanent': 'true',
      },
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
    required int periodCount,
    required int periodMinutes,
  }) async {
    await client.dio.put('/events/$eventId/match-details', data: {
      'opponent': opponent,
      'isHome': isHome,
      'competition': competition,
      'notes': notes,
      'ourGoals': ourGoals,
      'theirGoals': theirGoals,
      'periodCount': periodCount,
      'periodMinutes': periodMinutes,
      'durationMinutes': periodCount * periodMinutes,
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

  Future<MatchSquadModel> saveMatchSquad({
    required String eventId,
    required List<({String playerId, NominationStatus status})> members,
    String? formation,
  }) async {
    final response = await client.dio.put('/matches/$eventId/squad', data: {
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
    return MatchSquadModel.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> publishMatchSquad(String eventId) async {
    await client.dio.post('/matches/$eventId/squad/publish');
  }

  Future<LineupModel> saveLineup({
    required String eventId,
    required String formation,
    required int fieldSize,
    required LineupStatus status,
    required List<LineupPositionModel> positions,
    String? publicNote,
    String? tacticalNote,
  }) async {
    final response = await client.dio.put('/matches/$eventId/lineup', data: {
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
    return LineupModel.fromJson(
      response.data as Map<String, dynamic>,
    );
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

  Future<TickerDelegation> tickerDelegation(String eventId) async {
    final response =
        await client.dio.get('/matches/$eventId/ticker/delegation');
    return TickerDelegation.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<TickerDelegateUser?> saveTickerDelegation({
    required String eventId,
    String? parentId,
  }) async {
    final response = await client.dio.put(
      '/matches/$eventId/ticker/delegation',
      data: {'parentId': parentId},
    );
    final data = response.data as Map<String, dynamic>;
    return data['delegate'] == null
        ? null
        : TickerDelegateUser.fromJson(
            data['delegate'] as Map<String, dynamic>,
          );
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

  Future<AppUser> createMember({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    required List<String> teamIds,
    String? phone,
    String? playerId,
  }) async {
    final res = await client.dio.post('/admin/members', data: {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
      'role': userRoleApi(role),
      'teamIds': teamIds,
      'playerId': playerId,
    });
    return AppUser.fromJson(res.data as Map<String, dynamic>);
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
          (item) => AnnouncementModel.fromJson(item as Map<String, dynamic>),
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
          (item) => AppNotificationModel.fromJson(item as Map<String, dynamic>),
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

  Future<TeamOperationsOverview> teamOperations(String teamId) async {
    final res = await client.dio.get(
      '/team-operations',
      queryParameters: {'teamId': teamId},
    );
    return TeamOperationsOverview.fromJson(
      res.data as Map<String, dynamic>,
    );
  }

  Future<void> createTeamTask({
    required String teamId,
    required String title,
    required String category,
    String? description,
    String? assigneeUserId,
    DateTime? dueAt,
  }) async {
    await client.dio.post('/team-operations/tasks', data: {
      'teamId': teamId,
      'title': title,
      'category': category,
      'description': description,
      'assigneeUserId': assigneeUserId,
      'dueAt': dueAt?.toUtc().toIso8601String(),
    });
  }

  Future<void> updateTeamTaskStatus(String taskId, String status) async {
    await client.dio.put(
      '/team-operations/tasks/$taskId',
      data: {'status': status},
    );
  }

  Future<void> createEquipmentItem({
    required String teamId,
    required String name,
    required String category,
    required int quantity,
    String? notes,
  }) async {
    await client.dio.post('/team-operations/equipment', data: {
      'teamId': teamId,
      'name': name,
      'category': category,
      'quantity': quantity,
      'notes': notes,
    });
  }

  Future<void> assignEquipment({
    required String equipmentItemId,
    required int quantity,
    String? assignedToUserId,
    String? assignedToPlayerId,
    DateTime? dueAt,
  }) async {
    await client.dio.post(
      '/team-operations/equipment/$equipmentItemId/assignments',
      data: {
        'quantity': quantity,
        'assignedToUserId': assignedToUserId,
        'assignedToPlayerId': assignedToPlayerId,
        'dueAt': dueAt?.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> returnEquipment(String assignmentId) async {
    await client.dio.post(
      '/team-operations/equipment-assignments/$assignmentId/return',
    );
  }

  Future<void> createChecklistTemplate({
    required String teamId,
    required String title,
    required String category,
    required List<String> items,
    String? description,
  }) async {
    await client.dio.post('/team-operations/checklist-templates', data: {
      'teamId': teamId,
      'title': title,
      'category': category,
      'description': description,
      'items': items.map((item) => {'title': item}).toList(),
    });
  }

  Future<void> startChecklist({
    required String teamId,
    required String templateId,
    DateTime? dueAt,
  }) async {
    await client.dio.post('/team-operations/checklist-runs', data: {
      'teamId': teamId,
      'templateId': templateId,
      'dueAt': dueAt?.toUtc().toIso8601String(),
    });
  }

  Future<void> setChecklistItem({
    required String runId,
    required String itemId,
    required bool isCompleted,
  }) async {
    await client.dio.put(
      '/team-operations/checklist-runs/$runId/items/$itemId',
      data: {'isCompleted': isCompleted},
    );
  }
}
