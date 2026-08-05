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
    expect(manifest, contains('@drawable/ic_stat_fc_teugn'));
  });

  test('Android push uses the FC Teugn crest for every notification path', () {
    final icon = File(
      'android/app/src/main/res/drawable/ic_stat_fc_teugn.xml',
    );
    final activity = File(
      'android/app/src/main/kotlin/de/fcteugn/jugend/MainActivity.kt',
    ).readAsStringSync();

    expect(icon.existsSync(), isTrue);
    expect(icon.readAsStringSync(), contains('<vector'));
    expect(activity, contains('R.drawable.ic_stat_fc_teugn'));
    expect(activity, isNot(contains('R.drawable.ic_stat_notification')));
  });

  test('Android updater verifies and opens only app-owned APK files', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final paths = File(
      'android/app/src/main/res/xml/app_update_paths.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/de/fcteugn/jugend/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(manifest, contains(r'${applicationId}.fileprovider'));
    expect(paths, contains('path="app_updates/"'));
    expect(activity, contains('de.fcteugn.jugend/app_update'));
    expect(activity, contains('packageManager.canRequestPackageInstalls()'));
    expect(activity, contains('allowedDirectory.path + File.separator'));
  });

  test('release workflow publishes APK first and update manifest last', () {
    final workflow = File('../.github/workflows/ci.yml').readAsStringSync();
    final publisher = File(
      '../scripts/publish_magentacloud_release.sh',
    ).readAsStringSync();

    expect(workflow, contains('MAGENTACLOUD_WEBDAV_USERNAME'));
    expect(workflow, contains('MAGENTACLOUD_WEBDAV_PASSWORD'));
    expect(publisher, contains(r'upload "$apk_path" "$latest_name"'));
    expect(publisher, contains(r'upload "$manifest_path" "latest.json"'));
    expect(
      publisher.indexOf(r'upload "$apk_path" "$latest_name"'),
      lessThan(
        publisher.indexOf(r'upload "$manifest_path" "latest.json"'),
      ),
    );
  });
}
