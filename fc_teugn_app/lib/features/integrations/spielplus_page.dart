import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/spielplus_credentials.dart';

final spielPlusPortalUri = Uri.parse(
  'https://spielplus.bfv.de/spielplus/oauth/login',
);

final spielPlusLoginUri = spielPlusPortalUri;

bool isAllowedSpielPlusUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'bfv.de' ||
      host.endsWith('.bfv.de') ||
      host == 'dfbnet.org' ||
      host.endsWith('.dfbnet.org');
}

String buildSpielPlusCredentialScript(
  SpielPlusCredentials credentials, {
  bool? submitAutomatically,
}) {
  final username = jsonEncode(credentials.username.trim());
  final password = jsonEncode(credentials.password);
  final submit = submitAutomatically ??
      (credentials.automaticLogin && credentials.isComplete);
  return '''
(() => {
  const firstUsable = (selectors) => {
    for (const selector of selectors) {
      const fields = Array.from(document.querySelectorAll(selector));
      const visible = fields.find((field) =>
        !field.disabled && field.getAttribute('aria-hidden') !== 'true');
      if (visible) return visible;
    }
    return null;
  };
  const username = firstUsable([
    '#username',
    'input[name="username"]',
    'input[name="user"]',
    'input[autocomplete="username"]',
    'input[type="email"]',
  ]);
  const password = firstUsable([
    '#password',
    'input[name="password"]',
    'input[autocomplete="current-password"]',
    'input[type="password"]',
  ]);
  if (!username || !password) return 'login-form-not-found';
  const applyValue = (field, value) => {
    field.focus();
    const prototype = Object.getPrototypeOf(field);
    const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
    if (descriptor && descriptor.set) {
      descriptor.set.call(field, value);
    } else {
      field.value = value;
    }
    field.dispatchEvent(new Event('input', { bubbles: true }));
    field.dispatchEvent(new Event('change', { bubbles: true }));
    field.dispatchEvent(new Event('blur', { bubbles: true }));
  };
  applyValue(username, $username);
  applyValue(password, $password);
  if (${submit ? 'true' : 'false'}) {
    const form = password.form || username.form ||
      document.querySelector('#kc-form-login') || document.querySelector('form');
    if (form) {
      if (form.requestSubmit) {
        form.requestSubmit();
      } else {
        form.submit();
      }
      return 'credentials-submitted';
    }
    const submitButton = firstUsable([
      '#kc-login',
      'button[type="submit"]',
      'input[type="submit"]',
    ]);
    if (submitButton) {
      submitButton.click();
      return 'credentials-submitted';
    }
    return 'credentials-filled-no-submit';
  }
  return 'credentials-filled';
})()
''';
}

class SpielPlusBrowserPage extends StatefulWidget {
  const SpielPlusBrowserPage({
    super.key,
    required this.userId,
    this.store,
  });

  final String userId;
  final SpielPlusCredentialsStore? store;

  @override
  State<SpielPlusBrowserPage> createState() => _SpielPlusBrowserPageState();
}

