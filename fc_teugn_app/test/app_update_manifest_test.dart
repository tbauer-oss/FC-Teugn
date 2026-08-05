import 'package:fc_teugn_app/core/app_update/app_update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> validManifest() => {
        'schemaVersion': 1,
        'versionName': '1.5.27',
        'versionCode': 46,
        'apkUrl': 'https://magentacloud.de/update.apk',
        'sha256': List.filled(64, 'a').join(),
        'fileSize': 75339080,
        'publishedAt': '2026-08-05T13:30:00Z',
        'mandatory': false,
        'releaseNotes': ['Update-Prüfung', '', 42, 'Sicherer Download'],
      };

  test('parses a signed Android release manifest', () {
    final manifest = AppUpdateManifest.fromJson(validManifest());

    expect(manifest.versionName, '1.5.27');
    expect(manifest.versionCode, 46);
    expect(manifest.apkUri.scheme, 'https');
    expect(manifest.releaseNotes, ['Update-Prüfung', 'Sicherer Download']);
    expect(manifest.isNewerThan(45), isTrue);
    expect(manifest.isNewerThan(46), isFalse);
  });

  test('rejects non-https download URLs', () {
    final json = validManifest()..['apkUrl'] = 'http://example.test/app.apk';

    expect(
      () => AppUpdateManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed release checksums', () {
    final json = validManifest()..['sha256'] = 'not-a-sha256';

    expect(
      () => AppUpdateManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
