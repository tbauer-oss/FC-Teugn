enum PlayerStatus { active, injured, paused, left }

enum DominantFoot { right, left, both, unknown }

class PlayerCapabilities {
  const PlayerCapabilities({
    this.canEdit = false,
    this.canViewSensitive = false,
    this.canEditSensitive = false,
    this.canAddDevelopment = false,
  });

  final bool canEdit;
  final bool canViewSensitive;
  final bool canEditSensitive;
  final bool canAddDevelopment;

  factory PlayerCapabilities.fromJson(Map<String, dynamic>? json) =>
      PlayerCapabilities(
        canEdit: json?['canEdit'] as bool? ?? false,
        canViewSensitive: json?['canViewSensitive'] as bool? ?? false,
        canEditSensitive: json?['canEditSensitive'] as bool? ?? false,
        canAddDevelopment: json?['canAddDevelopment'] as bool? ?? false,
      );
}

class GuardianModel {
  const GuardianModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.relationship,
    required this.isLegalGuardian,
    required this.canPickup,
    required this.receivesCommunication,
    this.phone,
  });

  final String id;
  final String userId;
  final String name;
  final String email;
  final String? phone;
  final String relationship;
  final bool isLegalGuardian;
  final bool canPickup;
  final bool receivesCommunication;

  factory GuardianModel.fromJson(Map<String, dynamic> json) {
    final parent = json['parent'] as Map<String, dynamic>;
    return GuardianModel(
      id: json['id'] as String,
      userId: parent['id'] as String,
      name: parent['name'] as String,
      email: parent['email'] as String,
      phone: parent['phone'] as String?,
      relationship: json['relationship'] as String? ?? 'GUARDIAN',
      isLegalGuardian: json['isLegalGuardian'] as bool? ?? false,
      canPickup: json['canPickup'] as bool? ?? false,
      receivesCommunication:
          json['receivesCommunication'] as bool? ?? false,
    );
  }
}

class MedicalProfile {
  const MedicalProfile({
    this.allergies,
    this.medications,
    this.conditions,
    this.physicianName,
    this.physicianPhone,
    this.emergencyNotes,
  });

  final String? allergies;
  final String? medications;
  final String? conditions;
  final String? physicianName;
  final String? physicianPhone;
  final String? emergencyNotes;

  bool get isEmpty => [
        allergies,
        medications,
        conditions,
        physicianName,
        physicianPhone,
        emergencyNotes,
      ].every((value) => value == null || value.isEmpty);

  factory MedicalProfile.fromJson(Map<String, dynamic> json) => MedicalProfile(
        allergies: json['allergies'] as String?,
        medications: json['medications'] as String?,
        conditions: json['conditions'] as String?,
        physicianName: json['physicianName'] as String?,
        physicianPhone: json['physicianPhone'] as String?,
        emergencyNotes: json['emergencyNotes'] as String?,
      );
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

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        relationship: json['relationship'] as String?,
        priority: json['priority'] as int? ?? 1,
        isAuthorizedPickup: json['isAuthorizedPickup'] as bool? ?? false,
      );
}

class DevelopmentNote {
  const DevelopmentNote({
    required this.id,
    required this.title,
    required this.notes,
    required this.category,
    required this.visibility,
    required this.observedAt,
    required this.authorName,
    this.rating,
  });

  final String id;
  final String title;
  final String notes;
  final String category;
  final String visibility;
  final int? rating;
  final DateTime observedAt;
  final String authorName;

  factory DevelopmentNote.fromJson(Map<String, dynamic> json) =>
      DevelopmentNote(
        id: json['id'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String,
        category: json['category'] as String? ?? 'GENERAL',
        visibility: json['visibility'] as String? ?? 'STAFF_ONLY',
        rating: json['rating'] as int?,
        observedAt: DateTime.parse(json['observedAt'] as String),
        authorName:
            (json['author'] as Map<String, dynamic>?)?['name'] as String? ??
                'Trainerteam',
      );
}

class PlayerConsent {
  const PlayerConsent({
    required this.id,
    required this.type,
    required this.status,
    this.grantedAt,
    this.expiresAt,
    this.note,
  });

  final String id;
  final String type;
  final String status;
  final DateTime? grantedAt;
  final DateTime? expiresAt;
  final String? note;

