import 'event.dart';

class PersonalResponseModel {
  const PersonalResponseModel({
    required this.eventId,
    required this.playerId,
    required this.playerName,
    required this.teamName,
    required this.ageGroupCode,
    required this.title,
    required this.category,
    required this.startAt,
    required this.location,
    required this.responseStatus,
    required this.canRespond,
    required this.isOverdue,
    this.type = 'SPECIAL_EVENT',
    this.opponent,
    this.meetingAt,
    this.meetingLocation,
    this.responseDeadline,
    this.respondedAt,
    this.reason,
  });

  final String eventId;
  final String playerId;
  final String playerName;
  final String teamName;
  final String ageGroupCode;
  final String title;
  final String type;
  final String category;
  final DateTime startAt;
  final String location;
  final String? opponent;
  final DateTime? meetingAt;
  final String? meetingLocation;
  final DateTime? responseDeadline;
  final AttendanceStatus responseStatus;
  final DateTime? respondedAt;
  final String? reason;
  final bool canRespond;
  final bool isOverdue;

  bool get isOpen => responseStatus == AttendanceStatus.unknown;
  bool get isMatch =>
      type == 'MATCH' ||
      category.contains('MATCH') ||
      category.contains('TOURNAMENT') ||
      category == 'FOOTBALL_FESTIVAL';

  factory PersonalResponseModel.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['responseStatus'] as String? ?? 'UNKNOWN';
    return PersonalResponseModel(
      eventId: json['eventId'] as String,
      playerId: json['playerId'] as String,
      playerName: json['playerName'] as String? ?? 'Spieler',
      teamName: json['teamName'] as String? ?? '',
      ageGroupCode: json['ageGroupCode'] as String? ?? '',
      title: json['title'] as String? ?? 'Termin',
      type: json['type'] as String? ?? 'SPECIAL_EVENT',
      category: json['category'] as String? ?? 'SPECIAL_EVENT',
      startAt: DateTime.parse(json['startAt'] as String).toLocal(),
      location: json['location'] as String? ?? '',
      opponent: json['opponent'] as String?,
      meetingAt: json['meetingAt'] == null
          ? null
          : DateTime.parse(json['meetingAt'] as String).toLocal(),
      meetingLocation: json['meetingLocation'] as String?,
      responseDeadline: json['responseDeadline'] == null
          ? null
          : DateTime.parse(json['responseDeadline'] as String).toLocal(),
      responseStatus: switch (rawStatus) {
        'YES' => AttendanceStatus.yes,
        'NO' => AttendanceStatus.no,
        'MAYBE' => AttendanceStatus.maybe,
        _ => AttendanceStatus.unknown,
      },
      respondedAt: json['respondedAt'] == null
          ? null
          : DateTime.parse(json['respondedAt'] as String).toLocal(),
      reason: json['reason'] as String?,
      canRespond: json['canRespond'] as bool? ?? false,
      isOverdue: json['isOverdue'] as bool? ?? false,
    );
  }
}
