import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/core/app_update/web_update_version.dart';

void main() {
  final release = <String, dynamic>{
    'version': '1.8.1',
    'build_number': '195',
  };

  test('update is offered only until the new bundle has loaded', () {
    expect(availableWebUpdate(release, installedBuild: 194), '1.8.1');
    expect(availableWebUpdate(release, installedBuild: 195), isNull);
    expect(availableWebUpdate(release, installedBuild: 195), isNull);
  });

  test('an older server release does not prompt a newer client to reload', () {
    expect(availableWebUpdate(release, installedBuild: 196), isNull);
  });

  test('a later build with the same version name still offers an update', () {
    expect(
        availableWebUpdate({...release, 'build_number': 196},
            installedBuild: 195),
        '1.8.1');
  });

  test('invalid responses are errors, not update prompts', () {
    for (final manifest in [
      null,
      <String, dynamic>{},
      {...release, 'build_number': 'invalid'},
      {...release, 'version': null},
    ]) {
      expect(() => availableWebUpdate(manifest, installedBuild: 194),
          throwsFormatException);
    }
  });
}
