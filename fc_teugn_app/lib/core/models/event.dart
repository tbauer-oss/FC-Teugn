enum EventType { training, match, event }

enum EventCategory {
  training,
  leagueMatch,
  friendlyMatch,
  cupMatch,
  tournament,
  indoorTournament,
  footballFestival,
  teamMeeting,
  parentsMeeting,
  christmasParty,
  seasonClosing,
  clubEvent,
  trip,
  photoSession,
  specialEvent,
}

enum EventStatus { scheduled, cancelled }

enum EventCommunicationStatus { draft, internalPublished, familyReleased }

enum EventNotificationMode { none, inApp, push }

extension EventNotificationModeX on EventNotificationMode {
  String get apiName => switch (this) {
        EventNotificationMode.none => 'NONE',
        EventNotificationMode.inApp => 'IN_APP',
        EventNotificationMode.push => 'PUSH',
      };
}

enum EventVisibility { team, club, staffOnly }

enum HomeAway { home, away, neutral }

enum RecurrenceFrequency { weekly, biweekly, custom }

enum AttendanceStatus { yes, no, maybe, unknown }

enum CarpoolRequestStatus { requested, confirmed, declined, cancelled }

T _enumFromApi<T extends Enum>(String? value, List<T> values, T fallback) {
  final normalized = (value ?? '').replaceAll('_', '').toLowerCase();
  return values.firstWhere(
    (item) => item.name.toLowerCase() == normalized,
    orElse: () => fallback,
  );
}

DateTime _localDate(String value) => DateTime.parse(value).toLocal();

extension EventCategoryX on EventCategory {
  String get apiName => switch (this) {
        EventCategory.training => 'TRAINING',
        EventCategory.leagueMatch => 'LEAGUE_MATCH',
        EventCategory.friendlyMatch => 'FRIENDLY_MATCH',
        EventCategory.cupMatch => 'CUP_MATCH',
        EventCategory.tournament => 'TOURNAMENT',
        EventCategory.indoorTournament => 'INDOOR_TOURNAMENT',
        EventCategory.footballFestival => 'FOOTBALL_FESTIVAL',
        EventCategory.teamMeeting => 'TEAM_MEETING',
        EventCategory.parentsMeeting => 'PARENTS_MEETING',
        EventCategory.christmasParty => 'CHRISTMAS_PARTY',
        EventCategory.seasonClosing => 'SEASON_CLOSING',
        EventCategory.clubEvent => 'CLUB_EVENT',
        EventCategory.trip => 'TRIP',
        EventCategory.photoSession => 'PHOTO_SESSION',
        EventCategory.specialEvent => 'SPECIAL_EVENT',
      };

  String get label => switch (this) {
        EventCategory.training => 'Training',
        EventCategory.leagueMatch => 'Pflichtspiel',
        EventCategory.friendlyMatch => 'Freundschaftsspiel',
        EventCategory.cupMatch => 'Pokalspiel',
        EventCategory.tournament => 'Turnier',
        EventCategory.indoorTournament => 'Hallenturnier',
        EventCategory.footballFestival => 'Fußballfestival',
        EventCategory.teamMeeting => 'Mannschaftsbesprechung',
        EventCategory.parentsMeeting => 'Elternabend',
        EventCategory.christmasParty => 'Weihnachtsfeier',
        EventCategory.seasonClosing => 'Saisonabschluss',
        EventCategory.clubEvent => 'Vereinsveranstaltung',
        EventCategory.trip => 'Ausflug',
        EventCategory.photoSession => 'Fototermin',
        EventCategory.specialEvent => 'Sonderveranstaltung',
      };

  bool get isMatch => const {
        EventCategory.leagueMatch,
        EventCategory.friendlyMatch,
        EventCategory.cupMatch,
        EventCategory.tournament,
        EventCategory.indoorTournament,
        EventCategory.footballFestival,
      }.contains(this);

