import 'app_update_client.dart';
import 'app_update_service_stub.dart'
    if (dart.library.io) 'app_update_service_io.dart' as implementation;

export 'app_update_client.dart';
export 'app_update_manifest.dart';

final AppUpdateClient appUpdateService =
    implementation.createAppUpdateService();
