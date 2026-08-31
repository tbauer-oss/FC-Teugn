enum PlayerStatus { active, injured, paused, left }

const injuryTypeLabels = <String, String>{
  'MUSCLE_INJURY': 'Muskelverletzung',
  'LIGAMENT_INJURY': 'Bänderverletzung',
  'CONTUSION': 'Prellung',
  'STRAIN': 'Zerrung',
  'FRACTURE': 'Knochenbruch',
  'JOINT_INJURY': 'Gelenkverletzung',
  'HEAD_INJURY_CONCUSSION': 'Kopfverletzung / Gehirnerschütterung',
  'OVERUSE': 'Überlastung',
  'ILLNESS': 'Erkrankung',
  'OTHER': 'Sonstige Verletzung',
};

String injuryTypeLabel(String? value) =>
    injuryTypeLabels[value] ?? 'Nicht näher angegeben';

enum DominantFoot { right, left, both, unknown }

enum PlayerGender { male, female, diverse }

String? playerGenderApi(PlayerGender? gender) => switch (gender) {
      PlayerGender.male => 'MALE',
      PlayerGender.female => 'FEMALE',
      PlayerGender.diverse => 'DIVERSE',
      null => null,
    };

String playerGenderLabel(PlayerGender? gender) => switch (gender) {
      PlayerGender.male => 'm · männlich',
      PlayerGender.female => 'w · weiblich',
      PlayerGender.diverse => 'd · divers',
      null => 'Noch offen',
    };

PlayerGender? _playerGender(String? value) => switch (value) {
      'MALE' => PlayerGender.male,
      'FEMALE' => PlayerGender.female,
      'DIVERSE' => PlayerGender.diverse,
      _ => null,
    };

Map<String, dynamic>? _jsonMap(Object? value) =>
    value is Map<dynamic, dynamic> ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _jsonMapList(Object? value) => value is List
    ? value
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList()
    : const [];

String? _jsonString(Object? value) => value?.toString();

int _jsonInt(Object? value, [int fallback = 0]) => switch (value) {
      num number => number.toInt(),
      String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };

DateTime? _jsonDate(Object? value) {
  final text = _jsonString(value);
  return text == null ? null : DateTime.tryParse(text);
}

class PlayerCapabilities {
  const PlayerCapabilities({
    this.canEdit = false,
    this.canViewSensitive = false,
    this.canEditSensitive = false,
    this.canAddDevelopment = false,
    this.canManageDocuments = false,
    this.canManagePhoto = false,
    this.canDigitallyConsent = false,
  });

  final bool canEdit;
  final bool canViewSensitive;
  final bool canEditSensitive;
  final bool canAddDevelopment;
  final bool canManageDocuments;
  final bool canManagePhoto;
  final bool canDigitallyConsent;

  factory PlayerCapabilities.fromJson(Map<String, dynamic>? json) =>
      PlayerCapabilities(
        canEdit: json?['canEdit'] as bool? ?? false,
        canViewSensitive: json?['canViewSensitive'] as bool? ?? false,
        canEditSensitive: json?['canEditSensitive'] as bool? ?? false,
        canAddDevelopment: json?['canAddDevelopment'] as bool? ?? false,
        canManageDocuments: json?['canManageDocuments'] as bool? ?? false,
        canManagePhoto: json?['canManagePhoto'] as bool? ?? false,
        canDigitallyConsent: json?['canDigitallyConsent'] as bool? ?? false,
      );
}

class PlayerDocumentFile {
  const PlayerDocumentFile({
    required this.id,
    required this.originalName,
    required this.contentType,
    required this.size,
    required this.downloadUrl,
  });

  final String id;
  final String originalName;
  final String contentType;
  final int size;
  final String downloadUrl;

  factory PlayerDocumentFile.fromJson(Map<String, dynamic> json) =>
      PlayerDocumentFile(
        id: json['id'] as String,
        originalName: json['originalName'] as String,
        contentType: json['contentType'] as String,
        size: json['size'] as int,
        downloadUrl: json['downloadUrl'] as String,
      );
}

class PlayerDocument {
  const PlayerDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.version,
    required this.status,
    required this.createdAt,
    required this.file,
    this.validFrom,
    this.validUntil,
    this.grantedBy,
    this.grantedAt,
    this.note,
  });

  final String id;
  final String type;
  final String title;
  final int version;
  final String status;
  final DateTime createdAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? grantedBy;
  final DateTime? grantedAt;
  final String? note;
  final PlayerDocumentFile file;

  factory PlayerDocument.fromJson(Map<String, dynamic> json) => PlayerDocument(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        version: json['version'] as int,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        validFrom: json['validFrom'] == null
            ? null
            : DateTime.parse(json['validFrom'] as String),
        validUntil: json['validUntil'] == null
            ? null
            : DateTime.parse(json['validUntil'] as String),
        grantedBy: json['grantedBy'] as String?,
        grantedAt: json['grantedAt'] == null
            ? null
            : DateTime.parse(json['grantedAt'] as String),
        note: json['note'] as String?,
        file: PlayerDocumentFile.fromJson(
          json['file'] as Map<String, dynamic>,
        ),
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
      receivesCommunication: json['receivesCommunication'] as bool? ?? false,
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
    this.templateVersion,
    this.currentHash,
    this.latestEvidence,
  });

  final String id;
  final String type;
  final String status;
  final DateTime? grantedAt;
  final DateTime? expiresAt;
  final String? note;
  final String? templateVersion;
  final String? currentHash;
  final PlayerConsentEvidence? latestEvidence;

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
        templateVersion: json['templateVersion'] as String?,
        currentHash: json['currentHash'] as String?,
        latestEvidence: _latestGrantedEvidence(json['evidence']),
      );

  static PlayerConsentEvidence? _latestGrantedEvidence(Object? value) {
    final entries = value is List<dynamic> ? value : const <dynamic>[];
    for (final entry in entries) {
      final evidence =
          PlayerConsentEvidence.fromJson(entry as Map<String, dynamic>);
      if (evidence.action == 'GRANTED') return evidence;
    }
    return null;
  }
}

