import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isRegisterMode = false;
  UserRole _selectedRole = UserRole.coach;

  static const _defaultCoachEmail = 'tobias.bauer@fc-teugn.local';
  static const _defaultPassword = 'FC-Teugn_WEB!';

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'FC Teugn Jugend',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRegisterMode
                          ? 'Registriere dich als Trainer oder Elternteil'
                          : 'Melde dich mit deinem Zugang an',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (_isRegisterMode) ...[
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Bitte Name eingeben'
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Bitte E-Mail eingeben' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Passwort',
                      ),
                      obscureText: true,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Bitte Passwort eingeben' : null,
                    ),
                    if (_isRegisterMode) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<UserRole>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Rolle',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: UserRole.coach,
                            child: Text('Trainer/in'),
                          ),
                          DropdownMenuItem(
                            value: UserRole.parent,
                            child: Text('Elternteil'),
                          ),
                        ],
                        onChanged: (role) {
                          if (role != null) {
                            setState(() {
                              _selectedRole = role;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Telefon (optional)',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ],
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
                                  if (_isRegisterMode) {
                                    authCtrl.register(
                                      name: _nameController.text.trim(),
                                      email: _emailController.text.trim(),
                                      password: _passwordController.text.trim(),
                                      phone: _phoneController.text.trim().isEmpty
                                          ? null
                                          : _phoneController.text.trim(),
                                      role: _selectedRole,
                                    );
                                  } else {
                                    authCtrl.login(
                                      _emailController.text.trim(),
                                      _passwordController.text.trim(),
                                    );
                                  }
                                }
                              },
                        child: authState.loading
                            ? const CircularProgressIndicator()
                            : Text(_isRegisterMode ? 'Registrieren' : 'Anmelden'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: authState.loading
                            ? null
                            : () {
                                setState(() {
                                  _isRegisterMode = !_isRegisterMode;
                                });
                              },
                        child: Text(
                          _isRegisterMode
                              ? 'Zurück zum Login'
                              : 'Jetzt als Trainer/Eltern registrieren',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.admin_panel_settings),
                        onPressed: authState.loading
                            ? null
                            : () {
                                _emailController.text = _defaultCoachEmail;
                                _passwordController.text = _defaultPassword;
                                authCtrl.login(
                                  _emailController.text,
                                  _passwordController.text,
                                );
                              },
                        label: const Text('Trainerbereich öffnen'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Standardpasswort für neu angelegte Accounts: FC-Teugn_WEB!\n'
                      'Du kannst dich jetzt selbst als Trainer oder Elternteil registrieren.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
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
}
