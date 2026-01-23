import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import '../../core/providers.dart';

class TrainerApprovalsPage extends ConsumerWidget {
  const TrainerApprovalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingUsers = ref.watch(pendingUsersProvider);
    final repository = ref.watch(repositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Freigaben',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: pendingUsers.when(
              data: (users) {
                if (users.isEmpty) {
                  return const Center(child: Text('Keine offenen Anfragen.'));
                }
                return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      title: Text(user.name),
                      subtitle: Text('${user.email} • ${_roleLabel(user.role)}'),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              await repository.approveUser(user.id, status: AccountStatus.blocked);
                              ref.invalidate(pendingUsersProvider);
                            },
                            child: const Text('Blocken'),
                          ),
                          FilledButton(
                            onPressed: () async {
                              await repository.approveUser(user.id, status: AccountStatus.approved);
                              ref.invalidate(pendingUsersProvider);
                            },
                            child: const Text('Freigeben'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Fehler: $err')),
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.trainerAdmin:
        return 'Trainer Admin';
      case UserRole.trainer:
        return 'Trainer';
      case UserRole.parent:
        return 'Elternteil';
    }
  }
}