  List<String> get titleSuggestions => switch (this) {
        EventCategory.training => const [
            'Training',
            'Torwarttraining',
            'Athletiktraining',
            'Abschlusstraining',
            'Testtraining',
          ],
        EventCategory.leagueMatch => const [
            'Pflichtspiel',
            'Heimspiel',
            'Auswärtsspiel',
          ],
        EventCategory.friendlyMatch => const [
            'Freundschaftsspiel',
            'Testspiel',
          ],
        EventCategory.cupMatch => const ['Pokalspiel'],
        EventCategory.tournament => const ['Turnier', 'Sommerturnier'],
        EventCategory.indoorTournament => const ['Hallenturnier'],
        EventCategory.footballFestival => const ['Fußballfestival'],
        EventCategory.teamMeeting => const [
            'Mannschaftsbesprechung',
            'Trainerbesprechung',
          ],
        EventCategory.parentsMeeting => const [
            'Elternabend',
            'Elterninformation',
          ],
        EventCategory.christmasParty => const ['Weihnachtsfeier'],
        EventCategory.seasonClosing => const ['Saisonabschluss'],
        EventCategory.clubEvent => const [
            'Vereinsveranstaltung',
            'Vereinsfest',
            'Arbeitseinsatz',
          ],
        EventCategory.trip => const ['Ausflug', 'Mannschaftsfahrt'],
        EventCategory.photoSession => const [
            'Fototermin',
            'Mannschaftsfoto',
          ],
        EventCategory.specialEvent => const [
            'Sonderveranstaltung',
            'Infoveranstaltung',
          ],
      };
}

String resolveEventTitle(String? title, EventCategory category) {
  final value = title?.trim() ?? '';
  return value.isEmpty ? category.label : value;
}

extension AttendanceStatusX on AttendanceStatus {
  String get apiName => name.toUpperCase();
  String get label => switch (this) {
        AttendanceStatus.yes => 'Zugesagt',
        AttendanceStatus.no => 'Abgesagt',
        AttendanceStatus.maybe => 'Vielleicht',
        AttendanceStatus.unknown => 'Offen',
      };
}

extension EventVisibilityX on EventVisibility {
  String get apiName => switch (this) {
        EventVisibility.team => 'TEAM',
        EventVisibility.club => 'CLUB',
        EventVisibility.staffOnly => 'STAFF_ONLY',
      };
}

extension HomeAwayX on HomeAway {
  String get apiName => name.toUpperCase();
}

extension RecurrenceFrequencyX on RecurrenceFrequency {
  String get apiName => switch (this) {
        RecurrenceFrequency.weekly => 'WEEKLY',
        RecurrenceFrequency.biweekly => 'BIWEEKLY',
        RecurrenceFrequency.custom => 'CUSTOM',
      };
}

class EventSeriesModel {
  const EventSeriesModel({
    required this.id,
    required this.frequency,
    required this.interval,
    required this.weekdays,
    required this.until,
  });

  final String id;
  final RecurrenceFrequency frequency;
  final int interval;
  final List<int> weekdays;
  final DateTime until;

  factory EventSeriesModel.fromJson(Map<String, dynamic> json) {
    return EventSeriesModel(
      id: json['id'] as String,
      frequency: _enumFromApi(
        json['frequency'] as String?,
        RecurrenceFrequency.values,
        RecurrenceFrequency.weekly,
      ),
      interval: json['interval'] as int? ?? 1,
      weekdays:
          (json['weekdays'] as List<dynamic>? ?? []).whereType<int>().toList(),
      until: _localDate(json['until'] as String),
    );
  }
}

class EventTeam {
  const EventTeam({
    required this.id,
    required this.name,
    required this.ageGroupCode,
  });

  final String id;
  final String name;
  final String ageGroupCode;

  String get label => '$ageGroupCode-Jugend · $name';

