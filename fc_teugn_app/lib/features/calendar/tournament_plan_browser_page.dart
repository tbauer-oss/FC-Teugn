import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/models/event.dart';

Future<void> openTournamentPlanBrowser(
  BuildContext context, {
  required String url,
  required String tournamentName,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !isMeinTurnierplanUrl(url)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Der hinterlegte Turnierlink ist ungültig.'),
      ),
    );
    return;
  }
  // External pages need their own full-screen route. Keeping the app shell
  // around the WebView creates two competing scroll surfaces, especially on
  // mobile web and foldables.
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => TournamentPlanBrowserPage(
        uri: uri,
        tournamentName: tournamentName,
      ),
    ),
  );
}

class TournamentPlanBrowserPage extends StatefulWidget {
  const TournamentPlanBrowserPage({
    super.key,
    required this.uri,
    required this.tournamentName,
  });

  final Uri uri;
  final String tournamentName;

  @override
  State<TournamentPlanBrowserPage> createState() =>
      _TournamentPlanBrowserPageState();
}

class _TournamentPlanBrowserPageState extends State<TournamentPlanBrowserPage> {
  WebViewController? _controller;
  bool _contentApproved = false;
  bool _loading = false;
  int _progress = 0;
  String? _error;

  bool _allowed(Uri uri) =>
      isMeinTurnierplanUrl(uri.toString()) ||
      (uri.scheme == 'https' &&
          (uri.host == 'www.meinturnierplan.de' ||
              uri.host.endsWith('.meinturnierplan.de')));

  Future<void> _load() async {
    if (!_allowed(widget.uri)) {
      setState(() => _error = 'Der Turnierlink ist ungültig.');
      return;
    }
    setState(() {
      _contentApproved = true;
      _loading = true;
      _progress = 0;
      _error = null;
    });
    final controller = WebViewController();
    _controller = controller;
    try {
      if (!kIsWeb) {
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final target = Uri.tryParse(request.url);
              return target != null && _allowed(target)
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
            onPageFinished: (_) {
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
                _error = 'Der Live-Turnierplan konnte nicht geladen werden.';
              });
            },
          ),
        );
      }
      await controller.loadRequest(widget.uri);
      if (kIsWeb && mounted) {
        setState(() {
          _loading = false;
          _progress = 100;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Der Live-Turnierplan konnte nicht geladen werden.';
      });
    }
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) {
      await _load();
      return;
    }
    setState(() {
      _loading = true;
      _progress = 0;
      _error = null;
    });
    if (kIsWeb) {
      await controller.loadRequest(widget.uri);
    } else {
      await controller.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: compact ? 48 : 52,
        automaticallyImplyLeading: false,
        leadingWidth: compact ? 44 : 48,
        leading: IconButton(
          tooltip: 'Zurück',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          visualDensity: VisualDensity.compact,
        ),
        titleSpacing: 0,
        title: Text(
          'Turnierplan · ${widget.tournamentName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        actions: [
          if (_contentApproved)
            IconButton(
              tooltip: 'Neu laden',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              visualDensity: VisualDensity.compact,
            ),
          if (compact) const SizedBox(width: 2),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress / 100 : null,
                  minHeight: 3,
                  color: AppColors.gold,
                  backgroundColor: AppColors.yellowSoft,
                ),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: !_contentApproved
            ? _TournamentPrivacyNotice(onLoad: _load)
            : _error != null
                ? _TournamentLoadError(message: _error!, onRetry: _reload)
                : WebViewWidget(controller: _controller!),
      ),
    );
  }
}

class _TournamentPrivacyNotice extends StatelessWidget {
  const _TournamentPrivacyNotice({required this.onLoad});

  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        size: 54, color: AppColors.gold),
                    const SizedBox(height: 16),
                    Text('Turnierplan live öffnen',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    const Text(
                      'Die Inhalte werden direkt von MeinTurnierplan geladen. '
                      'Dabei wird eine Verbindung zu www.meinturnierplan.de '
                      'hergestellt und dort können technisch erforderliche '
                      'Verbindungsdaten verarbeitet werden. FC Teugn übernimmt '
                      'keine externen Tracking-Inhalte in die Vereinsdatenbank.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onLoad,
                      icon: const Icon(Icons.open_in_browser_rounded),
                      label: const Text('Live-Turnierplan laden'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Zurück'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _TournamentLoadError extends StatelessWidget {
  const _TournamentLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 48, color: AppColors.gold),
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
