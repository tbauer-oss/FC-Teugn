import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_controller.dart';
import '../shared/page_scaffold.dart';
import 'absences_page.dart';
import 'assistant_page.dart';
import 'goals_page.dart';
import 'invitations_page.dart';
import 'polls_page.dart';
import 'talents_repository.dart';
import 'talents_widgets.dart';

class TalentsPage extends ConsumerWidget {
  const TalentsPage({super.key, required this.section});
  final String section;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(talentsOptionsProvider);
    final base =
        ref.watch(authProvider).user!.isTrainer ? '/trainer' : '/parent';
    return PageScaffold(
        title: 'Familie & Team',
        subtitle: 'Alles Wichtige für euren Vereinsalltag.',
        child: options.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => TalentsEmpty(
                text: talentsError(e),
                action: OutlinedButton(
                    onPressed: () => ref.invalidate(talentsOptionsProvider),
                    child: const Text('Erneut laden'))),
            data: (data) {
              final sections = {
                'assistant': 'Aufgaben',
                'absences': 'Abwesenheiten',
                'polls': 'Umfragen',
                'goals': 'Lernziele',
                if (data['capabilities']['invitations'] == true)
                  'invitations': 'Einladungen'
              };
              final selected =
                  sections.containsKey(section) ? section : 'assistant';
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DefaultTabController(
                      key: ValueKey(selected),
                      length: sections.length,
                      initialIndex: sections.keys.toList().indexOf(selected),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final label in sections.values) Tab(text: label)
                        ],
                        onTap: (index) => context.go(
                            '$base/talents/${sections.keys.elementAt(index)}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    switch (selected) {
                      'absences' => AbsencesPage(options: data),
                      'polls' => PollsPage(options: data),
                      'goals' => GoalsPage(options: data),
                      'invitations' => InvitationsPage(options: data),
                      _ => const AssistantPage()
                    },
                  ]);
            }));
  }
}