  factory EventTeam.fromJson(Map<String, dynamic> json) {
    final team = (json['team'] as Map<String, dynamic>?) ?? json;
    final ageGroup =
        team['ageGroup'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return EventTeam(
      id: team['id'] as String,
      name: team['name'] as String? ?? 'Mannschaft',
      ageGroupCode: ageGroup['code'] as String? ?? '',
    );
  }
}

class EventAttachment {
  const EventAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.mimeType,
  });

  final String id;
  final String name;
  final String url;
  final String? mimeType;

  factory EventAttachment.fromJson(Map<String, dynamic> json) {
    return EventAttachment(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class MatchDetails {
  const MatchDetails({
    required this.opponent,
    required this.isHome,
    this.durationMinutes = 60,
    this.periodMinutes = 30,
    this.periodCount = 2,
    this.competition,
    this.notes,
    this.ourGoals,
    this.theirGoals,
    this.opponentId,
    this.opponentLogoUrl,
    this.leagueId,
  });

  final String opponent;
  final bool isHome;
  final int durationMinutes;
  final int periodMinutes;
  final int periodCount;
  final String? competition;
  final String? notes;
  final int? ourGoals;
  final int? theirGoals;
  final String? opponentId;
  final String? opponentLogoUrl;
  final String? leagueId;

  factory MatchDetails.fromJson(Map<String, dynamic> json) {
    return MatchDetails(
      opponent: json['opponent'] as String? ?? 'Unbekannt',
      isHome: json['isHome'] as bool? ?? true,
      durationMinutes: json['durationMinutes'] as int? ?? 60,
      periodMinutes: json['periodMinutes'] as int? ?? 30,
      periodCount: json['periodCount'] as int? ?? 2,
      competition: json['competition'] as String?,
      notes: json['notes'] as String?,
      ourGoals: json['ourGoals'] as int?,
      theirGoals: json['theirGoals'] as int?,
      opponentId: json['opponentId'] as String?,
      opponentLogoUrl: json['opponentLogoUrl'] as String?,
      leagueId: json['leagueId'] as String?,
    );
  }
}

class EventAttendance {
  const EventAttendance({
    required this.id,
    required this.playerId,
    required this.status,
    this.playerName,
    this.position,
    this.photoUrl,
    this.reason,
    this.goalkeeperAvailable,
    this.respondedAt,
    this.actualAttendance,
    this.actualAttendanceNote,
  });

  final String id;
  final String playerId;
  final AttendanceStatus status;
  final String? playerName;
  final String? position;
  final String? photoUrl;
  final String? reason;
  final bool? goalkeeperAvailable;
  final DateTime? respondedAt;
  final AttendanceStatus? actualAttendance;
  final String? actualAttendanceNote;

  factory EventAttendance.fromJson(Map<String, dynamic> json) {
    final player =
        json['player'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final preferredName = player['preferredName'] as String?;
    final fullName = [
      player['firstName'] as String?,
      player['lastName'] as String?,
    ].whereType<String>().join(' ');
    return EventAttendance(
      id: json['id'] as String,
      playerId: json['playerId'] as String,
      status: _enumFromApi(
        json['status'] as String?,
        AttendanceStatus.values,
        AttendanceStatus.unknown,
      ),
      playerName: preferredName?.isNotEmpty == true
          ? preferredName
          : (fullName.isEmpty ? null : fullName),
      position: player['position'] as String?,
      photoUrl: player['photoUrl'] as String?,
      reason: json['reason'] as String?,
      goalkeeperAvailable: json['goalkeeperAvailable'] as bool?,
      respondedAt: json['respondedAt'] == null
          ? null
          : _localDate(json['respondedAt'] as String),
      actualAttendance: json['actualAttendance'] == null
          ? null
          : _enumFromApi(
              json['actualAttendance'] as String?,
              AttendanceStatus.values,
              AttendanceStatus.unknown,
            ),
      actualAttendanceNote: json['actualAttendanceNote'] as String?,
    );
  }
}

class AttendanceSummary {
  const AttendanceSummary({
    this.yes = 0,
    this.no = 0,
    this.maybe = 0,
    this.unknown = 0,
    this.goalkeeperAvailable = 0,
  });

  final int yes;
  final int no;
  final int maybe;
  final int unknown;
  final int goalkeeperAvailable;

  int get total => yes + no + maybe + unknown;

  factory AttendanceSummary.fromJson(Map<String, dynamic>? json) {
    return AttendanceSummary(
      yes: json?['yes'] as int? ?? 0,
      no: json?['no'] as int? ?? 0,
      maybe: json?['maybe'] as int? ?? 0,
      unknown: json?['unknown'] as int? ?? 0,
      goalkeeperAvailable: json?['goalkeeperAvailable'] as int? ?? 0,
    );
  }
}

class MissingAttendance {
  const MissingAttendance({
    required this.id,
    required this.name,
    this.position,
  });

  final String id;
  final String name;
  final String? position;

  factory MissingAttendance.fromJson(Map<String, dynamic> json) {
    final preferred = json['preferredName'] as String?;
    return MissingAttendance(
      id: json['id'] as String,
      name: preferred?.isNotEmpty == true
          ? preferred!
          : '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'.trim(),
      position: json['position'] as String?,
    );
  }
}

class CarpoolPassenger {
  const CarpoolPassenger({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.status,
  });

  final String id;
  final String playerId;
  final String playerName;
  final CarpoolRequestStatus status;

  factory CarpoolPassenger.fromJson(Map<String, dynamic> json) {
    final player =
        json['player'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final preferred = player['preferredName'] as String?;
    return CarpoolPassenger(
      id: json['id'] as String,
      playerId: json['playerId'] as String,
      playerName: preferred?.isNotEmpty == true
          ? preferred!
          : '${player['firstName'] ?? ''} ${player['lastName'] ?? ''}'.trim(),
      status: _enumFromApi(
        json['status'] as String?,
        CarpoolRequestStatus.values,
        CarpoolRequestStatus.requested,
      ),
    );
  }
}

class CarpoolOffer {
  const CarpoolOffer({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.seatsTotal,
    required this.freeSeats,
    required this.departureLocation,
    required this.departureAt,
    required this.passengers,
    required this.canManage,
    this.driverPhone,
    this.notes,
  });

  final String id;
  final String driverId;
  final String driverName;
  final String? driverPhone;
  final int seatsTotal;
  final int freeSeats;
  final String departureLocation;
  final DateTime departureAt;
  final String? notes;
  final List<CarpoolPassenger> passengers;
  final bool canManage;

  factory CarpoolOffer.fromJson(Map<String, dynamic> json) {
    final driver =
        json['driver'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return CarpoolOffer(
      id: json['id'] as String,
      driverId: json['driverId'] as String,
      driverName: driver['name'] as String? ?? 'Fahrer/in',
      driverPhone: driver['phone'] as String?,
      seatsTotal: json['seatsTotal'] as int? ?? 0,
      freeSeats: json['freeSeats'] as int? ?? 0,
      departureLocation: json['departureLocation'] as String? ?? '',
      departureAt: _localDate(json['departureAt'] as String),
      notes: json['notes'] as String?,
      passengers: (json['passengers'] as List<dynamic>? ?? [])
          .map(
              (item) => CarpoolPassenger.fromJson(item as Map<String, dynamic>))
          .toList(),
      canManage: json['canManage'] as bool? ?? false,
    );
  }
}

class EventCapabilities {
  const EventCapabilities({
    this.canManage = false,
    this.canRespond = false,
    this.canOfferRide = false,
    this.canOpenEmergencyView = false,
    this.canDelete = false,
    this.canReschedule = false,
    this.canCancel = false,
  });

  final bool canManage;
  final bool canRespond;
  final bool canOfferRide;
  final bool canOpenEmergencyView;
  final bool canDelete;
  final bool canReschedule;
  final bool canCancel;

  factory EventCapabilities.fromJson(Map<String, dynamic>? json) {
    return EventCapabilities(
      canManage: json?['canManage'] as bool? ?? false,
      canRespond: json?['canRespond'] as bool? ?? false,
      canOfferRide: json?['canOfferRide'] as bool? ?? false,
      canOpenEmergencyView: json?['canOpenEmergencyView'] as bool? ?? false,
      canDelete: json?['canDelete'] as bool? ?? false,
      canReschedule: json?['canReschedule'] as bool? ?? false,
      canCancel: json?['canCancel'] as bool? ?? false,
    );
  }
}

class EventModel {
  const EventModel({
    required this.id,
    required this.teamId,
    required this.type,
    required this.category,
    required this.status,
    this.communicationStatus = EventCommunicationStatus.draft,
    required this.visibility,
    required this.title,
    required this.startAt,
    required this.location,
    required this.attendanceFinalized,
    required this.targetTeams,
    required this.attachments,
    required this.attendance,
    required this.attendanceSummary,
    required this.missingAttendance,
    required this.carpoolOffers,
    required this.capabilities,
    required this.reminderMinutes,
    this.reminderPushEnabled = true,
    this.participantPlayerIds = const [],
    this.series,
    this.endAt,
    this.meetingAt,
    this.meetingLocation,
    this.address,
    this.mapUrl,
    this.homeAway,
    this.opponent,
    this.opponentId,
    this.venue,
    this.contactName,
    this.contactPhone,
    this.description,
    this.equipment,
    this.clothing,
    this.catering,
    this.carpoolRequired = false,
    this.maxParticipants,
    this.responseDeadline,
    this.internalNote,
    this.isSeriesException = false,
    this.isHiddenRegularOccurrence = false,
    this.internalPublishedAt,
    this.familyReleasedAt,
    this.familyReleaseAudience,
    this.cancellationReason,
    this.matchDetails,
  });

  final String id;
  final String teamId;
  final EventType type;
  final EventCategory category;
  final EventStatus status;
  final EventCommunicationStatus communicationStatus;
  final EventVisibility visibility;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final DateTime? meetingAt;
  final String? meetingLocation;
  final String location;
  final String? address;
  final String? mapUrl;
  final HomeAway? homeAway;
  final String? opponent;
  final String? opponentId;
  final String? venue;
  final String? contactName;
  final String? contactPhone;
  final String? description;
  final String? equipment;
  final String? clothing;
  final String? catering;
  final bool carpoolRequired;
  final int? maxParticipants;
  final DateTime? responseDeadline;
  final String? internalNote;
  final List<int> reminderMinutes;
  final bool reminderPushEnabled;
  final List<String> participantPlayerIds;
  final bool isSeriesException;
  final bool isHiddenRegularOccurrence;
  final DateTime? internalPublishedAt;
  final DateTime? familyReleasedAt;
  final String? familyReleaseAudience;
  final String? cancellationReason;
  final bool attendanceFinalized;
  final EventSeriesModel? series;
  final List<EventTeam> targetTeams;
  final List<EventAttachment> attachments;
  final MatchDetails? matchDetails;
  final List<EventAttendance> attendance;
  final AttendanceSummary attendanceSummary;
  final List<MissingAttendance> missingAttendance;
  final List<CarpoolOffer> carpoolOffers;
  final EventCapabilities capabilities;

  bool get isCancelled => status == EventStatus.cancelled;
  bool get isRecurring => series != null;

  EventAttendance? attendanceFor(String playerId) {
    for (final item in attendance) {
      if (item.playerId == playerId) return item;
    }
    return null;
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      teamId: json['teamId'] as String,
      type: _enumFromApi(
        json['type'] as String?,
        EventType.values,
        EventType.event,
      ),
      category: _enumFromApi(
        json['category'] as String?,
        EventCategory.values,
        EventCategory.specialEvent,
      ),
      status: _enumFromApi(
        json['status'] as String?,
        EventStatus.values,
        EventStatus.scheduled,
      ),
      communicationStatus: _enumFromApi(
        json['communicationStatus'] as String?,
        EventCommunicationStatus.values,
        EventCommunicationStatus.draft,
      ),
      visibility: _enumFromApi(
        json['visibility'] as String?,
        EventVisibility.values,
        EventVisibility.team,
      ),
      title: json['title'] as String,
      startAt: _localDate(json['startAt'] as String),
      endAt: json['endAt'] == null ? null : _localDate(json['endAt'] as String),
      meetingAt: json['meetingAt'] == null
          ? null
          : _localDate(json['meetingAt'] as String),
      meetingLocation: json['meetingLocation'] as String?,
      location: json['location'] as String? ?? '',
      address: json['address'] as String?,
      mapUrl: json['mapUrl'] as String?,
      homeAway: json['homeAway'] == null
          ? null
          : _enumFromApi(
              json['homeAway'] as String?,
              HomeAway.values,
              HomeAway.neutral,
            ),
      opponent: json['opponent'] as String?,
      opponentId: json['opponentId'] as String?,
      venue: json['venue'] as String?,
      contactName: json['contactName'] as String?,
      contactPhone: json['contactPhone'] as String?,
      description: json['description'] as String?,
      equipment: json['equipment'] as String?,
      clothing: json['clothing'] as String?,
      catering: json['catering'] as String?,
      carpoolRequired: json['carpoolRequired'] as bool? ?? false,
      maxParticipants: json['maxParticipants'] as int?,
      responseDeadline: json['responseDeadline'] == null
          ? null
          : _localDate(json['responseDeadline'] as String),
      internalNote: json['internalNote'] as String?,
      reminderMinutes: (json['reminderMinutes'] as List<dynamic>? ?? [])
          .whereType<int>()
          .toList(),
      reminderPushEnabled: json['reminderPushEnabled'] as bool? ?? true,
      participantPlayerIds: (json['participants'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => item['playerId'])
          .whereType<String>()
          .toList(),
      isSeriesException: json['isSeriesException'] as bool? ?? false,
      isHiddenRegularOccurrence:
          json['isHiddenRegularOccurrence'] as bool? ?? false,
      internalPublishedAt: json['internalPublishedAt'] == null
          ? null
          : _localDate(json['internalPublishedAt'] as String),
      familyReleasedAt: json['familyReleasedAt'] == null
          ? null
          : _localDate(json['familyReleasedAt'] as String),
      familyReleaseAudience: json['familyReleaseAudience'] as String?,
      cancellationReason: json['cancellationReason'] as String?,
      attendanceFinalized: json['attendanceFinalized'] as bool? ?? false,
      series: json['series'] == null
          ? null
          : EventSeriesModel.fromJson(json['series'] as Map<String, dynamic>),
      targetTeams: (json['targetTeams'] as List<dynamic>? ?? [])
          .map((item) => EventTeam.fromJson(item as Map<String, dynamic>))
          .toList(),
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((item) => EventAttachment.fromJson(item as Map<String, dynamic>))
          .toList(),
      matchDetails: json['matchDetails'] == null
          ? null
          : MatchDetails.fromJson(
              json['matchDetails'] as Map<String, dynamic>,
            ),
      attendance: (json['attendance'] as List<dynamic>? ?? [])
          .map((item) => EventAttendance.fromJson(item as Map<String, dynamic>))
          .toList(),
      attendanceSummary: AttendanceSummary.fromJson(
        json['attendanceSummary'] as Map<String, dynamic>?,
      ),
      missingAttendance: (json['missingAttendance'] as List<dynamic>? ?? [])
          .map((item) => MissingAttendance.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList(),
      carpoolOffers: (json['carpoolOffers'] as List<dynamic>? ?? [])
          .map((item) => CarpoolOffer.fromJson(item as Map<String, dynamic>))
          .toList(),
      capabilities: EventCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>?,
      ),
    );
  }
}

class EventRecurrenceDraft {
  const EventRecurrenceDraft({
    required this.frequency,
    required this.until,
    this.interval = 1,
    this.weekdays = const [],
  });

  final RecurrenceFrequency frequency;
  final DateTime until;
  final int interval;
  final List<int> weekdays;

  DateTime get inclusiveUntil => DateTime(
        until.year,
        until.month,
        until.day,
        23,
        59,
        59,
        999,
      );

  Map<String, dynamic> toJson() => {
        'frequency': frequency.apiName,
        'until': inclusiveUntil.toUtc().toIso8601String(),
        'interval': interval,
        'weekdays': weekdays,
      };
}

class EventWriteData {
  const EventWriteData({
    required this.category,
    required this.title,
    required this.startAt,
    required this.location,
    required this.teamIds,
    this.endAt,
    this.meetingAt,
    this.meetingLocation,
    this.address,
    this.mapUrl,
    this.homeAway,
    this.opponent,
    this.opponentId,
    this.periodCount = 2,
    this.periodMinutes = 30,
    this.venue,
    this.contactName,
    this.contactPhone,
    this.description,
    this.equipment,
    this.clothing,
    this.catering,
    this.carpoolRequired = false,
    this.maxParticipants,
    this.responseDeadline,
    this.internalNote,
    this.visibility = EventVisibility.team,
    this.reminderMinutes = const [],
    this.reminderPushEnabled = true,
    this.attachmentName,
    this.attachmentUrl,
    this.recurrence,
    this.requestPitchConflictApprovals = false,
    this.pitchConflictMessage,
    this.participantPlayerIds,
    this.participantUserIds,
    this.notificationMode = EventNotificationMode.none,
  });

  final EventCategory category;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final DateTime? meetingAt;
  final String? meetingLocation;
  final String location;
  final String? address;
  final String? mapUrl;
  final HomeAway? homeAway;
  final String? opponent;
  final String? opponentId;
  final int periodCount;
  final int periodMinutes;
  final String? venue;
  final String? contactName;
  final String? contactPhone;
  final String? description;
  final String? equipment;
  final String? clothing;
  final String? catering;
  final bool carpoolRequired;
  final int? maxParticipants;
  final DateTime? responseDeadline;
  final String? internalNote;
  final EventVisibility visibility;
  final List<int> reminderMinutes;
  final bool reminderPushEnabled;
  final List<String> teamIds;
  final String? attachmentName;
  final String? attachmentUrl;
  final EventRecurrenceDraft? recurrence;
  final bool requestPitchConflictApprovals;
  final String? pitchConflictMessage;
  final List<String>? participantPlayerIds;
  final List<String>? participantUserIds;
  final EventNotificationMode notificationMode;

  Map<String, dynamic> toJson() => {
        'category': category.apiName,
        'title': title,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt?.toUtc().toIso8601String(),
        'meetingAt': meetingAt?.toUtc().toIso8601String(),
        'meetingLocation': meetingLocation,
        'location': location,
        'address': address,
        'mapUrl': mapUrl,
        'homeAway': homeAway?.apiName,
        'opponent': opponent,
        'opponentId': opponentId,
        'periodCount': periodCount,
        'periodMinutes': periodMinutes,
        'durationMinutes': periodCount * periodMinutes,
        'venue': venue,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'description': description,
        'equipment': equipment,
        'clothing': clothing,
        'catering': catering,
        'carpoolRequired': carpoolRequired,
        'maxParticipants': maxParticipants,
        'responseDeadline': responseDeadline?.toUtc().toIso8601String(),
        'internalNote': internalNote,
        'visibility': visibility.apiName,
        'reminderMinutes': reminderMinutes,
        'reminderPushEnabled': reminderPushEnabled,
        'teamIds': teamIds,
        'attachments': [
          if (attachmentName?.isNotEmpty == true &&
              attachmentUrl?.isNotEmpty == true)
            {
              'name': attachmentName,
              'url': attachmentUrl,
            },
        ],
        if (recurrence != null) 'recurrence': recurrence!.toJson(),
        'requestPitchConflictApprovals': requestPitchConflictApprovals,
        'pitchConflictMessage': pitchConflictMessage,
        if (participantPlayerIds != null)
          'participantPlayerIds': participantPlayerIds,
        if (participantUserIds != null)
          'participantUserIds': participantUserIds,
        'notificationMode': notificationMode.apiName,
      };
}