class _SpielPlusBrowserPageState extends State<SpielPlusBrowserPage> {
  late final SpielPlusCredentialsStore _store;
  WebViewController? _controller;
  SpielPlusCredentials _credentials = const SpielPlusCredentials();
  bool _loading = !kIsWeb;
  bool _automaticLoginAttempted = false;
  String? _filledLoginUrl;
  int _pageGeneration = 0;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SpielPlusCredentialsStore(userId: widget.userId);
    if (!kIsWeb) unawaited(_configureAndLoad());
  }

  Future<void> _configureAndLoad() async {
    try {
      try {
        _credentials = await _store.load();
      } catch (_) {
        // Ein nicht verfügbarer Gerätespeicher darf den offiziellen Zugang
        // nicht blockieren. SpielPLUS bleibt dann regulär manuell nutzbar.
        _credentials = const SpielPlusCredentials();
      }
      final controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            return target != null && isAllowedSpielPlusUri(target)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              _loading = progress < 100;
            });
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _pageGeneration += 1;
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (url) async {
            final generation = _pageGeneration;
            await _fillLoginIfPossible(url, generation);
            if (!mounted) return;
            setState(() {
              _loading = false;
              _progress = 100;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false || !mounted) return;
            setState(() {
              _loading = false;
              _error = 'SpielPLUS konnte nicht geladen werden.';
            });
          },
        ),
      );
      await controller.loadRequest(spielPlusLoginUri);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'SpielPLUS konnte nicht geladen werden.';
      });
    }
  }

  Future<void> _openPortalStart() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _automaticLoginAttempted = false;
      _filledLoginUrl = null;
      _loading = true;
      _progress = 0;
      _error = null;
    });
    await controller.loadRequest(spielPlusLoginUri);
  }

  Future<void> _fillLoginIfPossible(String url, int generation) async {
    final controller = _controller;
    final target = Uri.tryParse(url);
    if (controller == null ||
        target == null ||
        target.host.toLowerCase() != 'auth.dfbnet.org' ||
        !_credentials.isComplete) {
      return;
    }
    if (!_credentials.automaticLogin && _filledLoginUrl == url) {
      return;
    }

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 150),
      Duration(milliseconds: 300),
      Duration(milliseconds: 600),
      Duration(milliseconds: 1000),
      Duration(milliseconds: 1600),
    ];
    for (final delay in retryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!mounted || generation != _pageGeneration) return;
      final shouldSubmit =
          _credentials.automaticLogin && !_automaticLoginAttempted;
      try {
        final rawResult = await controller.runJavaScriptReturningResult(
          buildSpielPlusCredentialScript(
            _credentials,
            submitAutomatically: false,
          ),
        );
        final result = _normalizeJavaScriptResult(rawResult);
        if (result == 'credentials-filled') {
          _filledLoginUrl = url;
          if (shouldSubmit) {
            // Erst nach sicher erkanntem Formular als Anmeldeversuch markieren.
            // Dadurch werden dynamisch geladene Formulare zuverlässig gefunden,
            // fehlerhafte Zugangsdaten lösen aber keine Submit-Schleife aus.
            _automaticLoginAttempted = true;
            await controller.runJavaScript(
              buildSpielPlusCredentialScript(
                _credentials,
                submitAutomatically: true,
              ),
            );
          }
          return;
        }
      } catch (_) {
        // DFBnet bleibt manuell nutzbar, falls das Formular geändert wurde.
      }
    }
  }

  String _normalizeJavaScriptResult(Object value) {
    if (value is! String) return value.toString();
    try {
      final decoded = jsonDecode(value);
      return decoded is String ? decoded : value;
    } catch (_) {
      final quoted = value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")));
      return quoted ? value.substring(1, value.length - 1) : value;
    }
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _automaticLoginAttempted = false;
      _filledLoginUrl = null;
      _loading = true;
      _progress = 0;
      _error = null;
    });
    await controller.reload();
  }

  Future<void> _editCredentials() async {
    final changed = await showSpielPlusSettingsSheet(
      context,
      userId: widget.userId,
      store: _store,
    );
    if (changed != true || !mounted) return;
    try {
      _credentials = await _store.load();
    } catch (_) {
      _credentials = const SpielPlusCredentials();
    }
    _automaticLoginAttempted = false;
    _filledLoginUrl = null;
    await _controller?.loadRequest(spielPlusLoginUri);
  }

  Future<void> _handleSystemBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    _leave();
  }

  void _leave() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/trainer');
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(
        backgroundColor: context.appColors.surfaceMuted,
        appBar: AppBar(
          toolbarHeight: compact ? 48 : 52,
          automaticallyImplyLeading: false,
          leadingWidth: compact ? 44 : 48,
          leading: IconButton(
            tooltip: 'Zurück zur App',
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back_rounded),
            visualDensity: VisualDensity.compact,
          ),
          titleSpacing: 0,
          title: Text(
            'BfV SpielPLUS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          actions: [
            if (!kIsWeb)
              IconButton(
                key: const ValueKey('spielplus-home'),
                tooltip: 'SpielPLUS-Startseite',
                onPressed: _openPortalStart,
                icon: const Icon(Icons.home_outlined),
                visualDensity: VisualDensity.compact,
              ),
            if (!kIsWeb)
              IconButton(
                tooltip: 'SpielPLUS-Zugang verwalten',
                onPressed: _editCredentials,
                icon: const Icon(Icons.manage_accounts_outlined),
                visualDensity: VisualDensity.compact,
              ),
            if (!kIsWeb)
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                visualDensity: VisualDensity.compact,
              ),
            SizedBox(width: compact ? 2 : 4),
          ],
          bottom: _loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress / 100 : null,
                    minHeight: 3,
                    color: context.appWarning,
                    backgroundColor: context.appColors.brandSoft,
                  ),
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: kIsWeb
              ? const _SpielPlusWebFallback()
              : _error != null
                  ? _SpielPlusLoadError(message: _error!, onRetry: _reload)
                  : _controller == null
                      ? const Center(child: CircularProgressIndicator())
                      : WebViewWidget(controller: _controller!),
        ),
      ),
    );
  }
}

class SpielPlusSettingsCard extends StatelessWidget {
  const SpielPlusSettingsCard({
    super.key,
    required this.userId,
    required this.onOpen,
    this.store,
  });

