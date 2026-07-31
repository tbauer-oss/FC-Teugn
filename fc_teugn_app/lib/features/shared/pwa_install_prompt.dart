import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/pwa_install.dart';

bool get shouldOfferPwaInstall => pwaInstallSupported && !pwaRunningStandalone;

Future<void> showPwaInstallPrompt(BuildContext context) async {
  if (pwaRunningStandalone) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Die FC-Teugn-App ist bereits installiert.')),
    );
    return;
  }

  if (!pwaIsIos) {
    final installed = await requestPwaInstall();
    if (installed || !context.mounted) return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.install_mobile_rounded),
      title: Text(
        pwaIsIos ? 'Auf dem iPhone installieren' : 'Als App installieren',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pwaIsIos && !pwaIsIosSafari) ...[
              const _InstallHint(
                number: '1',
                icon: Icons.public_rounded,
                text: 'Diese Seite zuerst in Safari öffnen.',
              ),
              const SizedBox(height: 14),
            ],
            _InstallHint(
              number: pwaIsIos && !pwaIsIosSafari ? '2' : '1',
              icon:
                  pwaIsIos ? Icons.ios_share_rounded : Icons.more_vert_rounded,
              text: pwaIsIos
                  ? 'Unten in Safari auf „Teilen“ tippen.'
                  : 'Das Browsermenü öffnen.',
            ),
            const SizedBox(height: 14),
            _InstallHint(
              number: pwaIsIos && !pwaIsIosSafari ? '3' : '2',
              icon: Icons.add_box_outlined,
              text: pwaIsIos
                  ? '„Zum Home-Bildschirm“ auswählen.'
                  : '„App installieren“ oder „Zum Startbildschirm“ wählen.',
            ),
            const SizedBox(height: 14),
            _InstallHint(
              number: pwaIsIos && !pwaIsIosSafari ? '4' : '3',
              icon: Icons.check_circle_outline_rounded,
              text: pwaIsIos
                  ? 'Oben rechts mit „Hinzufügen“ bestätigen.'
                  : 'Die Installation bestätigen.',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.yellowSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Die Installation ist kostenlos. Danach startet FC Teugn über '
                'das Vereinswappen auf dem Home-Bildschirm im App-Modus.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Verstanden'),
        ),
      ],
    ),
  );
}

class PwaInstallButton extends StatelessWidget {
  const PwaInstallButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!shouldOfferPwaInstall) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => showPwaInstallPrompt(context),
      icon: const Icon(Icons.install_mobile_rounded),
      label: const Text('Kostenlos als App installieren'),
    );
  }
}

class _InstallHint extends StatelessWidget {
  const _InstallHint({
    required this.number,
    required this.icon,
    required this.text,
  });

  final String number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.yellow,
          foregroundColor: AppColors.black,
          child: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: AppColors.gold, size: 24),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
