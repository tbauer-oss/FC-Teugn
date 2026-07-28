import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/user.dart';
import '../../core/api_client.dart';
import 'auth_controller.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  UserRole _selectedRole = UserRole.parent;
  String? _selectedTeamId;
  late final Future<List<_RegistrationTeam>> _teams;

  @override
  void initState() {
    super.initState();
    _teams = _loadTeams();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final authCtrl = ref.read(authProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Registrierung')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Neuen Account anlegen',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => v == null || v.isEmpty ? 'Bitte Name eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'E-Mail'),
                      validator: (v) => v == null || v.isEmpty ? 'Bitte E-Mail eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(labelText: 'Passwort'),
                      obscureText: true,
                      validator: (v) => v == null || v.isEmpty ? 'Bitte Passwort eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UserRole>(
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(labelText: 'Rolle'),
                      items: const [
                        DropdownMenuItem(
                          value: UserRole.parent,
                          child: Text('Elternteil'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.player,
                          child: Text('Spieler/in'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.coach,
                          child: Text('Trainer/in'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.assistantCoach,
                          child: Text('Co-Trainer/in'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.teamManager,
                          child: Text('Teamorganisation'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedRole = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Telefon (optional)'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<_RegistrationTeam>>(
                      future: _teams,
                      builder: (context, snapshot) {
                        final teams = snapshot.data ?? const <_RegistrationTeam>[];
                        if (teams.isEmpty) {
                          return const TextField(
                            enabled: false,
                            decoration: InputDecoration(
                              labelText: 'Verein / Mannschaft',
                              hintText: 'FC Teugn',
                            ),
                          );
                        }
                        _selectedTeamId ??= teams.first.id;
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedTeamId,
                          decoration: const InputDecoration(
                            labelText: 'Verein / Mannschaft',
                          ),
                          items: [
                            for (final team in teams)
                              DropdownMenuItem(
                                value: team.id,
                                child: Text(team.label),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedTeamId = value),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (authState.error != null)
                      Text(
                        authState.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: authState.loading
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  authCtrl.register(
                                    name: _nameController.text.trim(),
                                    email: _emailController.text.trim(),
                                    password: _passwordController.text.trim(),
                                    phone: _phoneController.text.trim().isEmpty
                                        ? null
                                        : _phoneController.text.trim(),
                                    role: _selectedRole,
                                    teamName: 'FC Teugn',
                                    teamId: _selectedTeamId,
                                  );
                                }
                              },
                        child: authState.loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Registrieren'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: authState.loading ? null : () => context.go('/login'),
                      child: const Text('Zurück zum Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<List<_RegistrationTeam>> _loadTeams() async {
    try {
      final response = await ApiClient().dio.get('/organization/public');
      final result = <_RegistrationTeam>[];
      for (final entry in response.data as List<dynamic>) {
        final data = entry as Map<String, dynamic>;
        final club = data['club'] as Map<String, dynamic>;
        final season = data['season'] as Map<String, dynamic>;
        for (final ageGroupEntry in data['ageGroups'] as List<dynamic>) {
          final ageGroup = ageGroupEntry as Map<String, dynamic>;
          for (final teamEntry in ageGroup['teams'] as List<dynamic>) {
            final team = teamEntry as Map<String, dynamic>;
            result.add(
              _RegistrationTeam(
                id: team['id'] as String,
                label:
                    '${club['name']} · ${ageGroup['name']} · ${team['name']} (${season['name']})',
              ),
            );
          }
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }
}

class _RegistrationTeam {
  const _RegistrationTeam({required this.id, required this.label});

  final String id;
  final String label;
}
