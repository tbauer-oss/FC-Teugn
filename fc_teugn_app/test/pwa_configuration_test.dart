import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kostenlose installierbare Web-App', () {
    test('Manifest ist als eigenständige deutsche Vereins-App konfiguriert',
        () {
      final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;

      expect(manifest['name'], 'FC Teugn Talents');
      expect(manifest['short_name'], 'Talents');
      expect(
        manifest['description'],
        'FC Teugn Talents – Dein Team. Dein Verein. Deine App.',
      );
      expect(manifest['id'], '/');
      expect(manifest['start_url'], '/');
      expect(manifest['scope'], '/');
      expect(manifest['display'], 'standalone');
      expect(manifest['lang'], 'de-DE');
      expect(manifest['prefer_related_applications'], isFalse);
      expect(manifest['icons'], isNotEmpty);
      final icons = manifest['icons'] as List<dynamic>;
      expect(
        icons.where((entry) => entry['sizes'] == '1024x1024'),
        hasLength(2),
      );
      expect(
        icons.every((entry) => (entry['src'] as String).contains('fctt-2')),
        isTrue,
      );
    });

    test('iPhone-Metadaten und Installationsbrücke werden früh geladen', () {
      final index = File('web/index.html').readAsStringSync();

      expect(index, contains('apple-mobile-web-app-capable'));
      expect(index, contains('apple-mobile-web-app-title'));
      expect(index, contains('apple-touch-icon'));
      expect(index, contains('apple-touch-icon.png?v=fctt-2'));
      expect(index, contains('favicon-16.png?v=fctt-2'));
      expect(index, contains('favicon-32.png?v=fctt-2'));
      expect(index, contains('favicon-48.png?v=fctt-2'));
      expect(index, contains('favicon.png?v=fctt-2'));
      expect(index, contains('og.png?v=fctt-2'));
      expect(index, contains('pwa_install.js'));
      expect(
        index.indexOf('pwa_install.js'),
        lessThan(index.indexOf('flutter_bootstrap.js')),
      );
    });

    test('Push verdrängt nicht den Offline-Service-Worker der PWA', () {
      final pushBridge = File('web/push_bridge.js').readAsStringSync();

      expect(pushBridge, contains("pushScopePath = '/fc-teugn-push/'"));
      expect(pushBridge, contains('scope: pushScopePath'));
      expect(
        pushBridge,
        isNot(contains("register('/push-sw.js');")),
      );
    });

    test('Web-Push erkennt iOS-Installation und bestehenden Gerätestatus', () {
      final pushBridge = File('web/push_bridge.js').readAsStringSync();

      expect(pushBridge, contains('fcTeugnWebPushStatus'));
      expect(pushBridge, contains("matchMedia('(display-mode: standalone)')"));
      expect(pushBridge, contains('IOS_HOME_SCREEN_REQUIRED'));
      expect(pushBridge, contains('pushManager.getSubscription()'));
      expect(pushBridge, contains('usesVapidKey'));
      expect(pushBridge, contains('subscription.unsubscribe()'));
      expect(pushBridge, contains('keyMismatch'));
      expect(pushBridge, contains('fcTeugnShouldShowInitialPushPrompt'));
    });

    test('Push-Klick fokussiert eine offene App oder öffnet sie neu', () {
      final serviceWorker = File('web/push-sw.js').readAsStringSync();

      expect(serviceWorker, contains("clients.matchAll({ type: 'window'"));
      expect(serviceWorker, contains('client.navigate(url)'));
      expect(serviceWorker, contains('client.focus()'));
      expect(serviceWorker, contains('clients.openWindow(url)'));
      expect(serviceWorker, contains('/icons/Icon-192.png?v=fctt-2'));
    });
  });
}
