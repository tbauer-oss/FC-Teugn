import 'dart:io';

import 'package:fc_teugn_app/core/biometric_auth/biometric_auth_contract.dart';
import 'package:fc_teugn_app/core/biometric_auth/biometric_auth_stub.dart'
    as stub;
import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String relativePath) => File(relativePath).readAsStringSync();

  test('remembered session is restored before biometric fallback is offered',
      () {
    final auth = source('lib/features/auth/auth_controller.dart');
    final restore = auth.substring(
      auth.indexOf('Future<void> _restore()'),
      auth.indexOf('Future<void> retryStoredSession()'),
    );

    final refresh = restore.indexOf('await refreshAccessToken()');
    final successfulSession =
        restore.indexOf('if (token != null || !mounted) return;');
    final biometricFallback =
        restore.indexOf('if (await _prepareBiometricLogin()) return;');
    expect(refresh, greaterThanOrEqualTo(0));
    expect(successfulSession, greaterThan(refresh));
    expect(biometricFallback, greaterThan(successfulSession));
  });

  test('normal logout preserves biometric login as an explicit fallback', () {
    final auth = source('lib/features/auth/auth_controller.dart');
    final logout = auth.substring(
      auth.indexOf('Future<void> logout() async'),
      auth.indexOf('Future<String> updateOwnProfile'),
    );

    expect(logout, isNot(contains('_disableBiometricLoginOnServer')));
    expect(logout, isNot(contains('_clearBiometricPreference')));
    expect(logout, contains('_prepareBiometricLogin'));
  });

  test('biometric confirmation never stores the account password', () {
    final auth = source('lib/features/auth/auth_controller.dart');
    final native = source('lib/core/biometric_auth/biometric_auth_io.dart');

    expect(native, contains('biometricOnly: true'));
    expect(native, contains('persistAcrossBackgrounding: true'));
    expect(auth, contains("'/auth/biometric/enroll'"));
    expect(auth, contains("'/auth/biometric/login'"));
    expect(auth, contains('_biometricCredentialKey'));
    expect(
      RegExp(r'_storage\.write\([^;]*password', caseSensitive: false)
          .hasMatch(auth),
      isFalse,
    );
  });

  test('login and account views expose the optional biometric controls', () {
    final login = source('lib/features/auth/login_page.dart');
    final account = source('lib/features/auth/account_settings_page.dart');

    expect(login, contains("ValueKey('biometric-login')"));
    expect(login, contains('Mit Biometrie anmelden'));
    expect(account, contains("ValueKey('biometric-login-switch')"));
    expect(account, contains('Dein Passwort wird nicht gespeichert'));
  });

  test('Android and iOS contain the required native configuration', () {
    final manifest = source('android/app/src/main/AndroidManifest.xml');
    final activity = source(
      'android/app/src/main/kotlin/de/fcteugn/jugend/MainActivity.kt',
    );
    final styles = source('android/app/src/main/res/values/styles.xml');
    final info = source('ios/Runner/Info.plist');

    expect(manifest, contains('android.permission.USE_BIOMETRIC'));
    expect(activity, contains('FlutterFragmentActivity'));
    expect(styles, contains('Theme.AppCompat'));
    expect(info, contains('NSFaceIDUsageDescription'));
  });

  test('unsupported platforms have a safe non-biometric fallback', () async {
    final authenticator = stub.createBiometricAuthenticator();
    expect(
      await authenticator.capability(),
      BiometricCapability.unsupported,
    );
    expect(
      await authenticator.authenticate(reason: 'Test'),
      BiometricAuthenticationResult.unavailable,
    );
  });
}
