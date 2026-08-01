import 'dart:async';

final nativePushService = NativePushService();

class NativePushService {
  bool get supported => false;

  Stream<String> get actions => const Stream.empty();

  Stream<String> get tokenRefreshes => const Stream.empty();

  Future<void> initialize() async {}

  Future<bool> shouldAutomaticallyRegister({required bool accountOptIn}) async {
    return false;
  }

  Future<bool> shouldShowInitialPrompt() async => false;

  Future<void> markInitialPromptHandled() async {}

  Future<String?> enable() async => null;

  Future<String?> currentTokenIfEnabled() async => null;

  Future<void> disable({bool forgetPreference = true}) async {}

  String? takePendingAction() => null;
}
