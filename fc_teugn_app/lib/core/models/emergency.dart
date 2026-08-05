class EmergencyAccessGrant {
  const EmergencyAccessGrant({
    required this.token,
    required this.expiresAt,
  });

  final String token;
  final DateTime expiresAt;

  factory EmergencyAccessGrant.fromJson(Map<String, dynamic> json) {
    return EmergencyAccessGrant(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
    );
  }
}

class EmergencyEvent {
  const EmergencyEvent({
    required this.id,
    required this.title,
    required this.startAt,
    required this.location,
    this.endAt,
    this.meetingAt,
    this.address,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final DateTime? meetingAt;
  final String location;
  final String? address;

  factory EmergencyEvent.fromJson(Map<String, dynamic> json) {
    DateTime? optionalDate(Object? value) =>
        value is String ? DateTime.parse(value).toLocal() : null;

    return EmergencyEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      startAt: DateTime.parse(json['startAt'] as String).toLocal(),
      endAt: optionalDate(json['endAt']),
      meetingAt: optionalDate(json['meetingAt']),
      location: json['location'] as String? ?? '',
      address: json['address'] as String?,
    );
  }
}

class EmergencyGuardian {
  const EmergencyGuardian({
    required this.id,
    required this.name,
    required this.relationship,
    required this.isLegalGuardian,
    required this.canPickup,
    this.phone,
  });

  final String id;
  final String name;
  final String? phone;
  final String relationship;
  final bool isLegalGuardian;
  final bool canPickup;

  factory EmergencyGuardian.fromJson(Map<String, dynamic> json) {
    return EmergencyGuardian(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Erziehungsberechtigte Person',
      phone: json['phone'] as String?,
      relationship: json['relationship'] as String? ?? 'GUARDIAN',
      isLegalGuardian: json['isLegalGuardian'] as bool? ?? false,
      canPickup: json['canPickup'] as bool? ?? false,
    );
  }
}

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.priority,
    required this.isAuthorizedPickup,
    this.relationship,
  });

  final String id;
  final String name;
  final String phone;
  final String? relationship;
  final int priority;
  final bool isAuthorizedPickup;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      relationship: json['relationship'] as String?,
      priority: json['priority'] as int? ?? 1,
      isAuthorizedPickup: json['isAuthorizedPickup'] as bool? ?? false,
    );
  }
}

class EmergencyMedicalInfo {
  const EmergencyMedicalInfo({
    this.allergies,
    this.medications,
    this.conditions,
    this.emergencyNotes,
  });

  final String? allergies;
  final String? medications;
  final String? conditions;
  final String? emergencyNotes;

  bool get hasInformation =>
      _hasText(allergies) ||
      _hasText(medications) ||
      _hasText(conditions) ||
      _hasText(emergencyNotes);

  factory EmergencyMedicalInfo.fromJson(Map<String, dynamic>? json) {
    return EmergencyMedicalInfo(
      allergies: json?['allergies'] as String?,
      medications: json?['medications'] as String?,
      conditions: json?['conditions'] as String?,
      emergencyNotes: json?['emergencyNotes'] as String?,
    );
  }

  static bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;
}

class EmergencyPlayer {
  const EmergencyPlayer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.guardians,
    required this.emergencyContacts,
    required this.medical,
    this.preferredName,
    this.photoUrl,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? photoUrl;
  final List<EmergencyGuardian> guardians;
  final List<EmergencyContact> emergencyContacts;
  final EmergencyMedicalInfo medical;

  String get name {
    final preferred = preferredName?.trim();
    return '${preferred?.isNotEmpty == true ? preferred : firstName} $lastName';
  }

  factory EmergencyPlayer.fromJson(Map<String, dynamic> json) {
    return EmergencyPlayer(
      id: json['id'] as String,
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      preferredName: json['preferredName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      guardians: (json['guardians'] as List<dynamic>? ?? [])
          .map((item) =>
              EmergencyGuardian.fromJson(item as Map<String, dynamic>))
          .toList(),
      emergencyContacts: (json['emergencyContacts'] as List<dynamic>? ?? [])
          .map(
              (item) => EmergencyContact.fromJson(item as Map<String, dynamic>))
          .toList(),
      medical: EmergencyMedicalInfo.fromJson(
        json['medical'] as Map<String, dynamic>?,
      ),
    );
  }
}

class EmergencyView {
  const EmergencyView({
    required this.event,
    required this.generatedAt,
    required this.presenceSource,
    required this.players,
  });

  final EmergencyEvent event;
  final DateTime generatedAt;
  final String presenceSource;
  final List<EmergencyPlayer> players;

  bool get usesActualAttendance => presenceSource == 'ACTUAL_ATTENDANCE';

  factory EmergencyView.fromJson(Map<String, dynamic> json) {
    return EmergencyView(
      event: EmergencyEvent.fromJson(json['event'] as Map<String, dynamic>),
      generatedAt: DateTime.parse(json['generatedAt'] as String).toLocal(),
      presenceSource:
          json['presenceSource'] as String? ?? 'CONFIRMED_ATTENDANCE',
      players: (json['players'] as List<dynamic>? ?? [])
          .map((item) => EmergencyPlayer.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
