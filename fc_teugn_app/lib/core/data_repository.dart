import 'api_client.dart';
import 'models/event.dart';
import 'models/player.dart';
import 'models/user.dart';
import 'models/organization.dart';

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

  Future<List<EventModel>> events() async {
    final res = await client.dio.get('/events');
    return (res.data as List<dynamic>)
        .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EventModel> createEvent({
    required EventType type,
    required String title,
    required DateTime startAt,
    DateTime? endAt,
    required String location,
    String? description,
  }) async {
    final res = await client.dio.post('/events', data: {
      'type': type == EventType.match
          ? 'MATCH'
          : type == EventType.event
              ? 'EVENT'
              : 'TRAINING',
      'title': title,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
      'location': location,
      'description': description,
    });
    return EventModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> setAttendance({
    required String eventId,
    required String playerId,
    required AttendanceStatus status,
  }) async {
    await client.dio.post('/events/$eventId/attendance', data: {
      'playerId': playerId,
      'status': status == AttendanceStatus.yes
          ? 'YES'
          : status == AttendanceStatus.no
              ? 'NO'
              : status == AttendanceStatus.maybe
                  ? 'MAYBE'
                  : 'UNKNOWN',
    });
  }

  Future<void> finalizeAttendance(String eventId) async {
    await client.dio.post('/events/$eventId/attendance/finalize');
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
  }) async {
    await client.dio.post('/admin/approve', data: {
      'userId': userId,
      'status': status == AccountStatus.blocked
          ? 'BLOCKED'
          : status == AccountStatus.approved
              ? 'APPROVED'
              : 'PENDING',
      'role': role == null ? null : userRoleApi(role),
      'teamIds': teamIds,
      'playerId': playerId,
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
}
