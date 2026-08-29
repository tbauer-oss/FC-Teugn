import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/app_theme_controller.dart';
import '../../core/biometric_auth/biometric_auth.dart';
import '../../core/models/user.dart';
import '../integrations/spielplus_page.dart';
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
  late final AppUser _user;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _savingBiometric = false;
  BiometricLoginSettings? _biometricSettings;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser ?? ref.read(authProvider).user!;
    _firstName = TextEditingController(text: _user.resolvedFirstName);
    _lastName = TextEditingController(text: _user.resolvedLastName);
    _email = TextEditingController(text: _user.email);
    _phone = TextEditingController(text: _user.phone ?? '');
    unawaited(_loadBiometricSettings());
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

  Future<void> _loadBiometricSettings() async {
    final settings =
        await ref.read(authProvider.notifier).biometricLoginSettings();
    if (mounted) setState(() => _biometricSettings = settings);
  }

  Future<void> _setBiometricLogin(bool enabled) async {
    if (_savingBiometric) return;
    setState(() => _savingBiometric = true);
    try {
      final controller = ref.read(authProvider.notifier);
      final message = enabled
          ? await controller.enableBiometricLogin()
          : await controller.disableBiometricLogin();
      if (!mounted) return;
      _message(message);
      await _loadBiometricSettings();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _savingBiometric = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Mein Konto',
      subtitle: 'Persönliche Daten und Passwort sicher selbst verwalten.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final themePreference = ref.watch(appThemePreferenceProvider);
          final appearance = _SettingsCard(
            title: 'Darstellung',
            subtitle:
                'System folgt automatisch der Hell-/Dunkel-Einstellung des Geräts.',
            icon: Icons.contrast_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<AppThemePreference>(
                  key: const ValueKey('app-theme-selection'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: AppThemePreference.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Hell'),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Dunkel'),
                    ),
                  ],
                  selected: {themePreference},
                  onSelectionChanged: (selection) => unawaited(
                    ref
                        .read(appThemePreferenceProvider.notifier)
                        .select(selection.first),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.visibility_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kontraste, Statusfarben, Wappen und Bedienelemente bleiben in beiden Modi vollständig erkennbar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
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
          final biometric = _SettingsCard(
            title: 'Biometrischer Login',
            subtitle:
                'Mit Fingerabdruck oder Gesichtserkennung sicher anmelden.',
            icon: Icons.fingerprint,
            child: _buildBiometricSettings(),
          );
          final spielPlus = _user.isTrainer
              ? SpielPlusSettingsCard(
                  userId: _user.id,
                  onOpen: () => context.go('/spielplus-browser'),
                )
              : null;
          if (constraints.maxWidth >= 820) {
            return Column(
              children: [
                appearance,
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: profile),
                    const SizedBox(width: 18),
                    Expanded(child: password),
                  ],
                ),
                const SizedBox(height: 18),
                biometric,
                if (spielPlus != null) ...[
                  const SizedBox(height: 18),
                  spielPlus,
                ],
              ],
            );
          }
          return Column(
            children: [
              appearance,
              const SizedBox(height: 16),
              profile,
              const SizedBox(height: 16),
              password,
              const SizedBox(height: 16),
              biometric,
              if (spielPlus != null) ...[
                const SizedBox(height: 16),
                spielPlus,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildBiometricSettings() {
    final settings = _biometricSettings;
    if (settings == null) {
      return const _BiometricHint(
        icon: Icons.manage_search_rounded,
        text: 'Biometrische Gerätefunktionen werden geprüft …',
      );
    }
    if (settings.capability == BiometricCapability.unsupported) {
      return const _BiometricHint(
        icon: Icons.phone_android_rounded,
        text:
            'Diese Funktion steht in der Android-App und auf unterstützten iPhones zur Verfügung.',
      );
    }
    if (settings.capability == BiometricCapability.notEnrolled) {
      return const _BiometricHint(
        icon: Icons.fingerprint,
        text:
            'Richte zuerst in den Geräteeinstellungen einen Fingerabdruck oder die Gesichtserkennung ein.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('biometric-login-switch'),
          contentPadding: EdgeInsets.zero,
          value: settings.enabled,
          onChanged: _savingBiometric ? null : _setBiometricLogin,
          title: Text(
            settings.enabled
                ? 'Biometrischer Login aktiviert'
                : 'Biometrischen Login aktivieren',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Dein Passwort wird nicht gespeichert. Die Bestätigung erfolgt ausschließlich durch das Gerät.',
          ),
          secondary: _savingBiometric
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  settings.enabled
                      ? Icons.verified_user_rounded
                      : Icons.security_rounded,
                  color: settings.enabled ? AppColors.teal : AppColors.gold,
                ),
        ),
        if (settings.enabled)
          const _BiometricHint(
            icon: Icons.shield_outlined,
            text:
                'Eine gemerkte Sitzung öffnet die App weiterhin automatisch. Biometrie wird erst angeboten, wenn keine gültige Sitzung mehr vorhanden ist. Passwortänderung, „Überall abmelden“ oder das Ausschalten hier widerrufen die Gerätefreigabe.',
          ),
      ],
    );
  }
}

class _BiometricHint extends StatelessWidget {
  const _BiometricHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.yellowSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
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
