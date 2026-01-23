import 'api_client.dart';
import 'models/event.dart';
import 'models/player.dart';
import 'models/user.dart';

class DataRepository {
  final ApiClient client;

  DataRepository(this.client);

  Future<List<PlayerModel>> players() async {
    final res = await client.dio.get('/players');
    return (res.data as List<dynamic>)
        .map((e) => PlayerModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlayerModel> createPlayer({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    String? position,
    int? shirtNumber,
    String? parentId,
  }) async {
    final res = await client.dio.post('/players', data: {
      'firstName': firstName,
      'lastName': lastName,
      'birthDate': birthDate?.toIso8601String(),
      'position': position,
      'shirtNumber': shirtNumber,
      'parentId': parentId,
    });
    return PlayerModel.fromJson(res.data as Map<String, dynamic>);
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

  Future<void> approveUser(String userId, {AccountStatus status = AccountStatus.approved}) async {
    await client.dio.post('/admin/approve', data: {
      'userId': userId,
      'status': status == AccountStatus.blocked
          ? 'BLOCKED'
          : status == AccountStatus.approved
              ? 'APPROVED'
              : 'PENDING',
    });
  }

  Future<void> assignParentPlayer({required String parentId, required String playerId}) async {
    await client.dio.post('/admin/assign-parent-player', data: {
      'parentId': parentId,
      'playerId': playerId,
    });
  }
}