class PlayerConsentEvidence {
  const PlayerConsentEvidence({
    required this.id,
    required this.action,
    required this.templateVersion,
    required this.signerName,
    required this.documentHash,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String templateVersion;
  final String signerName;
  final String documentHash;
  final DateTime createdAt;

  factory PlayerConsentEvidence.fromJson(Map<String, dynamic> json) =>
      PlayerConsentEvidence(
        id: json['id'] as String,
        action: json['action'] as String? ?? 'PENDING',
        templateVersion: json['templateVersion'] as String? ?? '',
        signerName: json['signerName'] as String? ?? '',
        documentHash: json['documentHash'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class ConsentTemplateOption {
  const ConsentTemplateOption({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;

  factory ConsentTemplateOption.fromJson(Map<String, dynamic> json) =>
      ConsentTemplateOption(
        id: json['id'] as String,
        label: json['label'] as String,
        description: json['description'] as String?,
      );
}

class ConsentTemplate {
  const ConsentTemplate({
    required this.type,
    required this.version,
    required this.title,
    required this.shortTitle,
    required this.purpose,
    required this.legalBasis,
    required this.retention,
    required this.options,
    required this.explicit,
    this.risks,
  });

  final String type;
  final String version;
  final String title;
  final String shortTitle;
  final String purpose;
  final String legalBasis;
  final String retention;
  final String? risks;
  final List<ConsentTemplateOption> options;
  final bool explicit;

  factory ConsentTemplate.fromJson(Map<String, dynamic> json) =>
      ConsentTemplate(
        type: json['type'] as String,
        version: json['version'] as String,
        title: json['title'] as String,
        shortTitle: json['shortTitle'] as String,
        purpose: json['purpose'] as String,
        legalBasis: json['legalBasis'] as String,
        retention: json['retention'] as String,
        risks: json['risks'] as String?,
        explicit: json['explicit'] as bool? ?? false,
        options: (json['options'] as List<dynamic>? ?? const [])
            .map(
              (item) => ConsentTemplateOption.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

bool hasCurrentConsentDecision(
  PlayerConsent? consent,
  ConsentTemplate template,
) {
  if (consent == null || consent.templateVersion != template.version) {
    return false;
  }
  return consent.status == 'GRANTED' || consent.status == 'REVOKED';
}

List<ConsentTemplate> openConsentTemplates(
  List<PlayerConsent> consents,
  List<ConsentTemplate> templates,
) {
  return templates.where((template) {
    PlayerConsent? current;
    for (final consent in consents) {
      if (consent.type == template.type) {
        current = consent;
        break;
      }
    }
    return !hasCurrentConsentDecision(current, template);
  }).toList(growable: false);
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
    this.gender,
    this.position,
    this.secondaryPosition,
    this.shirtNumber,
    this.passNumber,
    this.injuryType,
    this.injuryDetails,
    this.joinedAt,
    this.photoUrl,
    this.teamName,
    this.teamNumber,
    this.ageGroupCode,
    this.goals = 0,
    this.assists = 0,
    this.appearances = 0,
    this.starts = 0,
    this.minutes = 0,
    this.cleanSheets = 0,
    this.cleanSheetEligible = false,
    this.statisticsBySeason = const [],
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
  final PlayerGender? gender;
  final String? position;
  final String? secondaryPosition;
  final DominantFoot dominantFoot;
  final int? shirtNumber;
  final String? passNumber;
  final String? injuryType;
  final String? injuryDetails;
  final PlayerStatus status;
  final DateTime? joinedAt;
  final String? photoUrl;
  final String? teamName;
  final int? teamNumber;
  final String? ageGroupCode;
  final int goals;
  final int assists;
  final int appearances;
  final int starts;
  final int minutes;
  final int cleanSheets;
  final bool cleanSheetEligible;
  final List<PlayerSeasonStatistics> statisticsBySeason;
  final List<GuardianModel> guardians;
  final MedicalProfile? medicalProfile;
  final List<EmergencyContact> emergencyContacts;
  final List<DevelopmentNote> developmentNotes;
  final List<PlayerConsent> consents;
  final PlayerCapabilities capabilities;

  String get fullName {
    final name = [firstName.trim(), lastName.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (name.isNotEmpty) return name;

    final preferred = preferredName?.trim();
    return preferred?.isNotEmpty == true ? preferred! : 'Unbenannter Spieler';
  }

  String get displayName {
    final preferred = preferredName?.trim();
    if (preferred?.isNotEmpty == true) return preferred!;

    final first = firstName.trim();
    return first.isNotEmpty ? first : fullName;
  }

  String get initials {
    final value = [firstName.trim(), lastName.trim()]
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return value.isEmpty ? '?' : value;
  }

  String get teamCode {
    if (teamId == null) return 'Nicht zugeordnet';
    final code = ageGroupCode?.trim().toUpperCase();
    final number = teamNumber ??
        int.tryParse(
          RegExp(r'(\d+)$').firstMatch(teamName?.trim() ?? '')?.group(1) ?? '',
        );
    if (code?.isNotEmpty == true && number != null) return '$code$number';
    if (teamName?.trim().isNotEmpty == true) return teamName!.trim();
    return code?.isNotEmpty == true ? code! : 'Mannschaft';
  }

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
    final team = _jsonMap(json['team']);
    final ageGroup = _jsonMap(team?['ageGroup']);
    final statistics = _jsonMap(json['statistics']);
    final medicalProfile = _jsonMap(json['medicalProfile']);
    final id = _jsonString(json['id']);
    if (id == null || id.isEmpty) {
      throw const FormatException('Spieler-ID fehlt in der Serverantwort.');
    }
    return PlayerModel(
      id: id,
      teamId: _jsonString(json['teamId']),
      firstName: _jsonString(json['firstName']) ?? '',
      lastName: _jsonString(json['lastName']) ?? '',
      preferredName: _jsonString(json['preferredName']),
      birthDate: _jsonDate(json['birthDate']),
      nationality: _jsonString(json['nationality']),
      gender: _playerGender(_jsonString(json['gender'])),
      position: _jsonString(json['position']),
      secondaryPosition: _jsonString(json['secondaryPosition']),
      dominantFoot: _foot(_jsonString(json['dominantFoot'])),
      shirtNumber:
          json['shirtNumber'] == null ? null : _jsonInt(json['shirtNumber']),
      passNumber: _jsonString(json['passNumber']),
      injuryType: _jsonString(json['injuryType']),
      injuryDetails: _jsonString(json['injuryDetails']),
      status: _status(_jsonString(json['status'])),
      joinedAt: _jsonDate(json['joinedAt']),
      photoUrl: _jsonString(json['photoUrl']),
      teamName: _jsonString(team?['name']),
      teamNumber:
          team?['teamNumber'] == null ? null : _jsonInt(team?['teamNumber']),
      ageGroupCode: _jsonString(ageGroup?['code']),
      goals: _jsonInt(statistics?['goals']),
      assists: _jsonInt(statistics?['assists']),
      appearances: _jsonInt(statistics?['appearances']),
      starts: _jsonInt(statistics?['starts']),
      minutes: _jsonInt(statistics?['minutes']),
      cleanSheets: _jsonInt(statistics?['cleanSheets']),
      cleanSheetEligible: statistics?['cleanSheetEligible'] as bool? ?? false,
      statisticsBySeason: _jsonMapList(json['statisticsBySeason'])
          .map(PlayerSeasonStatistics.fromJson)
          .toList(),
      guardians: _jsonMapList(json['parentLinks'])
          .map(GuardianModel.fromJson)
          .toList(),
      medicalProfile: medicalProfile == null
          ? null
          : MedicalProfile.fromJson(medicalProfile),
      emergencyContacts: _jsonMapList(json['emergencyContacts'])
          .map(EmergencyContact.fromJson)
          .toList(),
      developmentNotes: _jsonMapList(json['developmentNotes'])
          .map(DevelopmentNote.fromJson)
          .toList(),
      consents:
          _jsonMapList(json['consents']).map(PlayerConsent.fromJson).toList(),
      capabilities: PlayerCapabilities.fromJson(_jsonMap(json['capabilities'])),
    );
  }
}

class PlayerSeasonStatistics {
  const PlayerSeasonStatistics({
    required this.seasonId,
    required this.seasonName,
    required this.goals,
    required this.assists,
    required this.appearances,
    required this.starts,
    required this.minutes,
    required this.cleanSheets,
  });

  final String seasonId;
  final String seasonName;
  final int goals;
  final int assists;
  final int appearances;
  final int starts;
  final int minutes;
  final int cleanSheets;

  factory PlayerSeasonStatistics.fromJson(Map<String, dynamic> json) =>
      PlayerSeasonStatistics(
        seasonId: _jsonString(json['seasonId']) ?? '',
        seasonName: _jsonString(json['seasonName']) ?? 'Saison',
        goals: _jsonInt(json['goals']),
        assists: _jsonInt(json['assists']),
        appearances: _jsonInt(json['appearances']),
        starts: _jsonInt(json['starts']),
        minutes: _jsonInt(json['minutes']),
        cleanSheets: _jsonInt(json['cleanSheets']),
      );
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
