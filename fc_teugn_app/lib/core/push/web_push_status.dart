enum WebPushPermission {
  prompt,
  granted,
  denied,
  unavailable,
}

class WebPushStatus {
  const WebPushStatus({
    required this.supported,
    required this.subscribed,
    required this.isIos,
    required this.isStandalone,
    required this.permission,
  });

  const WebPushStatus.unavailable()
      : supported = false,
        subscribed = false,
        isIos = false,
        isStandalone = false,
        permission = WebPushPermission.unavailable;

  final bool supported;
  final bool subscribed;
  final bool isIos;
  final bool isStandalone;
  final WebPushPermission permission;

  bool get requiresHomeScreen => isIos && !isStandalone;

  bool get canSubscribe =>
      supported &&
      !requiresHomeScreen &&
      permission != WebPushPermission.denied;

  factory WebPushStatus.fromJson(Map<String, dynamic> json) => WebPushStatus(
        supported: json['supported'] as bool? ?? false,
        subscribed: json['subscribed'] as bool? ?? false,
        isIos: json['isIos'] as bool? ?? false,
        isStandalone: json['isStandalone'] as bool? ?? false,
        permission: switch (json['permission']) {
          'granted' => WebPushPermission.granted,
          'denied' => WebPushPermission.denied,
          'default' => WebPushPermission.prompt,
          _ => WebPushPermission.unavailable,
        },
      );
}
