enum BiometricCapability {
  available,
  notEnrolled,
  unsupported,
}

enum BiometricAuthenticationResult {
  authenticated,
  cancelled,
  unavailable,
  failed,
}

abstract interface class BiometricAuthenticator {
  Future<BiometricCapability> capability();

  Future<BiometricAuthenticationResult> authenticate({
    required String reason,
  });
}
