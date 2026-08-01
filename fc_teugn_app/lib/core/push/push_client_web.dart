import 'dart:convert';
import 'dart:js_interop';

import 'web_push_status.dart';

@JS('fcTeugnSubscribePush')
external JSPromise<JSString> _subscribe(JSString vapidPublicKey);

@JS('fcTeugnWebPushStatus')
external JSPromise<JSString> _status();

@JS('fcTeugnShouldShowInitialPushPrompt')
external JSPromise<JSString> _shouldShowInitialPrompt();

@JS('fcTeugnMarkInitialPushPromptHandled')
external void _markInitialPromptHandled();

Future<Map<String, dynamic>> subscribeToWebPush(
  String vapidPublicKey,
) async {
  final raw = (await _subscribe(vapidPublicKey.toJS).toDart).toDart;
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<WebPushStatus> getWebPushStatus() async {
  try {
    final raw = (await _status().toDart).toDart;
    return WebPushStatus.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  } catch (_) {
    return const WebPushStatus.unavailable();
  }
}

Future<bool> shouldShowInitialWebPushPrompt() async {
  try {
    final raw = (await _shouldShowInitialPrompt().toDart).toDart;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    return value['show'] as bool? ?? false;
  } catch (_) {
    return false;
  }
}

void markInitialWebPushPromptHandled() => _markInitialPromptHandled();

bool get webPushSupported => true;
