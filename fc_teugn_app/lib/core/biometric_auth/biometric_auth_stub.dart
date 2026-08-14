import 'biometric_auth_contract.dart';

BiometricAuthenticator createBiometricAuthenticator() =>
    const _UnsupportedBiometricAuthenticator();

class _UnsupportedBiometricAuthenticator implements BiometricAuthenticator {
  const _UnsupportedBiometricAuthenticator();

  @override
  Future<BiometricCapability> capability() async =>
      BiometricCapability.unsupported;

  @override
  Future<BiometricAuthenticationResult> authenticate({
    required String reason,
  }) async =>
      BiometricAuthenticationResult.unavailable;
}
