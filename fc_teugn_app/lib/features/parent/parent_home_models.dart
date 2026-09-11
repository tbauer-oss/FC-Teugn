import '../../core/models/event.dart';
import '../../core/models/personal_response.dart';
import '../../core/models/player.dart';
import 'family_assistant_model.dart';

/// An attendance belongs to a child AND an event, never just to an event.
class ParentVisit {
  const ParentVisit({required this.player, required this.item});
  final PlayerModel player;
  final FamilyTimelineItem item;
  String get key => '${item.eventId}:${player.id}';
  PersonalResponseModel? get response => item.response;
  String get childLabel => '${player.displayName} · ${player.teamCode}';
  String get title {
    if (!item.isMatch) return item.title;
    if (item.event != null) return item.event!.fixtureDisplayTitle;
    final opponent = response?.opponent?.trim() ?? '';
    if (opponent.isNotEmpty && !item.title.contains(opponent)) {
      return 'FC Teugn ${player.teamCode} – $opponent';
    }
    return item.title;
  }

  DateTime? get meetingAt => item.event?.meetingAt ?? response?.meetingAt;
}

List<ParentVisit> buildParentVisits({
  required List<PlayerModel> players,
  required List<EventModel> events,
  required List<PersonalResponseModel> responses,
  required DateTime now,
}) {
  final result = <ParentVisit>[];
  final from = DateTime(now.year, now.month, now.day);
  for (final player in players) {
    final ownResponses =
        responses.where((r) => r.playerId == player.id).toList();
    final responseIds = ownResponses.map((r) => r.eventId).toSet();
    final ownEvents = events.where((event) {
      if (responseIds.contains(event.id)) return true;
      if (event.excludedParticipantPlayerIds.contains(player.id)) return false;
      if (event.participantPlayerIds.isNotEmpty) {
        return event.participantPlayerIds.contains(player.id);
      }
      return event.teamId == player.teamId ||
          event.targetTeams.any((t) => t.id == player.teamId);
    }).toList();
    final timeline = buildFamilyTimeline(
        events: ownEvents,
        responses: ownResponses,
        from: from,
        until: from.add(const Duration(days: 43)));
    for (final item in timeline) {
      if (item.event?.isCancelled == true) continue;
      final end =
          item.event?.endAt ?? item.startAt.add(const Duration(hours: 2));
      if (end.isBefore(now)) continue;
      result.add(ParentVisit(player: player, item: item));
    }
  }
  result.sort((a, b) {
    final byDate = a.item.startAt.compareTo(b.item.startAt);
    return byDate == 0
        ? a.player.displayName.compareTo(b.player.displayName)
        : byDate;
  });
  return result;
}

List<ParentVisit> nextParentVisits(List<ParentVisit> visits,
    {required bool match}) {
  final relevant = visits
      .where((v) => match
          ? v.item.isMatch
          : (v.item.event?.type == EventType.training ||
              v.response?.type == 'TRAINING' ||
              v.response?.category == 'TRAINING'))
      .toList();
  if (relevant.isEmpty) return const [];
  // Siblings at the same event retain separate, explicitly named controls.
  return relevant
      .where((v) => v.item.eventId == relevant.first.item.eventId)
      .toList();
}

String parentClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String parentDate(DateTime value, {bool short = false}) {
  const weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag'
  ];
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember'
  ];
  return short
      ? '${weekdays[value.weekday - 1].substring(0, 2)}, ${value.day}.${value.month}.'
      : '${weekdays[value.weekday - 1]}, ${value.day}. ${months[value.month - 1]}';
}
