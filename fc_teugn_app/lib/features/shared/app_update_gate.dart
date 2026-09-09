import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_update/app_update_service.dart';
import 'app_update_dialog.dart';

/// Checks Android updates before constructing authentication or API providers.
/// An installer launch is not evidence that the new version was installed.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child, this.client});

  final Widget child;
  final AppUpdateClient? client;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  AppUpdateClient get _client => widget.client ?? appUpdateService;
  AppUpdateManifest? _required;
  bool _started = false;
  bool _checking = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_client.supported) {
      unawaited(_check());
    } else {
      _started = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _client.supported) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _failed = false;
    });
    try {
      final update = await _client.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _required = update?.mandatory == true ? update : null;
        if (_required == null) _started = true;
      });
    } catch (_) {
      // A failed recheck must never release a previously required update.
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = !_started || _required != null;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        if (_started) Offstage(offstage: blocked, child: widget.child),
        if (blocked)
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: PopScope(
              canPop: false,
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: _required != null
                        ? AppUpdateDialog(
                            key: ValueKey(_required!.versionCode),
                            manifest: _required!,
                            client: _client,
                          )
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_checking)
                                  const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  _failed
                                      ? 'Die Updatesuche ist gerade nicht erreichbar. '
                                          'Bitte prüfe die Internetverbindung.'
                                      : 'App-Version wird geprüft …',
                                  textAlign: TextAlign.center,
                                ),
                                if (!_checking)
                                  TextButton(
                                    onPressed: _check,
                                    child: const Text('Erneut prüfen'),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
