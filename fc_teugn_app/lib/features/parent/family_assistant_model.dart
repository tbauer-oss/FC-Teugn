import '../../core/models/communication.dart';
import '../../core/models/event.dart';
import '../../core/models/matchday.dart';
import '../../core/models/personal_response.dart';

enum FamilyNotificationGroup {
  important,
  matchday,
  training,
  club,
}

String familyNotificationGroupLabel(FamilyNotificationGroup group) =>
    switch (group) {
      FamilyNotificationGroup.important => 'Wichtig',
      FamilyNotificationGroup.matchday => 'Spielbetrieb',
      FamilyNotificationGroup.training => 'Training',
      FamilyNotificationGroup.club => 'Vereinsinformationen',
    };

FamilyNotificationGroup familyNotificationGroup(
  AppNotificationModel notification,
) {
  switch (notification.category) {
    case NotificationCategory.urgent:
    case NotificationCategory.system:
      return FamilyNotificationGroup.important;
    case NotificationCategory.nomination:
    case NotificationCategory.lineup:
    case NotificationCategory.liveTicker:
    case NotificationCategory.match:
      return FamilyNotificationGroup.matchday;
    case NotificationCategory.eventReminder:
      return FamilyNotificationGroup.training;
    case NotificationCategory.event:
      final text = '${notification.title} ${notification.body}'.toLowerCase();
      return text.contains('training')
          ? FamilyNotificationGroup.training
          : FamilyNotificationGroup.club;
    case NotificationCategory.announcement:
    case NotificationCategory.registration:
      return FamilyNotificationGroup.club;
  }
}

bool isActiveFamilyTicker(MatchdayModel match) {
  final status = match.ticker?.status;
  return status == TickerStatus.live ||
      status == TickerStatus.paused ||
      status == TickerStatus.halfTime ||
      status == TickerStatus.interrupted;
}

/// Makes a time change readable when the server notification contains both
/// times. If it only contains descriptive text, that text remains authoritative.
String scheduleChangeSummary(AppNotificationModel notification) {
  final source = '${notification.title} ${notification.body}';
  final times = RegExp(r'\b([01]?\d|2[0-3]):[0-5]\d\b')
      .allMatches(source)
      .map((match) => match.group(0)!)
      .toSet()
      .toList(growable: false);
  if (times.length >= 2) {
    final subject = notification.title.trim().isEmpty
        ? 'Termin geändert'
        : notification.title.trim();
    return '$subject: ${times.first} → ${times[1]} Uhr';
  }
  return notification.body.trim().isNotEmpty
      ? notification.body.trim()
      : notification.title.trim();
}

bool isScheduleChangeNotification(AppNotificationModel notification) {
  final value = '${notification.title} ${notification.body}'.toLowerCase();
  return value.contains('verschob') ||
      value.contains('verlegt') ||
      value.contains('geändert') ||
      value.contains('neue uhrzeit') ||
      value.contains('änderung');
}

bool hasRelevantCarpool(EventModel event, Set<String> childIds) {
  final freeSeats = event.carpoolOffers.any((offer) => offer.freeSeats > 0);
  final openOwnNeed = event.carpoolNeeds.any(
    (need) =>
        need.status == CarpoolNeedStatus.open &&
        (childIds.isEmpty || childIds.contains(need.playerId)),
  );
  return freeSeats || openOwnNeed;
}

class FamilyTimelineItem {
  const FamilyTimelineItem({
    required this.eventId,
    required this.title,
    required this.startAt,
    required this.location,
    required this.isTraining,
    required this.isMatch,
    this.event,
    this.response,
  });

  final String eventId;
  final String title;
  final DateTime startAt;
  final String location;
  final bool isTraining;
  final bool isMatch;
  final EventModel? event;
  final PersonalResponseModel? response;
}

/// Joins calendar and personal-response data without rendering an occurrence
/// twice. Personal responses are especially important because generated regular
/// training occurrences can exist there before they are present in the general
/// event list.
List<FamilyTimelineItem> buildFamilyTimeline({
  required List<EventModel> events,
  required List<PersonalResponseModel> responses,
  required DateTime from,
  required DateTime until,
}) {
  final result = <FamilyTimelineItem>[];
  final byId = <String, FamilyTimelineItem>{};
  final eventKeys = <String, String>{};
  final responseKeys = <String, String>{};

  bool within(DateTime value) => !value.isBefore(from) && value.isBefore(until);

  for (final event in events) {
    if (!within(event.startAt) || event.isHiddenRegularOccurrence) continue;
    final minute = event.startAt.millisecondsSinceEpoch ~/ 60000;
    final canonical = '${event.teamId}|${event.type.name}|$minute|'
        '${event.title.trim().toLowerCase()}';
    if (eventKeys.containsKey(canonical)) continue;
    eventKeys[canonical] = event.id;
    byId[event.id] = FamilyTimelineItem(
      eventId: event.id,
      title: event.title,
      startAt: event.startAt,
      location: event.location,
      isTraining: event.type == EventType.training,
      isMatch: event.type == EventType.match,
      event: event,
    );
  }

  for (final response in responses) {
    if (!within(response.startAt)) continue;
    final minute = response.startAt.millisecondsSinceEpoch ~/ 60000;
    final canonical = '${response.teamName.trim().toLowerCase()}|'
        '${response.type}|$minute|${response.title.trim().toLowerCase()}';
    final effectiveId = responseKeys[canonical] ?? response.eventId;
    responseKeys[canonical] = effectiveId;
    final existing = byId[response.eventId] ?? byId[effectiveId];
    byId[effectiveId] = FamilyTimelineItem(
      eventId: effectiveId,
      title: existing?.title ?? response.title,
      startAt: existing?.startAt ?? response.startAt,
      location: existing?.location ?? response.location,
      isTraining: existing?.isTraining ?? !response.isMatch,
      isMatch: existing?.isMatch ?? response.isMatch,
      event: existing?.event,
      response: response,
    );
  }

  result.addAll(byId.values);
  result.sort((a, b) => a.startAt.compareTo(b.startAt));
  return result;
}