  factory PlayerConsent.fromJson(Map<String, dynamic> json) => PlayerConsent(
        id: json['id'] as String,
        type: json['type'] as String,
        status: json['status'] as String? ?? 'PENDING',
        grantedAt: json['grantedAt'] == null
            ? null
            : DateTime.parse(json['grantedAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
        note: json['note'] as String?,
      );
}

class PlayerModel {
  const PlayerModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.status,
    required this.dominantFoot,
    this.teamId,
    this.preferredName,
    this.birthDate,
    this.nationality,
    this.position,
    this.secondaryPosition,
    this.shirtNumber,
    this.joinedAt,
    this.photoUrl,
    this.teamName,
    this.ageGroupCode,
    this.guardians = const [],
    this.medicalProfile,
    this.emergencyContacts = const [],
    this.developmentNotes = const [],
    this.consents = const [],
    this.capabilities = const PlayerCapabilities(),
  });

  final String id;
  final String? teamId;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final DateTime? birthDate;
  final String? nationality;
  final String? position;
  final String? secondaryPosition;
  final DominantFoot dominantFoot;
  final int? shirtNumber;
  final PlayerStatus status;
  final DateTime? joinedAt;
  final String? photoUrl;
  final String? teamName;
  final String? ageGroupCode;
  final List<GuardianModel> guardians;
  final MedicalProfile? medicalProfile;
  final List<EmergencyContact> emergencyContacts;
  final List<DevelopmentNote> developmentNotes;
  final List<PlayerConsent> consents;
  final PlayerCapabilities capabilities;

  String get fullName => '$firstName $lastName';
  String get displayName =>
      preferredName?.isNotEmpty == true ? preferredName! : firstName;
  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    var result = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      result--;
    }
    return result;
  }

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    final team = json['team'] as Map<String, dynamic>?;
    final ageGroup = team?['ageGroup'] as Map<String, dynamic>?;
    return PlayerModel(
      id: json['id'] as String,
      teamId: json['teamId'] as String?,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      preferredName: json['preferredName'] as String?,
      birthDate: json['birthDate'] == null
          ? null
          : DateTime.parse(json['birthDate'] as String),
      nationality: json['nationality'] as String?,
      position: json['position'] as String?,
      secondaryPosition: json['secondaryPosition'] as String?,
      dominantFoot: _foot(json['dominantFoot'] as String?),
      shirtNumber: json['shirtNumber'] as int?,
      status: _status(json['status'] as String?),
      joinedAt: json['joinedAt'] == null
          ? null
          : DateTime.parse(json['joinedAt'] as String),
      photoUrl: json['photoUrl'] as String?,
      teamName: team?['name'] as String?,
      ageGroupCode: ageGroup?['code'] as String?,
      guardians: (json['parentLinks'] as List<dynamic>? ?? [])
          .map((item) => GuardianModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      medicalProfile: json['medicalProfile'] == null
          ? null
          : MedicalProfile.fromJson(
              json['medicalProfile'] as Map<String, dynamic>,
            ),
      emergencyContacts:
          (json['emergencyContacts'] as List<dynamic>? ?? [])
              .map((item) =>
                  EmergencyContact.fromJson(item as Map<String, dynamic>))
              .toList(),
      developmentNotes:
          (json['developmentNotes'] as List<dynamic>? ?? [])
              .map((item) =>
                  DevelopmentNote.fromJson(item as Map<String, dynamic>))
              .toList(),
      consents: (json['consents'] as List<dynamic>? ?? [])
          .map(
              (item) => PlayerConsent.fromJson(item as Map<String, dynamic>))
          .toList(),
      capabilities: PlayerCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>?,
      ),
    );
  }
}

PlayerStatus _status(String? value) => switch (value) {
      'INJURED' => PlayerStatus.injured,
      'PAUSED' => PlayerStatus.paused,
      'LEFT' => PlayerStatus.left,
      _ => PlayerStatus.active,
    };

DominantFoot _foot(String? value) => switch (value) {
      'RIGHT' => DominantFoot.right,
      'LEFT' => DominantFoot.left,
      'BOTH' => DominantFoot.both,
      _ => DominantFoot.unknown,
    };

String playerStatusApi(PlayerStatus value) => switch (value) {
      PlayerStatus.active => 'ACTIVE',
      PlayerStatus.injured => 'INJURED',
      PlayerStatus.paused => 'PAUSED',
      PlayerStatus.left => 'LEFT',
    };

String dominantFootApi(DominantFoot value) => switch (value) {
      DominantFoot.right => 'RIGHT',
      DominantFoot.left => 'LEFT',
      DominantFoot.both => 'BOTH',
      DominantFoot.unknown => 'UNKNOWN',
    };