  final String userId;
  final VoidCallback onOpen;
  final SpielPlusCredentialsStore? store;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('spielplus-settings-card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: context.appColors.brandSoft,
                  foregroundColor: context.appWarning,
                  child: const Icon(Icons.sports_soccer_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BfV SpielPLUS',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        'Optionaler Gerätezugang für Trainer und Verwaltung.',
                        style: TextStyle(color: context.appColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (kIsWeb) ...[
              const _SpielPlusWebNotice(),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (!kIsWeb)
                  OutlinedButton.icon(
                    key: const ValueKey('manage-spielplus-credentials'),
                    onPressed: () => showSpielPlusSettingsSheet(
                      context,
                      userId: userId,
                      store: store,
                    ),
                    icon: const Icon(Icons.phonelink_lock_rounded),
                    label: const Text('Zugang verwalten'),
                  ),
                FilledButton.icon(
                  key: const ValueKey('open-spielplus'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('SpielPLUS öffnen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showSpielPlusSettingsSheet(
  BuildContext context, {
  required String userId,
  SpielPlusCredentialsStore? store,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.appColors.surfaceMuted,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          4,
          18,
          18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SpielPLUS-Zugang',
                style: Theme.of(sheetContext).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Die Angaben gelten nur auf diesem Gerät und werden nicht an FC Teugn übertragen.',
              style: TextStyle(color: context.appColors.textMuted),
            ),
            const SizedBox(height: 16),
            _SpielPlusCredentialForm(
              userId: userId,
              store: store,
              onSaved: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SpielPlusCredentialForm extends StatefulWidget {
  const _SpielPlusCredentialForm({
    required this.userId,
    this.store,
    this.onSaved,
  });

  final String userId;
  final SpielPlusCredentialsStore? store;
  final VoidCallback? onSaved;

  @override
  State<_SpielPlusCredentialForm> createState() =>
      _SpielPlusCredentialFormState();
}

class _SpielPlusCredentialFormState extends State<_SpielPlusCredentialForm> {
  late final SpielPlusCredentialsStore _store;
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _automaticLogin = false;
  bool _obscurePassword = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SpielPlusCredentialsStore(userId: widget.userId);
    unawaited(_load());
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final credentials = await _store.load();
      if (!mounted) return;
      _username.text = credentials.username;
      _password.text = credentials.password;
      setState(() {
        _automaticLogin = credentials.automaticLogin;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await _store.save(
        SpielPlusCredentials(
          username: _username.text,
          password: _password.text,
          automaticLogin: _automaticLogin,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SpielPLUS-Zugang sicher gespeichert.')),
      );
      widget.onSaved?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Der SpielPLUS-Zugang konnte auf diesem Gerät nicht gespeichert werden.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    try {
      await _store.clear();
      if (!mounted) return;
      _username.clear();
      _password.clear();
      setState(() => _automaticLogin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SpielPLUS-Zugang wurde entfernt.')),
      );
      widget.onSaved?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Der gespeicherte Zugang konnte nicht entfernt werden.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('spielplus-username'),
            controller: _username,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'SpielPLUS-Kennung',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'SpielPLUS-Kennung eingeben'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('spielplus-password'),
            controller: _password,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'SpielPLUS-Passwort',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Passwort anzeigen'
                    : 'Passwort verbergen',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
            validator: (value) => value == null || value.isEmpty
                ? 'SpielPLUS-Passwort eingeben'
                : null,
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            key: const ValueKey('spielplus-auto-login'),
            contentPadding: EdgeInsets.zero,
            value: _automaticLogin,
            onChanged: (value) => setState(() => _automaticLogin = value),
            title: const Text(
              'Automatisch anmelden',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Beim Öffnen werden die Zugangsdaten eingesetzt und die Anmeldung direkt gestartet.',
            ),
          ),
          const _LocalCredentialNotice(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                key: const ValueKey('clear-spielplus-credentials'),
                onPressed: _saving ? null : _clear,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Zugang entfernen'),
              ),
              FilledButton.icon(
                key: const ValueKey('save-spielplus-credentials'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.security_rounded),
                label: Text(_saving ? 'Speichere …' : 'Sicher speichern'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocalCredentialNotice extends StatelessWidget {
  const _LocalCredentialNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: context.appColors.brandSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.phonelink_lock_rounded, color: context.appWarning),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Verschlüsselte Gerätespeicherung: Das Kennwort wird weder synchronisiert noch in der Vereinsdatenbank gespeichert. Bei einem gemeinsam genutzten Gerät den Zugang anschließend entfernen.',
              ),
            ),
          ],
        ),
      );
}

class _SpielPlusWebNotice extends StatelessWidget {
  const _SpielPlusWebNotice();

  @override
  Widget build(BuildContext context) => const _SpielPlusWebNoticeBody();
}

class _SpielPlusWebNoticeBody extends StatelessWidget {
  const _SpielPlusWebNoticeBody();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.appColors.brandSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: context.appWarning),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Auf der Web-App verhindert die Sicherheitsrichtlinie von DFBnet eine eingebettete Anmeldung. Nutze dort den Passwortmanager des Browsers. Der interne Browser mit Gerätezugang steht in der Android- und iPhone-App bereit.',
              ),
            ),
          ],
        ),
      );
}

class _SpielPlusWebFallback extends StatelessWidget {
  const _SpielPlusWebFallback();

  Future<void> _open() => launchUrl(
        spielPlusLoginUri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sports_soccer_rounded,
                        size: 52, color: context.appWarning),
                    const SizedBox(height: 12),
                    Text('SpielPLUS öffnen',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const _SpielPlusWebNoticeBody(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _open,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Offizielle SpielPLUS-Seite öffnen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _SpielPlusLoadError extends StatelessWidget {
  const _SpielPlusLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: context.appWarning),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      );
}
