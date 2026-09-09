import 'web_push_status.dart';

Future<Map<String, dynamic>> subscribeToWebPush(String vapidPublicKey,
    {bool requestPermission = true}) {
  throw UnsupportedError('Web-Push ist auf diesem Gerät nicht verfügbar.');
}

Future<WebPushStatus> getWebPushStatus([String? vapidPublicKey]) async =>
    const WebPushStatus.unavailable();

Future<bool> shouldShowInitialWebPushPrompt([String? vapidPublicKey]) async =>
    false;

void markInitialWebPushPromptHandled([String? vapidPublicKey]) {}

bool get webPushSupported => false;
