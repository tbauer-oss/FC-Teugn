import 'app_update_manifest.dart';

typedef AppUpdateProgress = void Function(double? progress);

enum AppUpdateInstallResult {
  launched,
  permissionRequired,
  unsupported,
}

abstract interface class AppUpdateClient {
  bool get supported;

  Future<AppUpdateManifest?> checkForUpdate();

  Future<AppUpdateInstallResult> downloadAndInstall(
    AppUpdateManifest manifest, {
    required AppUpdateProgress onProgress,
  });
}
