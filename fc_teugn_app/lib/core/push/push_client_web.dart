import 'dart:convert';
import 'dart:js_interop';

@JS('fcTeugnSubscribePush')
external JSPromise<JSString> _subscribe(JSString vapidPublicKey);

Future<Map<String, dynamic>> subscribeToWebPush(
  String vapidPublicKey,
) async {
  final raw = (await _subscribe(vapidPublicKey.toJS).toDart).toDart;
  return jsonDecode(raw) as Map<String, dynamic>;
}

bool get webPushSupported => true;
