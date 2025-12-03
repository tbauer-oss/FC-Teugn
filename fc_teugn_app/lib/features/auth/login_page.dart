import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  static const _defaultCoachEmail = 'tobias.bauer@fc-teugn.local';
  static const _defaultPassword = 'FC-Teugn_WEB!';

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
                    const SizedBox(height: 8),
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
                                  authCtrl.login(
                                    _emailController.text.trim(),
                                    _passwordController.text.trim(),
                                  );
                                }
                              },
                        child: authState.loading
                            ? const CircularProgressIndicator()
                            : const Text('Anmelden'),
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
                      'Trainer-Accounts werden per Seed-Skript angelegt.\n'
                      'Eltern-Accounts legen wir im Adminbereich an; sie ändern ihr Passwort beim ersten Login.',
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
