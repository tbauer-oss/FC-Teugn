import 'package:flutter/material.dart';

import '../calendar/calendar_page.dart';

class TrainerEventsPage extends StatelessWidget {
  const TrainerEventsPage({super.key, this.initialEventId});

  final String? initialEventId;

  @override
  Widget build(BuildContext context) {
    return CalendarPage(
      canManage: true,
      initialEventId: initialEventId,
    );
  }
}
