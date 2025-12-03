class Training {
  final String id;
  final DateTime date;
  final DateTime startTime;
  final DateTime? endTime;
  final String location;
  final String? note;

  Training({
    required this.id,
    required this.date,
    required this.startTime,
    this.endTime,
    required this.location,
    this.note,
  });

  factory Training.fromJson(Map<String, dynamic> json) {
    return Training(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      location: json['location'] as String,
      note: json['note'] as String?,
    );
  }
}
