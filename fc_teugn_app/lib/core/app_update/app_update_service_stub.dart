import 'app_update_client.dart';
import 'app_update_manifest.dart';

AppUpdateClient createAppUpdateService() => const _UnsupportedUpdateClient();

class _UnsupportedUpdateClient implements AppUpdateClient {
  const _UnsupportedUpdateClient();

  @override
  bool get supported => false;

  @override
  Future<AppUpdateManifest?> checkForUpdate() async => null;

  @override
  Future<AppUpdateInstallResult> downloadAndInstall(
    AppUpdateManifest manifest, {
    required AppUpdateProgress onProgress,
  }) async =>
      AppUpdateInstallResult.unsupported;
}
