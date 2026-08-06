enum SupportCategory {
  usage,
  display,
  account,
  push,
  sync,
  calendar,
  matchday,
  other,
}

enum SupportStatus { open, inProgress, question, resolved, closed }

extension SupportCategoryX on SupportCategory {
  String get apiName => switch (this) {
        SupportCategory.usage => 'USAGE',
        SupportCategory.display => 'DISPLAY',
        SupportCategory.account => 'ACCOUNT',
        SupportCategory.push => 'PUSH',
        SupportCategory.sync => 'SYNC',
        SupportCategory.calendar => 'CALENDAR',
        SupportCategory.matchday => 'MATCHDAY',
        SupportCategory.other => 'OTHER',
      };

  String get label => switch (this) {
        SupportCategory.usage => 'Bedienung',
        SupportCategory.display => 'Darstellung',
        SupportCategory.account => 'Konto & Anmeldung',
        SupportCategory.push => 'Pushnachrichten',
        SupportCategory.sync => 'Synchronisierung',
        SupportCategory.calendar => 'Kalender',
        SupportCategory.matchday => 'Spieltag & Liveticker',
        SupportCategory.other => 'Sonstiges',
      };
}

extension SupportStatusX on SupportStatus {
  String get apiName => switch (this) {
        SupportStatus.open => 'OPEN',
        SupportStatus.inProgress => 'IN_PROGRESS',
        SupportStatus.question => 'QUESTION',
        SupportStatus.resolved => 'RESOLVED',
        SupportStatus.closed => 'CLOSED',
      };

  String get label => switch (this) {
        SupportStatus.open => 'Offen',
        SupportStatus.inProgress => 'In Bearbeitung',
        SupportStatus.question => 'Rückfrage',
        SupportStatus.resolved => 'Gelöst',
        SupportStatus.closed => 'Geschlossen',
      };
}

class SupportMessageModel {
  const SupportMessageModel({
    required this.id,
    required this.body,
    required this.authorName,
    required this.internal,
    required this.createdAt,
  });
  final String id;
  final String body;
  final String authorName;
  final bool internal;
  final DateTime createdAt;

  factory SupportMessageModel.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? const {};
    return SupportMessageModel(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      authorName: author['name'] as String? ?? 'Support',
      internal: json['internal'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    );
  }
}

class SupportTicketModel {
  const SupportTicketModel({
    required this.id,
    required this.subject,
    required this.description,
    required this.category,
    required this.status,
    required this.creatorName,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.appArea,
    this.attachmentName,
  });
  final String id;
  final String subject;
  final String description;
  final SupportCategory category;
  final SupportStatus status;
  final String creatorName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SupportMessageModel> messages;
  final String? appArea;
  final String? attachmentName;

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'] as Map<String, dynamic>? ?? const {};
    final attachment = json['attachment'] as Map<String, dynamic>?;
    final rawCategory = json['category'] as String? ?? 'OTHER';
    final rawStatus = json['status'] as String? ?? 'OPEN';
    return SupportTicketModel(
      id: json['id'] as String,
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: SupportCategory.values.firstWhere(
        (item) => item.apiName == rawCategory,
        orElse: () => SupportCategory.other,
      ),
      status: SupportStatus.values.firstWhere(
        (item) => item.apiName == rawStatus,
        orElse: () => SupportStatus.open,
      ),
      creatorName: creator['name'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SupportMessageModel.fromJson)
          .toList(),
      appArea: json['appArea'] as String?,
      attachmentName: attachment?['originalName'] as String?,
    );
  }
}
