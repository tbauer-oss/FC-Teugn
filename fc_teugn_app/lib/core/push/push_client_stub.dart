import 'web_push_status.dart';

Future<Map<String, dynamic>> subscribeToWebPush(String vapidPublicKey) {
  throw UnsupportedError('Web-Push ist auf diesem Gerät nicht verfügbar.');
}

Future<WebPushStatus> getWebPushStatus([String? vapidPublicKey]) async =>
    const WebPushStatus.unavailable();

Future<bool> shouldShowInitialWebPushPrompt() async => false;

void markInitialWebPushPromptHandled() {}

bool get webPushSupported => false;
