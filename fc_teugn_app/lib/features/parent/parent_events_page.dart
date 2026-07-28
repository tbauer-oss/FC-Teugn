import 'package:flutter/material.dart';

import '../calendar/calendar_page.dart';

class ParentEventsPage extends StatelessWidget {
  const ParentEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CalendarPage(canManage: false);
  }
}
