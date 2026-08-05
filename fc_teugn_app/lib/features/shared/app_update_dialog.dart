import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/app_update/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.manifest,
  });

  final AppUpdateManifest manifest;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  double? _progress;
  bool _working = false;
  bool _permissionWasRequested = false;
  String? _message;

  Future<void> _install() async {
    if (_working) return;
    setState(() {
      _working = true;
      _progress = null;
      _message = null;
    });
    try {
      final result = await appUpdateService.downloadAndInstall(
        widget.manifest,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      switch (result) {
        case AppUpdateInstallResult.launched:
          Navigator.of(context).pop();
          return;
        case AppUpdateInstallResult.permissionRequired:
          setState(() {
            _working = false;
            _permissionWasRequested = true;
            _message =
                'Android hat die Sicherheitseinstellung geöffnet. Erlaube dort '
                'Installationen für FC Teugn Talents, kehre zurück und tippe '
                'anschließend auf „Installation fortsetzen“.';
          });
          return;
        case AppUpdateInstallResult.unsupported:
          setState(() {
            _working = false;
            _message =
                'Die Android-Installation konnte nicht direkt geöffnet werden.';
          });
          return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _message =
            'Das Update konnte noch nicht vollständig geladen oder geprüft '
            'werden. Bitte prüfe die Internetverbindung und versuche es erneut.';
      });
    }
  }

  Future<void> _openDownload() async {
    final opened = await launchUrl(
      widget.manifest.apkUri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      setState(() => _message = 'Der Download konnte nicht geöffnet werden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;
    final percent = _progress == null ? null : (_progress! * 100).round();
    return PopScope(
      canPop: !manifest.mandatory && !_working,
      child: AlertDialog(
        icon: const Icon(
          Icons.system_update_alt_rounded,
          color: AppColors.gold,
          size: 34,
        ),
        title: const Text(
          'Neue App-Version verfügbar',
          textAlign: TextAlign.center,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${manifest.versionName} · Build ${manifest.versionCode}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (manifest.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ...manifest.releaseNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 7),
                            child: Icon(
                              Icons.circle,
                              size: 5,
                              color: AppColors.gold,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: Text(note)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_working) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    percent == null
                        ? 'Update wird sicher heruntergeladen …'
                        : 'Update wird sicher heruntergeladen … $percent %',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_message!),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!_working && !manifest.mandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Später'),
            ),
          if (!_working && _message != null)
            TextButton(
              onPressed: _openDownload,
              child: const Text('Im Browser laden'),
            ),
          FilledButton.icon(
            onPressed: _working ? null : _install,
            icon: _working
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              _working
                  ? 'Wird geladen'
                  : _permissionWasRequested
                      ? 'Installation fortsetzen'
                      : 'Jetzt aktualisieren',
            ),
          ),
        ],
      ),
    );
  }
}
