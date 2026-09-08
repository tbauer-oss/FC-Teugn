/// FCM on Apple platforms requires a registered APNs token first.
Future<String?> applePushRegistrationToken({
  required Future<String?> Function() readApnsToken,
  required Future<String?> Function() readFcmToken,
  Duration retryDelay = const Duration(milliseconds: 500),
  int attempts = 12,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final token = await readApnsToken();
    if (token != null && token.isNotEmpty) return readFcmToken();
    if (attempt + 1 < attempts) await Future<void>.delayed(retryDelay);
  }
  throw StateError('IOS_APNS_NOT_READY');
}
