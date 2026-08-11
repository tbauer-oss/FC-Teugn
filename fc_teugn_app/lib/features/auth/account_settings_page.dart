import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/models/user.dart';
import '../shared/page_scaffold.dart';
import 'auth_controller.dart';

class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({super.key, this.initialUser});

  final AppUser? initialUser;

  @override
  ConsumerState<AccountSettingsPage> createState() =>
      _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;

  @override
  void initState() {
    super.initState();
    final user = widget.initialUser ?? ref.read(authProvider).user!;
    _firstName = TextEditingController(text: user.resolvedFirstName);
    _lastName = TextEditingController(text: user.resolvedLastName);
    _email = TextEditingController(text: user.email);
    _phone = TextEditingController(text: user.phone ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _errorText(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_profileKey.currentState!.validate() || _savingProfile) return;
    setState(() => _savingProfile = true);
    try {
      final message = await ref.read(authProvider.notifier).updateOwnProfile(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      if (mounted) _message(message);
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    if (!_passwordKey.currentState!.validate() || _savingPassword) return;
    setState(() => _savingPassword = true);
    try {
      final message = await ref.read(authProvider.notifier).changeOwnPassword(
            currentPassword: _currentPassword.text,
            newPassword: _newPassword.text,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.verified_user_rounded, color: AppColors.teal),
          title: const Text('Passwort geändert'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Neu anmelden'),
            ),
          ],
        ),
      );
      ref.read(authProvider.notifier).clearSession();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Mein Konto',
      subtitle: 'Persönliche Daten und Passwort sicher selbst verwalten.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final profile = _SettingsCard(
            title: 'Persönliche Daten',
            subtitle: 'Diese Angaben werden für dein Vereinskonto verwendet.',
            icon: Icons.person_outline_rounded,
            child: Form(
              key: _profileKey,
              child: AutofillGroup(
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('account-first-name'),
                            controller: _firstName,
                            autofillHints: const [AutofillHints.givenName],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Vorname *',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Vorname fehlt'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('account-last-name'),
                            controller: _lastName,
                            autofillHints: const [AutofillHints.familyName],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Nachname *',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Nachname fehlt'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('account-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail-Adresse *',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)
                            ? null
                            : 'Gültige E-Mail-Adresse eingeben';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('account-phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Telefonnummer (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('save-account-profile'),
                        onPressed: _savingProfile ? null : _saveProfile,
                        icon: _savingProfile
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                            _savingProfile ? 'Speichere …' : 'Daten speichern'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          final password = _SettingsCard(
            title: 'Passwort ändern',
            subtitle: 'Danach meldest du dich auf allen Geräten erneut an.',
            icon: Icons.password_rounded,
            child: Form(
              key: _passwordKey,
              child: AutofillGroup(
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('current-password'),
                      controller: _currentPassword,
                      obscureText: !_showCurrentPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Aktuelles Passwort *',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _showCurrentPassword
                              ? 'Passwort verbergen'
                              : 'Passwort anzeigen',
                          onPressed: () => setState(
                            () => _showCurrentPassword = !_showCurrentPassword,
                          ),
                          icon: Icon(_showCurrentPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Aktuelles Passwort eingeben'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('new-password'),
                      controller: _newPassword,
                      obscureText: !_showNewPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Neues Passwort *',
                        helperText: 'Mindestens 10 Zeichen',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          tooltip: _showNewPassword
                              ? 'Passwort verbergen'
                              : 'Passwort anzeigen',
                          onPressed: () => setState(
                            () => _showNewPassword = !_showNewPassword,
                          ),
                          icon: Icon(_showNewPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) < 10
                          ? 'Mindestens 10 Zeichen erforderlich'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('confirm-password'),
                      controller: _confirmPassword,
                      obscureText: !_showNewPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _savePassword(),
                      decoration: const InputDecoration(
                        labelText: 'Neues Passwort wiederholen *',
                        prefixIcon: Icon(Icons.key_rounded),
                      ),
                      validator: (value) => value != _newPassword.text
                          ? 'Passwörter stimmen nicht überein'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('save-account-password'),
                        onPressed: _savingPassword ? null : _savePassword,
                        icon: _savingPassword
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.password_rounded),
                        label: Text(
                            _savingPassword ? 'Ändere …' : 'Passwort ändern'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (constraints.maxWidth >= 820) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: profile),
                const SizedBox(width: 18),
                Expanded(child: password),
              ],
            );
          }
          return Column(
            children: [profile, const SizedBox(height: 16), password],
          );
        },
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.yellowSoft,
                  foregroundColor: AppColors.gold,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
