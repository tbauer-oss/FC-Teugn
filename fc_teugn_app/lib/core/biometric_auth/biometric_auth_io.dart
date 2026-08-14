import 'dart:io';

import 'package:local_auth/local_auth.dart';

import 'biometric_auth_contract.dart';

BiometricAuthenticator createBiometricAuthenticator() =>
    _MobileBiometricAuthenticator();

class _MobileBiometricAuthenticator implements BiometricAuthenticator {
  final LocalAuthentication _localAuthentication = LocalAuthentication();

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  Future<BiometricCapability> capability() async {
    if (!_isSupportedPlatform) return BiometricCapability.unsupported;
    try {
      final supported = await _localAuthentication.isDeviceSupported();
      final canCheck = await _localAuthentication.canCheckBiometrics;
      if (!supported || !canCheck) return BiometricCapability.unsupported;
      final enrolled = await _localAuthentication.getAvailableBiometrics();
      return enrolled.isEmpty
          ? BiometricCapability.notEnrolled
          : BiometricCapability.available;
    } catch (_) {
      return BiometricCapability.unsupported;
    }
  }

  @override
  Future<BiometricAuthenticationResult> authenticate({
    required String reason,
  }) async {
    if (await capability() != BiometricCapability.available) {
      return BiometricAuthenticationResult.unavailable;
    }
    try {
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? BiometricAuthenticationResult.authenticated
          : BiometricAuthenticationResult.cancelled;
    } catch (_) {
      return BiometricAuthenticationResult.failed;
    }
  }
}
