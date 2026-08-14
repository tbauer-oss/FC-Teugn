import '../../core/models/event.dart';

String dashboardEventRoute({
  required EventModel event,
  required bool isTrainer,
  Set<String> personalResponseEventIds = const <String>{},
}) {
  if (event.type == EventType.training &&
      (!isTrainer || personalResponseEventIds.contains(event.id))) {
    return Uri(
      path: isTrainer ? '/trainer/family' : '/parent/family',
      queryParameters: {'eventId': event.id},
    ).toString();
  }
  if (event.type == EventType.match) {
    if (event.category.isTournament) {
      return isTrainer ? '/trainer/matches' : '/parent/matches';
    }
    return '${isTrainer ? '/trainer' : '/parent'}/matches/${event.id}';
  }
  if (event.type == EventType.training) {
    return event.id.startsWith('training-plan:')
        ? '/trainer/events'
        : '/trainer/training/${event.id}';
  }
  return isTrainer ? '/trainer/events' : '/parent/events';
}
