import 'package:flutter/material.dart';

import '../calendar/calendar_page.dart';

class ParentEventsPage extends StatelessWidget {
  const ParentEventsPage({super.key, this.initialEventId});

  final String? initialEventId;

  @override
  Widget build(BuildContext context) {
    return CalendarPage(
      canManage: false,
      initialEventId: initialEventId,
    );
  }
}
