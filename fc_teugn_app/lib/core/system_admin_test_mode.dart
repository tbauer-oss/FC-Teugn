import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/user.dart';

/// In-memory safety switch for the local system-administration test lab.
///
/// The mode deliberately is not persisted. Closing or restarting the app
/// always returns to production mode, which makes it impossible to overlook a
/// previously enabled test session on a shared device.
class SystemAdminTestModeController extends StateNotifier<bool> {
  SystemAdminTestModeController() : super(false);

  bool enableFor(AppUser? user) {
    if (!systemAdminCanUseTestMode(user)) return false;
    state = true;
    return true;
  }

  void disable() => state = false;
}

bool systemAdminCanUseTestMode(AppUser? user) =>
    user?.role == UserRole.superAdmin && user?.isReadOnlyPreview != true;

final systemAdminTestModeProvider =
    StateNotifierProvider<SystemAdminTestModeController, bool>(
  (ref) => SystemAdminTestModeController(),
);
