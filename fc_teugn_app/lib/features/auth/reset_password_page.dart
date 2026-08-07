import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import 'auth_controller.dart';

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: ClubLogo(size: 74),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Neues Passwort festlegen',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Der sichere Link ist 15 Minuten und nur einmal gültig. Nach dem Speichern meldest du dich auf allen Geräten neu an.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 22),
                          if (widget.token.isEmpty)
                            const _ResetError(
                              message: 'Der Reset-Link ist unvollständig.',
                            )
                          else ...[
                            TextFormField(
                              controller: _password,
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Neues Passwort',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                helperText: 'Mindestens 10 Zeichen',
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                  icon: Icon(_showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined),
                                ),
                              ),
                              validator: (value) => (value?.length ?? 0) < 10
                                  ? 'Mindestens 10 Zeichen eingeben'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmation,
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: const InputDecoration(
                                labelText: 'Passwort wiederholen',
                                prefixIcon: Icon(Icons.verified_user_outlined),
                              ),
                              validator: (value) => value != _password.text
                                  ? 'Die Passwörter stimmen nicht überein'
                                  : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _ResetError(message: _error!),
                            ],
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_reset_rounded),
                              label: const Text('Passwort speichern'),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () => context.go('/login'),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('Zur Anmeldung'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final message =
          await ref.read(authProvider.notifier).confirmPasswordReset(
                token: widget.token,
                password: _password.text,
              );
      if (!mounted) return;
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = exception.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

class _ResetError extends StatelessWidget {
  const _ResetError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      );
}
