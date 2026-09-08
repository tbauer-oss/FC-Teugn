import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/pwa_install.dart';
import 'talents_widgets.dart';
import '../shared/app_update_check.dart';

class InstallationPage extends StatefulWidget {
  const InstallationPage({super.key, this.invitationToken});
  final String? invitationToken;
  @override
  State<InstallationPage> createState() => _InstallationPageState();
}

class _InstallationPageState extends State<InstallationPage> {
  late bool _ios = pwaIsIos || defaultTargetPlatform == TargetPlatform.iOS;
  String? _message;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('FC Teugn Talents installieren')),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppUpdateCheckButton(),
                            const SizedBox(height: 12),
                            Text('Deine Mannschaft. Direkt auf deinem Handy.',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 16),
                            Wrap(spacing: 8, children: [
                              ChoiceChip(
                                  label: const Text('iPhone / iPad'),
                                  selected: _ios,
                                  onSelected: (_) =>
                                      setState(() => _ios = true)),
                              ChoiceChip(
                                  label: const Text('Android'),
                                  selected: !_ios,
                                  onSelected: (_) =>
                                      setState(() => _ios = false))
                            ]),
                            const SizedBox(height: 16),
                            if (_ios)
                              TalentsCard(
                                  title:
                                      'In Safari zum Home-Bildschirm hinzufügen',
                                  children: [
                                    if (pwaRunningStandalone)
                                      const Text(
                                          'Du nutzt die App bereits vom Home-Bildschirm.'),
                                    const Text(
                                        '1. Öffne diese Seite in Safari.\n\n2. Tippe auf „Teilen“ und „Zum Home-Bildschirm“.\n\n3. Öffne FC Teugn Talents über das neue Symbol und melde dich an.\n\n4. Aktiviere Push-Nachrichten in der App, wenn du Erinnerungen erhalten möchtest.'),
                                    const SizedBox(height: 12),
                                    const Text(
                                        'App-Updates werden beim erneuten Öffnen geladen. Deine Daten bleiben mit deinem Konto verknüpft.'),
                                  ])
                            else
                              TalentsCard(
                                  title: 'Android-App installieren',
                                  children: [
                                    const Text(
                                        '1. Lade die aktuelle Android-App aus dem Vereinsdownload.\n\n2. Öffne die APK-Datei. Falls Android nachfragt, erlaube diesem Browser die Installation.\n\n3. Öffne FC Teugn Talents und melde dich an. Neue Versionen werden dir in der App mit Versionshinweisen angeboten.'),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                        icon: const Icon(Icons.download),
                                        label: const Text(
                                            'Aktuellen Vereinsdownload öffnen'),
                                        onPressed: () async {
                                          final opened = await launchUrl(
                                              Uri.parse(
                                                  'https://magentacloud.de/s/xkgHEESdKbQ6XMP'),
                                              mode: LaunchMode
                                                  .externalApplication);
                                          if (!opened && mounted) {
                                            setState(() => _message =
                                                'Der Download konnte nicht geöffnet werden. Bitte erneut versuchen.');
                                          }
                                        }),
                                    if (kIsWeb && pwaInstallSupported)
                                      OutlinedButton(
                                          onPressed: () async {
                                            final ok =
                                                await requestPwaInstall();
                                            if (mounted) {
                                              setState(() => _message = ok
                                                  ? 'Installation angefordert.'
                                                  : 'Nutze im Browsermenü „App installieren“ oder versuche es erneut.');
                                            }
                                          },
                                          child: const Text(
                                              'Als Web-App installieren')),
                                  ]),
                            if (_message != null)
                              Semantics(
                                  liveRegion: true, child: Text(_message!)),
                            if (widget.invitationToken != null)
                              TalentsCard(
                                  title:
                                      'Deine Einladung bleibt der nächste Schritt',
                                  children: [
                                    const Text(
                                        'Öffne nach der Installation deinen Einladungslink erneut. Mit deinem bestehenden Konto kannst du eine weitere Mannschaft hinzufügen.'),
                                    TextButton(
                                        onPressed: () => context.go(
                                            '/join?token=${widget.invitationToken}'),
                                        child: const Text(
                                            'Zur Mannschaftseinladung')),
                                  ])
                            else
                              TextButton(
                                  onPressed: () => context.go('/login'),
                                  child: const Text('Zur Anmeldung')),
                          ]))))));
}
