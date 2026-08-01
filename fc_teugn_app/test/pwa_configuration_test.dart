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
    });

    test('iPhone-Metadaten und Installationsbrücke werden früh geladen', () {
      final index = File('web/index.html').readAsStringSync();

      expect(index, contains('apple-mobile-web-app-capable'));
      expect(index, contains('apple-mobile-web-app-title'));
      expect(index, contains('apple-touch-icon'));
      expect(index, contains('pwa_install.js'));
      expect(
        index.indexOf('pwa_install.js'),
        lessThan(index.indexOf('flutter_bootstrap.js')),
      );
    });

    test('Push verdrängt nicht den Offline-Service-Worker der PWA', () {
      final pushBridge = File('web/push_bridge.js').readAsStringSync();

      expect(pushBridge, contains("scope: '/fc-teugn-push/'"));
      expect(
        pushBridge,
        isNot(contains("register('/push-sw.js');")),
      );
    });
  });
}
