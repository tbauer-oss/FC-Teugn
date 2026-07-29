const meetingOffsetOptions = <int>[
  15,
  30,
  45,
  60,
  75,
  90,
  105,
  120,
  135,
  150,
  165,
  180,
];

DateTime meetingTimeBefore(DateTime startAt, int minutesBefore) {
  if (minutesBefore <= 0) {
    throw ArgumentError.value(
      minutesBefore,
      'minutesBefore',
      'Der Abstand muss größer als null sein.',
    );
  }
  return startAt.subtract(Duration(minutes: minutesBefore));
}

int? standardMeetingOffset(DateTime startAt, DateTime? meetingAt) {
  if (meetingAt == null) return null;
  final difference = startAt.difference(meetingAt).inMinutes;
  return meetingOffsetOptions.contains(difference) ? difference : null;
}
