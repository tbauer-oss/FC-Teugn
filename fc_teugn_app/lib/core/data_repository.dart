import 'package:dio/dio.dart';
import 'api_client.dart';
import 'models/event.dart';
import 'models/match.dart';
import 'models/player.dart';
import 'models/training.dart';
import 'models/user.dart';

class DataRepository {
  final ApiClient client;

  DataRepository(this.client);

  Future<List<Training>> trainings() async {
    final res = await client.dio.get('/trainings');
    return (res.data as List<dynamic>).map((e) => Training.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<MatchModel>> matches() async {
    final res = await client.dio.get('/matches');
    return (res.data as List<dynamic>).map((e) => MatchModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setMatchRsvp(String matchId, String playerId, RSVPStatus status) async {
    await client.dio.post('/matches/$matchId/rsvp', data: {
      'playerId': playerId,
      'status': status == RSVPStatus.yes
          ? 'YES'
          : status == RSVPStatus.no
              ? 'NO'
              : 'MAYBE',
    });
  }

  Future<List<EventModel>> events() async {
    final res = await client.dio.get('/events');
    return (res.data as List<dynamic>).map((e) => EventModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setEventRsvp(String eventId, String userId, RSVPStatus status) async {
    await client.dio.post('/events/$eventId/rsvp', data: {
      'userId': userId,
      'status': status == RSVPStatus.yes
          ? 'YES'
          : status == RSVPStatus.no
              ? 'NO'
              : 'MAYBE',
    });
  }

  Future<AppUserDetails> me() async {
    final res = await client.dio.get('/users/me');
    return AppUserDetails.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> updateProfile({String? name, String? phone}) async {
    await client.dio.put('/users/me', data: {'name': name, 'phone': phone});
  }

  Future<void> changePassword(String current, String next) async {
    await client.dio.post('/users/me/password', data: {'currentPassword': current, 'newPassword': next});
  }

  Future<void> deleteAccount() async {
    await client.dio.delete('/users/me');
  }

  Future<List<PlayerModel>> players() async {
    final res = await client.dio.get('/players');
    return (res.data as List<dynamic>).map((e) => PlayerModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createPlayer({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String gender,
    String? position,
    int? shirtNumber,
    String? team,
    String? parentUserId,
  }) async {
    await client.dio.post('/players', data: {
      'firstName': firstName,
      'lastName': lastName,
      'birthDate': birthDate.toIso8601String(),
      'gender': gender,
      'position': position,
      'shirtNumber': shirtNumber,
      'team': team,
      'parentUserId': parentUserId,
    });
  }

  Future<void> createTraining({
    required DateTime date,
    required DateTime start,
    DateTime? end,
    required String location,
    String? note,
  }) async {
    await client.dio.post('/trainings', data: {
      'date': date.toIso8601String(),
      'startTime': start.toIso8601String(),
      'endTime': end?.toIso8601String(),
      'location': location,
      'note': note,
    });
  }

  Future<void> createEvent({
    required String title,
    required DateTime date,
    DateTime? startTime,
    required String location,
    String? description,
  }) async {
    await client.dio.post('/events', data: {
      'title': title,
      'date': date.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
      'location': location,
      'description': description,
    });
  }

  Future<void> createMatch({
    required MatchType type,
    required DateTime date,
    required DateTime kickOff,
    required String location,
    required String opponent,
    required bool isHome,
    String? competition,
    String? notes,
  }) async {
    await client.dio.post('/matches', data: {
      'type': type == MatchType.friendly ? 'FRIENDLY' : 'LEAGUE',
      'date': date.toIso8601String(),
      'kickOff': kickOff.toIso8601String(),
      'location': location,
      'opponent': opponent,
      'isHome': isHome,
      'competition': competition,
      'notes': notes,
    });
  }

  Future<void> saveLineup({
    required String matchId,
    required String formation,
    required List<Map<String, dynamic>> positions,
  }) async {
    await client.dio.post('/matches/$matchId/lineups', data: {
      'formation': formation,
      'positions': positions,
    });
  }

  Future<void> toggleGoal({required String matchId, required String playerId}) async {
    await client.dio.post('/matches/$matchId/goals/toggle', data: {'playerId': playerId});
  }
}

class AppUserDetails {
  final AppUser user;
  final List<PlayerModel> players;

  AppUserDetails({required this.user, required this.players});

  factory AppUserDetails.fromJson(Map<String, dynamic> json) {
    return AppUserDetails(
      user: AppUser.fromJson(json),
      players: (json['players'] as List<dynamic>? ?? [])
          .map((e) => PlayerModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
