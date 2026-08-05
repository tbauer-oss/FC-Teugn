import 'package:flutter/material.dart';
import '../loading/loading_widgets.dart';

import '../app_theme.dart';

class InitialPushPromptDialog extends StatefulWidget {
  const InitialPushPromptDialog({
    super.key,
    this.onActivate,
  });

  final Future<void> Function()? onActivate;

  @override
  State<InitialPushPromptDialog> createState() =>
      _InitialPushPromptDialogState();
}

class _InitialPushPromptDialogState extends State<InitialPushPromptDialog> {
  bool _activating = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.yellow,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.notifications_active_rounded,
          color: AppColors.black,
          size: 32,
        ),
      ),
      title: const Text(
        'Pushnachrichten aktivieren?',
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bleibe bei wichtigen Vereinsinformationen auf dem Laufenden – auch wenn die App geschlossen ist.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          const _PushBenefit(
            icon: Icons.event_available_rounded,
            text: 'Termin- und Trainingsänderungen',
          ),
          const SizedBox(height: 10),
          const _PushBenefit(
            icon: Icons.sports_soccer_rounded,
            text: 'Kader, Spiele und wichtige Hinweise',
          ),
          const SizedBox(height: 10),
          const _PushBenefit(
            icon: Icons.forum_rounded,
            text: 'Nachrichten deiner Mannschaft',
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed:
              _activating ? null : () => Navigator.of(context).pop(false),
          child: const Text('Jetzt nicht'),
        ),
        FilledButton.icon(
          onPressed: _activating ? null : _activate,
          icon: _activating
              ? const LogoLoadingIndicator(
                  size: 22,
                  semanticsLabel: 'Benachrichtigungen werden aktiviert',
                )
              : const Icon(Icons.notifications_rounded),
          label: Text(_activating ? 'Aktiviere …' : 'Aktivieren'),
        ),
      ],
    );
  }

  Future<void> _activate() async {
    final activate = widget.onActivate;
    if (activate == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _activating = true;
      _error = null;
    });
    try {
      // Der Web-Aufruf erfolgt direkt im Tap-Handler. Das ist insbesondere
      // für die von iOS verlangte unmittelbare Nutzerinteraktion notwendig.
      await activate();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activating = false;
        _error = 'Die Gerätefreigabe war nicht möglich. Bitte prüfe die '
            'Benachrichtigungseinstellungen oder versuche es später erneut.';
      });
    }
  }
}

class _PushBenefit extends StatelessWidget {
  const _PushBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.gold),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
