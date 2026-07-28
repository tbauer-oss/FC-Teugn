import 'package:flutter/material.dart';

import '../calendar/calendar_page.dart';

class TrainerEventsPage extends StatelessWidget {
  const TrainerEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CalendarPage(canManage: true);
  }
}
