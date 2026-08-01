import 'package:flutter/material.dart';

import '../app_theme.dart';

class InitialPushPromptDialog extends StatelessWidget {
  const InitialPushPromptDialog({super.key});

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
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bleibe bei wichtigen Vereinsinformationen auf dem Laufenden – auch wenn die App geschlossen ist.',
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 18),
          _PushBenefit(
            icon: Icons.event_available_rounded,
            text: 'Termin- und Trainingsänderungen',
          ),
          SizedBox(height: 10),
          _PushBenefit(
            icon: Icons.sports_soccer_rounded,
            text: 'Kader, Spiele und wichtige Hinweise',
          ),
          SizedBox(height: 10),
          _PushBenefit(
            icon: Icons.forum_rounded,
            text: 'Nachrichten deiner Mannschaft',
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Jetzt nicht'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.notifications_rounded),
          label: const Text('Aktivieren'),
        ),
      ],
    );
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
