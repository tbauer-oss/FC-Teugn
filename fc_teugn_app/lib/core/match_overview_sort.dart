import 'models/event.dart';
import 'match_view_preferences.dart';

/// Lifecycle used only for the match overview ordering.
///
/// A match must not fall behind the complete future fixture list at kick-off.
/// The operational phase intentionally lasts through the local match day and
/// for several hours after the calculated end. This keeps delayed matches and
/// the live ticker reachable even when no explicit end time was stored.
enum MatchOverviewPhase { operational, upcoming, past }

DateTime matchOperationalUntil(EventModel event) {
  final configuredEnd = event.endAt;
  final durationMinutes = event.matchDetails?.durationMinutes ?? 90;
  final expectedEnd = configuredEnd != null && configuredEnd.isAfter(event.startAt)
      ? configuredEnd
      : event.startAt.add(
          Duration(minutes: durationMinutes.clamp(30, 240).toInt()),
        );
  final localStart = event.startAt.toLocal();
  final endOfMatchDay = DateTime(
    localStart.year,
    localStart.month,
    localStart.day + 1,
    6,
  );
  final delayedMatchSafetyWindow = expectedEnd.add(const Duration(hours: 6));
  return delayedMatchSafetyWindow.isAfter(endOfMatchDay)
      ? delayedMatchSafetyWindow
      : endOfMatchDay;
}

MatchOverviewPhase matchOverviewPhase(EventModel event, DateTime now) {
  if (!event.startAt.isAfter(now) &&
      !event.isCancelled &&
      now.isBefore(matchOperationalUntil(event))) {
    return MatchOverviewPhase.operational;
  }
  if (event.startAt.isAfter(now) || event.startAt.isAtSameMomentAs(now)) {
    return MatchOverviewPhase.upcoming;
  }
  return MatchOverviewPhase.past;
}

int compareMatchOverviewEvents(
  EventModel first,
  EventModel second,
  DateTime now,
  MatchSortOrder order,
) {
  if (order == MatchSortOrder.nextFirst) {
    final firstPhase = matchOverviewPhase(first, now);
    final secondPhase = matchOverviewPhase(second, now);
    final phaseOrder = firstPhase.index.compareTo(secondPhase.index);
    if (phaseOrder != 0) return phaseOrder;

    return switch (firstPhase) {
      MatchOverviewPhase.operational =>
        second.startAt.compareTo(first.startAt),
      MatchOverviewPhase.upcoming => first.startAt.compareTo(second.startAt),
      MatchOverviewPhase.past => second.startAt.compareTo(first.startAt),
    };
  }
  return order == MatchSortOrder.newestFirst
      ? second.startAt.compareTo(first.startAt)
      : first.startAt.compareTo(second.startAt);
}
