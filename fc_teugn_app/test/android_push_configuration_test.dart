import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase Android config belongs to the production app package', () {
    final config = jsonDecode(
      File('android/app/google-services.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final clients = config['client'] as List<dynamic>;
    final packages = clients.map((entry) {
      final client = entry as Map<String, dynamic>;
      final info = client['client_info'] as Map<String, dynamic>;
      final android = info['android_client_info'] as Map<String, dynamic>;
      return android['package_name'];
    });
    expect(packages, contains('de.fcteugn.jugend'));
  });

  test('Android manifest declares notification permission and channel', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('fc_teugn_important'));
    expect(manifest, contains('@drawable/ic_stat_notification'));
  });
}
