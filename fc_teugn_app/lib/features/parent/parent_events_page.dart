import 'package:flutter/material.dart';

import '../calendar/calendar_page.dart';

class ParentEventsPage extends StatelessWidget {
  const ParentEventsPage({super.key, this.initialEventId, this.initialDate});

  final String? initialEventId;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) {
    return CalendarPage(
      canManage: false,
      initialEventId: initialEventId,
      initialDate: initialDate,
    );
  }
}
