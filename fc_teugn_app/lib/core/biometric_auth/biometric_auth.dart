import 'biometric_auth_contract.dart';
import 'biometric_auth_stub.dart' if (dart.library.io) 'biometric_auth_io.dart'
    as implementation;

export 'biometric_auth_contract.dart';

BiometricAuthenticator createBiometricAuthenticator() =>
    implementation.createBiometricAuthenticator();

final BiometricAuthenticator biometricAuthenticator =
    createBiometricAuthenticator();
