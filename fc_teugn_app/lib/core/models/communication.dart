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
  return values
          .where((item) => item.name.toLowerCase() == normalized)
          .firstOrNull ??
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
        teamNames:
            (json['targetTeams'] as List<dynamic>? ?? const []).map((item) {
          final team =
              (item as Map<String, dynamic>)['team'] as Map<String, dynamic>;
          return team['shortName'] as String? ??
              team['name'] as String? ??
              'Team';
        }).toList(),
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

class AdminPushTestResult {
  const AdminPushTestResult({
    required this.recipients,
    required this.subscriptions,
    required this.sent,
    required this.failed,
    required this.pending,
    required this.skipped,
    required this.webSubscriptions,
    required this.androidSubscriptions,
    required this.errors,
  });

  final int recipients;
  final int subscriptions;
  final int sent;
  final int failed;
  final int pending;
  final int skipped;
  final int webSubscriptions;
  final int androidSubscriptions;
  final Map<String, int> errors;

  bool get allSent => subscriptions > 0 && sent == subscriptions;

  factory AdminPushTestResult.fromJson(Map<String, dynamic> json) {
    final platforms = json['byPlatform'] as Map<String, dynamic>? ?? const {};
    final web = platforms['WEB'] as Map<String, dynamic>? ?? const {};
    final android = platforms['ANDROID'] as Map<String, dynamic>? ?? const {};
    final errorItems = json['errors'] as List<dynamic>? ?? const [];
    return AdminPushTestResult(
      recipients: (json['recipients'] as num?)?.toInt() ?? 0,
      subscriptions: (json['subscriptions'] as num?)?.toInt() ?? 0,
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      webSubscriptions: (web['total'] as num?)?.toInt() ?? 0,
      androidSubscriptions: (android['total'] as num?)?.toInt() ?? 0,
      errors: {
        for (final item in errorItems)
          if (item is Map<String, dynamic>)
            item['code'] as String: (item['count'] as num?)?.toInt() ?? 0,
      },
    );
  }
}

enum PushDeviceHealth { active, stale, disabled }

class AdminPushDevice {
  const AdminPushDevice({
    required this.id,
    required this.platform,
    required this.deviceName,
    required this.isActive,
    required this.health,
    required this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    required this.userStatus,
    required this.teamName,
    required this.deliveryCount,
    this.administrativelyDisabledAt,
    this.lastDeliveryStatus,
    this.lastDeliveryError,
    this.lastDeliveryAt,
  });

  final String id;
  final String platform;
  final String deviceName;
  final bool isActive;
  final PushDeviceHealth health;
  final DateTime lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? administrativelyDisabledAt;
  final String userId;
  final String userName;
  final String userEmail;
  final String userRole;
  final String userStatus;
  final String teamName;
  final int deliveryCount;
  final String? lastDeliveryStatus;
  final String? lastDeliveryError;
  final DateTime? lastDeliveryAt;

  bool get isAndroid => platform == 'ANDROID';
  bool get isStale => health == PushDeviceHealth.stale;
  bool get isAdministrativelyDisabled => administrativelyDisabledAt != null;

  String get roleLabel => switch (userRole) {
        'SUPER_ADMIN' => 'Systemadministration',
        'CLUB_ADMIN' => 'Vereinsadministration',
        'YOUTH_DIRECTOR' => 'Jugendleitung',
        'COACH' || 'TRAINER' => 'Trainerteam',
        'ASSISTANT_COACH' => 'Co-Trainerteam',
        'TEAM_MANAGER' => 'Teamorganisation',
        'TRAINER_ADMIN' => 'Trainer-Administration',
        'PLAYER' => 'Spieler',
        'READ_ONLY' => 'Lesender Zugriff',
        _ => 'Elternteil',
      };

  factory AdminPushDevice.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    final team = user['team'] as Map<String, dynamic>? ?? const {};
    final lastDelivery = json['lastDelivery'] as Map<String, dynamic>?;
    return AdminPushDevice(
      id: json['id'] as String,
      platform: json['platform'] as String? ?? 'WEB',
      deviceName: (json['deviceName'] as String?)?.trim().isNotEmpty == true
          ? json['deviceName'] as String
          : 'Unbenanntes Gerät',
      isActive: json['isActive'] as bool? ?? false,
      health: switch (json['health']) {
        'ACTIVE' => PushDeviceHealth.active,
        'STALE' => PushDeviceHealth.stale,
        _ => PushDeviceHealth.disabled,
      },
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      administrativelyDisabledAt: json['administrativelyDisabledAt'] == null
          ? null
          : DateTime.parse(json['administrativelyDisabledAt'] as String),
      userId: user['id'] as String? ?? '',
      userName: user['name'] as String? ?? 'Unbekanntes Mitglied',
      userEmail: user['email'] as String? ?? '',
      userRole: user['role'] as String? ?? 'PARENT',
      userStatus: user['status'] as String? ?? 'PENDING',
      teamName: team['name'] as String? ?? 'Nicht zugeordnet',
      deliveryCount: (json['deliveryCount'] as num?)?.toInt() ?? 0,
      lastDeliveryStatus: lastDelivery?['status'] as String?,
      lastDeliveryError: lastDelivery?['errorCode'] as String?,
      lastDeliveryAt: lastDelivery?['sentAt'] != null
          ? DateTime.parse(lastDelivery!['sentAt'] as String)
          : lastDelivery?['createdAt'] != null
              ? DateTime.parse(lastDelivery!['createdAt'] as String)
              : null,
    );
  }
}

