import 'user.dart';

enum RSVPStatus { yes, no, maybe }

RSVPStatus rsvpFromString(String value) {
  switch (value) {
    case 'YES':
      return RSVPStatus.yes;
    case 'NO':
      return RSVPStatus.no;
    default:
      return RSVPStatus.maybe;
  }
}

class EventRsvp {
  final String id;
  final String userId;
  final RSVPStatus status;

  EventRsvp({required this.id, required this.userId, required this.status});

  factory EventRsvp.fromJson(Map<String, dynamic> json) {
    return EventRsvp(
      id: json['id'] as String,
      userId: json['userId'] as String,
      status: rsvpFromString(json['status'] as String),
    );
  }
}

class EventModel {
  final String id;
  final String title;
  final DateTime date;
  final DateTime? startTime;
  final String location;
  final String? description;
  final bool rsvpEnabled;
  final List<EventRsvp> rsvps;

  EventModel({
    required this.id,
    required this.title,
    required this.date,
    this.startTime,
    required this.location,
    this.description,
    required this.rsvpEnabled,
    required this.rsvps,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime'] as String) : null,
      location: json['location'] as String,
      description: json['description'] as String?,
      rsvpEnabled: json['rsvpEnabled'] as bool? ?? true,
      rsvps: (json['rsvps'] as List<dynamic>? ?? [])
          .map((e) => EventRsvp.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
