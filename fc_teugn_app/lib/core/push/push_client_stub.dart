Future<Map<String, dynamic>> subscribeToWebPush(String vapidPublicKey) {
  throw UnsupportedError('Web-Push ist auf diesem Gerät nicht verfügbar.');
}

bool get webPushSupported => false;
