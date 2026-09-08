import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/app_update/app_update_service.dart';
import '../../core/app_update/update_check_coordinator.dart';
import '../../core/app_update/web_update.dart';
import 'app_update_dialog.dart';

final _nativeChecks =
    UpdateCheckCoordinator(check: appUpdateService.checkForUpdate);
final _webChecks = UpdateCheckCoordinator(check: checkWebUpdate);
bool _presentingUpdate = false;
int? _offeredBuild;
String? _offeredWebVersion;

Future<void> checkAppUpdates(BuildContext context,
    {bool manual = false, ValueChanged<String>? onFeedback}) async {
  if (_presentingUpdate) return;
  void feedback(String message) {
    if (manual && context.mounted) {
      if (onFeedback != null) {
        onFeedback(message);
      } else {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  try {
    if (kIsWeb) {
      final version = await _webChecks.run(manual: manual);
      if (!context.mounted || _presentingUpdate) return;
      if (version == null) {
        feedback('Deine Web-App ist aktuell.');
        return;
      }
      if (!manual && _offeredWebVersion == version) return;
      _offeredWebVersion = version;
      _presentingUpdate = true;
      try {
        final reload = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Neue Web-App verfügbar'),
                  content: Text(
                      'Version $version ist bereit. Speichere offene Eingaben vor dem Neuladen.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Später')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Jetzt neu laden')),
                  ],
                ));
        if (reload == true) reloadWebApp();
      } finally {
        _presentingUpdate = false;
      }
      return;
    }
    if (!appUpdateService.supported) {
      feedback(
          'Die direkte Updatesuche ist in der Android-App und Web-App verfügbar.');
      return;
    }
    final update = await _nativeChecks.run(manual: manual);
    if (!context.mounted || _presentingUpdate) return;
    if (update == null) {
      feedback('Deine App ist aktuell.');
      return;
    }
    if (!manual && !update.mandatory && _offeredBuild == update.versionCode) {
      return;
    }
    _offeredBuild = update.versionCode;
    _presentingUpdate = true;
    try {
      await showDialog<void>(
          context: context,
          barrierDismissible: !update.mandatory,
          builder: (_) => AppUpdateDialog(manifest: update));
    } finally {
      _presentingUpdate = false;
    }
  } catch (_) {
    feedback(
        'Updatesuche derzeit nicht möglich. Bitte Verbindung prüfen und erneut versuchen.');
  }
}

class AppUpdateCheckButton extends StatefulWidget {
  const AppUpdateCheckButton({super.key});
  @override
  State<AppUpdateCheckButton> createState() => _AppUpdateCheckButtonState();
}

class _AppUpdateCheckButtonState extends State<AppUpdateCheckButton> {
  bool _checking = false;
  String? _feedback;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
          onPressed: _checking
              ? null
              : () async {
                  setState(() {
                    _checking = true;
                    _feedback = null;
                  });
                  await checkAppUpdates(context, manual: true,
                      onFeedback: (value) {
                    if (mounted) setState(() => _feedback = value);
                  });
                  if (mounted) setState(() => _checking = false);
                },
          icon: _checking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.system_update_alt_rounded),
          label:
              Text(_checking ? 'Suche nach Updates …' : 'Nach Updates suchen'),
        ),
        if (_feedback != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(_feedback!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall))
      ]);
}
