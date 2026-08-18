String roleCorrectPushActionRoute(
  String action, {
  required bool isTrainer,
}) {
  final parsed = Uri.tryParse(action.trim());
  final path = parsed?.path ?? '';
  if (path == '/reset-password' &&
      ((parsed?.queryParameters['token']?.isNotEmpty ?? false) ||
          (parsed?.queryParameters['requestId']?.isNotEmpty ?? false))) {
    return Uri(
      path: '/reset-password',
      queryParameters: {
        if (parsed!.queryParameters['token']?.isNotEmpty ?? false)
          'token': parsed.queryParameters['token']!,
        if (parsed.queryParameters['requestId']?.isNotEmpty ?? false)
          'requestId': parsed.queryParameters['requestId']!,
      },
    ).toString();
  }
  if (path == '/messages' || path.startsWith('/messages/')) {
    final base = isTrainer ? '/trainer/messages' : '/parent/messages';
    return parsed?.hasQuery == true ? '$base?${parsed!.query}' : base;
  }
  if (path == '/trainer/messages' || path == '/parent/messages') {
    final base = isTrainer ? '/trainer/messages' : '/parent/messages';
    return parsed?.hasQuery == true ? '$base?${parsed!.query}' : base;
  }
  if (path == '/events' || path.startsWith('/events/')) {
    final base = isTrainer ? '/trainer/events' : '/parent/events';
    final eventId = path.startsWith('/events/')
        ? path.substring('/events/'.length).split('/').first
        : '';
    final parameters = <String, String>{
      ...?parsed?.queryParameters,
      if (eventId.isNotEmpty) 'eventId': eventId,
    };
    return Uri(path: base, queryParameters: parameters).toString();
  }
  if (path == '/family' || path.startsWith('/family/')) {
    final base = isTrainer ? '/trainer/family' : '/parent/family';
    return parsed?.hasQuery == true ? '$base?${parsed!.query}' : base;
  }
  if (path == '/support' || path.startsWith('/support/')) {
    final base = isTrainer ? '/trainer/support' : '/parent/support';
    final ticketId = path.startsWith('/support/')
        ? path.substring('/support/'.length).split('/').first
        : '';
    return ticketId.isEmpty ? base : '$base?ticketId=$ticketId';
  }
  if (path == '/matches') {
    return isTrainer ? '/trainer/matches' : '/parent/matches';
  }
  if (path.startsWith('/matches/')) {
    final matchId = path.substring('/matches/'.length).split('/').first;
    if (matchId.isNotEmpty) {
      final destination =
          isTrainer ? '/trainer/matches/$matchId' : '/parent/matches/$matchId';
      return parsed?.hasQuery == true
          ? '$destination?${parsed!.query}'
          : destination;
    }
  }
  if (path.startsWith('/trainer/') && !isTrainer) return '/parent';
  if (path.startsWith('/parent/') && isTrainer) return '/trainer';
  if (path.startsWith('/')) return path;
  return isTrainer ? '/trainer' : '/parent';
}
