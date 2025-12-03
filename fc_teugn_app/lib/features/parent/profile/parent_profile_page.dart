import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../auth/auth_controller.dart';

class ParentProfilePage extends ConsumerStatefulWidget {
  const ParentProfilePage({super.key});

  @override
  ConsumerState<ParentProfilePage> createState() => _ParentProfilePageState();
}

class _ParentProfilePageState extends ConsumerState<ParentProfilePage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _oldPwController = TextEditingController();
  final _newPwController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(_meProvider);
    final repo = ref.watch(repositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mein Konto')),
      body: me.when(
        data: (details) {
          _nameController.text = details.user.name;
          _phoneController.text = details.user.phone ?? '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await repo.updateProfile(name: _nameController.text, phone: _phoneController.text);
                  ref.refresh(_meProvider);
                },
                child: const Text('Speichern'),
              ),
              const Divider(),
              TextField(
                controller: _oldPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Aktuelles Passwort'),
              ),
              TextField(
                controller: _newPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await repo.changePassword(_oldPwController.text, _newPwController.text);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort geändert')));
                },
                child: const Text('Passwort ändern'),
              ),
              const Divider(),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Account löschen?'),
                      content: const Text('Dieser Schritt kann nicht rückgängig gemacht werden.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Löschen'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await repo.deleteAccount();
                    ref.read(authProvider.notifier).logout();
                  }
                },
                child: const Text('Account löschen'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
      ),
    );
  }
}

final _meProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.me();
});