enum PitchConflictRequestStatus {
  pending,
  approved,
  declined,
  callbackRequested,
  cancelled,
}

class PitchConflictCoach {
  const PitchConflictCoach({
    required this.id,
    required this.name,
    required this.role,
    this.phone,
    this.email,
  });

  final String id;
  final String name;
  final String role;
  final String? phone;
  final String? email;

  factory PitchConflictCoach.fromJson(Map<String, dynamic> json) =>
      PitchConflictCoach(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Haupttrainer',
        role: json['role'] as String? ?? 'COACH',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
      );
}

class PitchConflictPreview {
  const PitchConflictPreview({
    required this.kind,
    required this.requiresApproval,
    required this.trainingTeamId,
    required this.trainingTeamName,
    required this.ageGroupCode,
    required this.trainingScheduleValue,
    required this.weekday,
    required this.startLabel,
    required this.endLabel,
    required this.pitch,
    this.headCoach,
  });

  final String kind;
  final bool requiresApproval;
  final String trainingTeamId;
  final String trainingTeamName;
  final String ageGroupCode;
  final String trainingScheduleValue;
  final String weekday;
  final String startLabel;
  final String endLabel;
  final String pitch;
  final PitchConflictCoach? headCoach;

  factory PitchConflictPreview.fromJson(Map<String, dynamic> json) =>
      PitchConflictPreview(
        kind: json['kind'] as String? ?? 'TEAM',
        requiresApproval: json['requiresApproval'] as bool? ?? false,
        trainingTeamId: json['trainingTeamId'] as String,
        trainingTeamName: json['trainingTeamName'] as String? ?? 'Mannschaft',
        ageGroupCode: json['ageGroupCode'] as String? ?? '',
        trainingScheduleValue: json['trainingScheduleValue'] as String? ?? '',
        weekday: json['weekday'] as String? ?? '',
        startLabel: json['startLabel'] as String? ?? '',
        endLabel: json['endLabel'] as String? ?? '',
        pitch: json['pitch'] as String? ?? '',
        headCoach: json['headCoach'] == null
            ? null
            : PitchConflictCoach.fromJson(
                json['headCoach'] as Map<String, dynamic>,
              ),
      );
}

class PitchConflictRequestModel {
  const PitchConflictRequestModel({
    required this.id,
    required this.status,
    required this.direction,
    required this.canRespond,
    required this.pitch,
    required this.trainingScheduleValue,
    required this.eventTitle,
    required this.eventStartAt,
    required this.trainingTeamName,
    required this.requesterName,
    required this.recipientName,
    this.opponent,
    this.message,
    this.responseMessage,
    this.recipientPhone,
  });

  final String id;
  final PitchConflictRequestStatus status;
  final String direction;
  final bool canRespond;
  final String pitch;
  final String trainingScheduleValue;
  final String eventTitle;
  final DateTime eventStartAt;
  final String? opponent;
  final String trainingTeamName;
  final String requesterName;
  final String recipientName;
  final String? recipientPhone;
  final String? message;
  final String? responseMessage;

  factory PitchConflictRequestModel.fromJson(Map<String, dynamic> json) {
    final event = json['event'] as Map<String, dynamic>? ?? const {};
    final team = json['trainingTeam'] as Map<String, dynamic>? ?? const {};
    final requester = json['requester'] as Map<String, dynamic>? ?? const {};
    final recipient = json['recipient'] as Map<String, dynamic>? ?? const {};
    return PitchConflictRequestModel(
      id: json['id'] as String,
      status: _enum(
        PitchConflictRequestStatus.values,
        json['status'],
        PitchConflictRequestStatus.pending,
      ),
      direction: json['direction'] as String? ?? 'OUTGOING',
      canRespond: json['canRespond'] as bool? ?? false,
      pitch: json['pitch'] as String? ?? '',
      trainingScheduleValue: json['trainingScheduleValue'] as String? ?? '',
      eventTitle: event['title'] as String? ?? 'Spiel',
      eventStartAt: DateTime.parse(
        event['startAt'] as String? ?? DateTime.now().toIso8601String(),
      ).toLocal(),
      opponent: event['opponent'] as String?,
      trainingTeamName:
          team['shortName'] as String? ?? team['name'] as String? ?? 'Team',
      requesterName: requester['name'] as String? ?? 'Anfragende Person',
      recipientName: recipient['name'] as String? ?? 'Haupttrainer',
      recipientPhone: recipient['phone'] as String?,
      message: json['message'] as String?,
      responseMessage: json['responseMessage'] as String?,
    );
  }
}
