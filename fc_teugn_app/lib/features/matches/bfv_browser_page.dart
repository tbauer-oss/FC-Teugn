import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_theme.dart';

Uri? buildEmbeddedBfvUri({
  required String? widgetTeamId,
  required String teamName,
  String? teamUrl,
}) {
  final normalizedId = widgetTeamId?.trim() ?? '';
  if (normalizedId.isNotEmpty) {
    return Uri.https('fcteugnapp.vercel.app', '/bfv-widget.html', {
      'teamId': normalizedId,
      'teamName': teamName,
    });
  }

  final normalizedUrl = teamUrl?.trim() ?? '';
  final uri = Uri.tryParse(normalizedUrl);
  final host = uri?.host.toLowerCase() ?? '';
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      (host != 'bfv.de' && !host.endsWith('.bfv.de'))) {
    return null;
  }
  return uri;
}

class BfvBrowserPage extends StatefulWidget {
  const BfvBrowserPage({
    super.key,
    required this.initialUri,
    required this.teamName,
  });

  final Uri initialUri;
  final String teamName;

  @override
  State<BfvBrowserPage> createState() => _BfvBrowserPageState();
}

class _BfvBrowserPageState extends State<BfvBrowserPage> {
  late final WebViewController _controller;
  bool _loading = true;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_configureAndLoad());
  }

  Future<void> _configureAndLoad() async {
    try {
      if (!kIsWeb) {
        await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await _controller.setNavigationDelegate(
          NavigationDelegate(
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
                _loading = true;
                _error = null;
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
                _error = 'Die BfV-Ansicht konnte nicht geladen werden.';
              });
            },
          ),
        );
      }
      await _controller.loadRequest(widget.initialUri);
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
        _error = 'Die BfV-Ansicht konnte nicht geladen werden.';
      });
    }
  }

  Future<void> _reload() async {
    if (kIsWeb) {
      await _controller.loadRequest(widget.initialUri);
    } else {
      await _controller.reload();
    }
    if (!mounted) return;
    setState(() {
      _error = null;
      _loading = true;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Zurück zur App',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tabelle & Ergebnisse',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.teamName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Neu laden',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
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
          child: _error == null
              ? WebViewWidget(controller: _controller)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: AppColors.gold,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Erneut laden'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );
}
