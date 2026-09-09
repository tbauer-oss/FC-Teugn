import 'web_push_status.dart';

/// Reconcile a previously permitted device with the server after app startup.
/// A valid local subscription still needs uploading: a previous upload may
/// have failed, or the server may have lost or deactivated its registration.
Future<bool> restoreWebPushRegistration({
  required bool accountOptIn,
  required String vapidPublicKey,
  required Future<WebPushStatus> Function(String) readStatus,
  required Future<Map<String, dynamic>> Function(String) restoreSubscription,
  required Future<void> Function(Map<String, dynamic>) saveSubscription,
}) async {
  final status = await readStatus(vapidPublicKey);
  if (!status.canSubscribe ||
      status.permission != WebPushPermission.granted ||
      (!accountOptIn && !status.subscribed && !status.keyMismatch)) {
    return false;
  }
  final subscription = await restoreSubscription(vapidPublicKey);
  await saveSubscription(subscription);
  return true;
}
