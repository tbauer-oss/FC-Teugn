enum AnnouncementAudience { allMembers, parents, players, staff, individuals }

enum AnnouncementPriority { normal, important, urgent }

enum AnnouncementStatus { draft, scheduled, published, archived }

enum NotificationCategory {
  event,
  eventReminder,
  announcement,
  nomination,
  lineup,
  liveTicker,
  match,
  registration,
  urgent,
  system,
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final normalized = raw?.toString().toLowerCase().replaceAll('_', '');
  return values.where((item) => item.name.toLowerCase() == normalized).firstOrNull ??
      fallback;
}

String communicationApiEnum(Enum value) => value.name
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toUpperCase();

class AnnouncementModel {
  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.priority,
    required this.status,
    required this.authorName,
    required this.teamNames,
    required this.requireReadReceipt,
    required this.pushEnabled,
    required this.isRead,
    required this.attachments,
    this.publishAt,
    this.expiresAt,
    this.readCount,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final AnnouncementPriority priority;
  final AnnouncementStatus status;
  final String authorName;
  final List<String> teamNames;
  final bool requireReadReceipt;
  final bool pushEnabled;
  final bool isRead;
  final int? readCount;
  final DateTime? publishAt;
  final DateTime? expiresAt;
  final List<AnnouncementAttachmentModel> attachments;

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) =>
      AnnouncementModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Mitteilung',
        body: json['body'] as String? ?? '',
        audience: _enum(
          AnnouncementAudience.values,
          json['audience'],
          AnnouncementAudience.allMembers,
        ),
        priority: _enum(
          AnnouncementPriority.values,
          json['priority'],
          AnnouncementPriority.normal,
        ),
        status: _enum(
          AnnouncementStatus.values,
          json['status'],
          AnnouncementStatus.draft,
        ),
        authorName:
            (json['author'] as Map<String, dynamic>?)?['name'] as String? ??
                'Trainerteam',
        teamNames: (json['targetTeams'] as List<dynamic>? ?? const [])
            .map((item) {
              final team =
                  (item as Map<String, dynamic>)['team']
                      as Map<String, dynamic>;
              return team['shortName'] as String? ??
                  team['name'] as String? ??
                  'Team';
            })
            .toList(),
        requireReadReceipt: json['requireReadReceipt'] as bool? ?? false,
        pushEnabled: json['pushEnabled'] as bool? ?? false,
        isRead: json['isRead'] as bool? ?? false,
        readCount: json['readCount'] as int?,
        publishAt: json['publishAt'] == null
            ? null
            : DateTime.parse(json['publishAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .map(
              (item) => AnnouncementAttachmentModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class AnnouncementAttachmentModel {
  const AnnouncementAttachmentModel({
    required this.name,
    required this.url,
    this.mimeType,
  });
  final String name;
  final String url;
  final String? mimeType;

  factory AnnouncementAttachmentModel.fromJson(Map<String, dynamic> json) =>
      AnnouncementAttachmentModel(
        name: json['name'] as String? ?? 'Anhang',
        url: json['url'] as String? ?? '',
        mimeType: json['mimeType'] as String?,
      );
}

class AppNotificationModel {
  const AppNotificationModel({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.actionUrl,
  });
  final String id;
  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? actionUrl;

  factory AppNotificationModel.fromJson(Map<String, dynamic> json) =>
      AppNotificationModel(
        id: json['id'] as String,
        category: _enum(
          NotificationCategory.values,
          json['category'],
          NotificationCategory.system,
        ),
        title: json['title'] as String? ?? 'Benachrichtigung',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        isRead: json['readAt'] != null,
        actionUrl: json['actionUrl'] as String?,
      );
}

class NotificationPreferenceModel {
  const NotificationPreferenceModel({
    required this.category,
    required this.inApp,
    required this.push,
  });
  final NotificationCategory category;
  final bool inApp;
  final bool push;

  factory NotificationPreferenceModel.fromJson(Map<String, dynamic> json) =>
      NotificationPreferenceModel(
        category: _enum(
          NotificationCategory.values,
          json['category'],
          NotificationCategory.system,
        ),
        inApp: json['inApp'] as bool? ?? true,
        push: json['push'] as bool? ?? true,
      );
}

class PushConfiguration {
  const PushConfiguration({
    required this.webPushConfigured,
    required this.androidConfigured,
    this.vapidPublicKey,
  });
  final bool webPushConfigured;
  final bool androidConfigured;
  final String? vapidPublicKey;

  factory PushConfiguration.fromJson(Map<String, dynamic> json) =>
      PushConfiguration(
        webPushConfigured: json['webPushConfigured'] as bool? ?? false,
        androidConfigured: json['androidConfigured'] as bool? ?? false,
        vapidPublicKey: json['vapidPublicKey'] as String?,
      );
}
