import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/loading/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_identity.dart';
import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../shared/pwa_install_prompt.dart';
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
  bool _showPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return Row(
            children: [
              if (wide)
                Expanded(
                  flex: 5,
                  child: Container(
                    height: double.infinity,
                    padding: const EdgeInsets.all(54),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.black, Color(0xFF373100)],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _LoginBrand(logoSize: 92),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'TEAM · TERMINE · GEMEINSCHAFT',
                              style: TextStyle(
                                color: AppColors.yellow,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Dein Team.\nDein Verein.\nDeine App.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              height: 1.04,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.8,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Alles, was Trainer und Eltern für einen gut organisierten Jugendfußball brauchen.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .7),
                              fontSize: 17,
                              height: 1.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            AppIdentity.name,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .45)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                flex: 6,
                child: ColoredBox(
                  color: context.appColors.surface,
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(
                          constraints.maxWidth < 360 ? 16 : 28,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!wide) ...[
                                    const _LoginBrand(dark: true, logoSize: 82),
                                    const SizedBox(height: 42),
                                  ],
                                  Text('Willkommen zurück',
                                      style: Theme.of(context)
                                          .textTheme
                                          .displaySmall),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Melde dich an, um dein Team zu organisieren.'),
                                  const SizedBox(height: 30),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    decoration: const InputDecoration(
                                      labelText: 'E-Mail-Adresse',
                                      prefixIcon:
                                          Icon(Icons.mail_outline_rounded),
                                    ),
                                    validator: (value) {
                                      final email = value?.trim() ?? '';
                                      if (email.isEmpty ||
                                          !email.contains('@')) {
                                        return 'Bitte eine gültige E-Mail eingeben';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: !_showPassword,
                                    autofillHints: const [
                                      AutofillHints.password
                                    ],
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                      labelText: 'Passwort',
                                      prefixIcon: const Icon(
                                          Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        tooltip: _showPassword
                                            ? 'Passwort verbergen'
                                            : 'Passwort anzeigen',
                                        onPressed: () => setState(() =>
                                            _showPassword = !_showPassword),
                                        icon: Icon(_showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined),
                                      ),
                                    ),
                                    validator: (value) =>
                                        (value?.isEmpty ?? true)
                                            ? 'Bitte Passwort eingeben'
                                            : null,
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: authState.loading
                                          ? null
                                          : _showForgotPassword,
                                      icon: const Icon(Icons.key_rounded),
                                      label: const Text('Passwort vergessen?'),
                                    ),
                                  ),
                                  if (authState.error != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .errorContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.error_outline_rounded,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: Text(authState.error!)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed:
                                        authState.loading ? null : _submit,
                                    child: authState.loading
                                        ? const LogoLoadingIndicator(
                                            size: 24,
                                            semanticsLabel:
                                                'Anmeldung wird geprüft',
                                          )
                                        : const Text('Anmelden'),
                                  ),
                                  if (authState.biometricLoginAvailable) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        const Expanded(child: Divider()),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            'ODER',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: context
                                                      .appColors.textMuted,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        const Expanded(child: Divider()),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    OutlinedButton.icon(
                                      key: const ValueKey('biometric-login'),
                                      onPressed: authState.loading
                                          ? null
                                          : _biometricLogin,
                                      icon: const Icon(Icons.fingerprint),
                                      label: Text(
                                        authState.biometricAccountLabel == null
                                            ? 'Mit Biometrie anmelden'
                                            : 'Mit Biometrie anmelden\n${authState.biometricAccountLabel}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.lock_clock_outlined,
                                        size: 17,
                                        color: context.appColors.textMuted,
                                      ),
                                      const SizedBox(width: 7),
                                      Flexible(
                                        child: Text(
                                          'Du bleibst auf diesem Gerät automatisch angemeldet.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: context.appColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    'Noch nicht dabei?',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 14),
                                  OutlinedButton(
                                    onPressed: authState.loading
                                        ? null
                                        : () => context.go('/register'),
                                    child: const Text('Account registrieren'),
                                  ),
                                  const SizedBox(height: 12),
                                  const PwaInstallButton(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final signedIn = await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (signedIn) {
      TextInput.finishAutofillContext(shouldSave: true);
    }
  }

  Future<void> _biometricLogin() async {
    await ref.read(authProvider.notifier).unlockWithBiometrics();
  }

  Future<void> _showForgotPassword() async {
    final email = TextEditingController(text: _emailController.text.trim());
    final formKey = GlobalKey<FormState>();
    var sending = false;
    var sent = false;
    String? error;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            scrollable: true,
            icon: Icon(sent
                ? Icons.mark_email_read_rounded
                : Icons.lock_reset_rounded),
            title:
                Text(sent ? 'E-Mail-Postfach prüfen' : 'Passwort zurücksetzen'),
            content: sent
                ? const Text(
                    'Wenn unter dieser E-Mail-Adresse ein freigegebener Zugang besteht, wurde ein sicherer Link zum Zurücksetzen des Passworts versendet. Der Link ist 15 Minuten gültig und kann nur einmal verwendet werden.\n\nBitte prüfe auch deinen Spam- oder Junk-Ordner. Aus Sicherheitsgründen zeigen wir nicht an, ob unter der eingegebenen Adresse tatsächlich ein Konto vorhanden ist.',
                  )
                : Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gib die E-Mail-Adresse deines Zugangs ein. Wenn ein freigegebenes Konto vorhanden ist, senden wir dir einen sicheren Link zum Festlegen eines neuen Passworts.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'E-Mail-Adresse des Zugangs',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            return text.contains('@')
                                ? null
                                : 'Bitte eine gültige E-Mail eingeben';
                          },
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogContext),
                child: Text(sent ? 'Schließen' : 'Abbrechen'),
              ),
              if (!sent)
                FilledButton.icon(
                  onPressed: sending
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setDialogState(() {
                            sending = true;
                            error = null;
                          });
                          try {
                            await ref
                                .read(authProvider.notifier)
                                .requestPasswordReset(email.text.trim());
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              sending = false;
                              sent = true;
                            });
                          } catch (exception) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              sending = false;
                              error = exception
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Reset-Link per E-Mail senden'),
                ),
            ],
          ),
        ),
      );
    } finally {
      email.dispose();
    }
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({this.dark = false, this.logoSize = 82});
  final bool dark;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClubLogo(size: logoSize),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FC TEUGN',
                maxLines: 2,
                softWrap: true,
                style: TextStyle(
                  color: dark ? context.appColors.text : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
              Text(
                'TALENTS',
                maxLines: 2,
                softWrap: true,
                style: TextStyle(
                  color: dark ? context.appColors.textMuted : Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
