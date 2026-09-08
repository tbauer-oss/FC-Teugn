import 'dart:async';
import 'dart:io';
import 'apple_push_token.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _notificationChannel = MethodChannel(
  'de.fcteugn.jugend/notifications',
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await Firebase.initializeApp();
}

final nativePushService = NativePushService();

class NativePushService {
  String get _enabledKey =>
      'fc_teugn_${Platform.isIOS ? 'ios' : 'android'}_push_enabled';
  String get _initialPromptHandledKey =>
      'fc_teugn_${Platform.isIOS ? 'ios' : 'android'}_push_initial_prompt_handled';
  static const _storage = FlutterSecureStorage();

  final _actions = StreamController<String>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _initialized = false;
  Future<void>? _initializing;
  String? _pendingAction;
  String? _lastAction;

  bool get supported => Platform.isAndroid || Platform.isIOS;
  String get platform => Platform.isIOS ? 'IOS' : 'ANDROID';

  Stream<String> get actions => _actions.stream;

  Stream<String> get tokenRefreshes => supported
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream.empty();

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    await (_initializing ??=
        _initialize().whenComplete(() => _initializing = null));
  }

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      if (Platform.isIOS) throw StateError('IOS_PUSH_NOT_CONFIGURED');
      rethrow;
    }
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);
    }
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    final initialAction = Platform.isAndroid
        ? await _notificationChannel
            .invokeMethod<String>('getInitialPushAction')
        : null;
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );
    if (Platform.isAndroid) {
      _notificationChannel.setMethodCallHandler((call) async {
        if (call.method == 'notificationOpened') {
          _emitAction(call.arguments as String?);
        }
      });
    }
    if (Platform.isAndroid) {
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen(_showForegroundNotification),
      );
    }
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteAction),
    );
    _handleRemoteAction(initialMessage);
    _emitAction(initialAction);
    _initialized = true;
  }

  Future<bool> shouldAutomaticallyRegister({required bool accountOptIn}) async {
    if (!supported) return false;
    try {
      final locallyEnabled = await _storage.read(key: _enabledKey) == 'true';
      if (locallyEnabled) return true;
      // An account-level opt-in is not enough to bypass the explicit decision
      // on this particular device.
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> shouldShowInitialPrompt() async {
    if (!supported) return false;
    try {
      if (await _storage.read(key: _initialPromptHandledKey) == 'true') {
        return false;
      }
      if (await _storage.read(key: _enabledKey) == 'true') {
        await _storage.write(key: _initialPromptHandledKey, value: 'true');
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> markInitialPromptHandled() async {
    if (!supported) return;
    try {
      await _storage.write(key: _initialPromptHandledKey, value: 'true');
    } catch (_) {}
  }

  Future<String?> enable() async {
    if (!supported) return null;
    await initialize();
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return null;
    }
    final token = await _registrationToken();
    if (token == null || token.trim().isEmpty) return null;
    try {
      await _storage.write(key: _enabledKey, value: 'true');
    } catch (_) {}
    return token;
  }

  Future<String?> currentTokenIfEnabled() async {
    if (!supported) return null;
    if (!await shouldAutomaticallyRegister(accountOptIn: false)) return null;
    await initialize();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return null;
    }
    return _registrationToken();
  }

  Future<String?> _registrationToken() async {
    if (Platform.isIOS) {
      // APNs registration can lag behind permission approval. FCM calls must
      // wait for it; an absent token is not a denial of notification permission.
      return applePushRegistrationToken(
        readApnsToken: FirebaseMessaging.instance.getAPNSToken,
        readFcmToken: FirebaseMessaging.instance.getToken,
      );
    }
    return FirebaseMessaging.instance.getToken();
  }

  Future<void> disable({bool forgetPreference = true}) async {
    if (!supported) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    if (forgetPreference) {
      try {
        await _storage.delete(key: _enabledKey);
      } catch (_) {}
    }
  }

  String? takePendingAction() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }

  void _handleRemoteAction(RemoteMessage? message) {
    _emitAction(message?.data['actionUrl'] as String?);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    // Die native Live-Match-Oberfläche verarbeitet diese Daten mit stabiler
    // ID als laufende Sperrbildschirm-/Statusanzeige.
    if (message.data['liveMatch']?.toString() == 'true') return;
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null || body == null) return;
    await _notificationChannel.invokeMethod<bool>('showNotification', {
      'title': title,
      'body': body,
      'actionUrl': message.data['actionUrl']?.toString(),
    });
  }

  void _emitAction(String? action) {
    final normalized = action?.trim();
    if (normalized == null || normalized.isEmpty || normalized == _lastAction) {
      return;
    }
    _lastAction = normalized;
    if (_actions.hasListener) {
      _actions.add(normalized);
    } else {
      _pendingAction = normalized;
    }
  }
}
