enum UserRole {
  superAdmin,
  clubAdmin,
  youthDirector,
  coach,
  assistantCoach,
  teamManager,
  trainerAdmin,
  trainer,
  parent,
  player,
  readOnly,
}

class MemberPermissionProfile {
  const MemberPermissionProfile({
    required this.userId,
    required this.rolePermissions,
    required this.effectivePermissions,
    required this.overrides,
  });

  final String userId;
  final Set<String> rolePermissions;
  final Set<String> effectivePermissions;
  final Map<String, String> overrides;

  factory MemberPermissionProfile.fromJson(Map<String, dynamic> json) =>
      MemberPermissionProfile(
        userId: json['id'] as String,
        rolePermissions: (json['rolePermissions'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
        effectivePermissions:
            (json['effectivePermissions'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toSet(),
        overrides: {
          for (final item
              in (json['permissionOverrides'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>())
            if (item['permission'] is String && item['state'] is String)
              item['permission'] as String: item['state'] as String,
        },
      );
}

enum AccountStatus { pending, approved, rejected, blocked, archived }

enum RegistrationReviewStatus { newRequest, inReview, needsInfo, completed }

String guardianRelationshipLabel(String value) => switch (value) {
      'MOTHER' => 'Mutter',
      'FATHER' => 'Vater',
      _ => 'Sorgeberechtigt',
    };

class AppUser {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final UserRole role;
  final AccountStatus status;
  final String teamId;
  final DateTime? createdAt;
  final List<UserTeamMembership> memberships;
  final List<UserParentPlayerLink> parentPlayers;
  final RegistrationRequestInfo? registrationRequest;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.role,
    required this.status,
    required this.teamId,
    this.createdAt,
    this.memberships = const [],
    this.parentPlayers = const [],
    this.registrationRequest,
  });

  bool get isTrainer => switch (role) {
        UserRole.superAdmin ||
        UserRole.clubAdmin ||
        UserRole.youthDirector ||
        UserRole.coach ||
        UserRole.assistantCoach ||
        UserRole.teamManager ||
        UserRole.trainerAdmin ||
        UserRole.trainer =>
          true,
        _ => false,
      };

  /// Teams that are relevant for the current account state.
  ///
  /// During registration, the selected teams are only a request and help the
  /// administration review the account. As soon as that review is finished,
  /// only the memberships saved by the approving person are authoritative.
  List<UserTeamMembership> get assignedTeams {
    final requestedTeams =
        registrationRequest?.requestedTeams ?? const <UserTeamMembership>[];
    if (status == AccountStatus.pending && requestedTeams.isNotEmpty) {
      return requestedTeams;
    }
    return memberships;
  }

  String get roleLabel => switch (role) {
        UserRole.superAdmin => 'Systemadministration',
        UserRole.clubAdmin => 'Vereinsadministration',
        UserRole.youthDirector => 'Jugendleitung',
        UserRole.coach || UserRole.trainer => 'Trainerteam',
        UserRole.assistantCoach => 'Co-Trainerteam',
        UserRole.teamManager => 'Teamorganisation',
        UserRole.trainerAdmin => 'Trainer-Administration',
        UserRole.parent => 'Elternteil',
        UserRole.player => 'Spieler',
        UserRole.readOnly => 'Lesender Zugriff',
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? 'PARENT';
    final status = json['status'] as String? ?? 'PENDING';
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      teamId: json['teamId'] as String? ?? '',
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      memberships: (json['memberships'] as List<dynamic>? ?? [])
          .map((item) =>
              UserTeamMembership.fromJson(item as Map<String, dynamic>))
          .toList(),
      parentPlayers: (json['parentLinks'] as List<dynamic>? ?? [])
          .map((item) =>
              UserParentPlayerLink.fromJson(item as Map<String, dynamic>))
          .toList(),
      registrationRequest: json['registrationRequest'] == null
          ? null
          : RegistrationRequestInfo.fromJson(
              json['registrationRequest'] as Map<String, dynamic>,
            ),
      role: switch (role) {
        'SUPER_ADMIN' => UserRole.superAdmin,
        'CLUB_ADMIN' => UserRole.clubAdmin,
        'YOUTH_DIRECTOR' => UserRole.youthDirector,
        'COACH' => UserRole.coach,
        'ASSISTANT_COACH' => UserRole.assistantCoach,
        'TEAM_MANAGER' => UserRole.teamManager,
        'TRAINER_ADMIN' => UserRole.trainerAdmin,
        'TRAINER' => UserRole.trainer,
        'PLAYER' => UserRole.player,
        'READ_ONLY' => UserRole.readOnly,
        _ => UserRole.parent,
      },
      status: accountStatusFromApi(status),
    );
  }
}

class UserParentPlayerLink {
  const UserParentPlayerLink({
    required this.playerId,
    required this.playerName,
    required this.teamId,
    required this.teamName,
    required this.ageGroupCode,
    required this.relationship,
    required this.isLegalGuardian,
    required this.canPickup,
    required this.receivesCommunication,
  });

  final String playerId;
  final String playerName;
  final String teamId;
  final String teamName;
  final String ageGroupCode;
  final String relationship;
  final bool isLegalGuardian;
  final bool canPickup;
  final bool receivesCommunication;

  factory UserParentPlayerLink.fromJson(Map<String, dynamic> json) {
    final player = json['player'] as Map<String, dynamic>? ?? const {};
    final team = player['team'] as Map<String, dynamic>? ?? const {};
    final ageGroup = team['ageGroup'] as Map<String, dynamic>? ?? const {};
    final firstName = player['firstName'] as String? ?? '';
    final lastName = player['lastName'] as String? ?? '';
    return UserParentPlayerLink(
      playerId: player['id'] as String? ?? '',
      playerName: '$firstName $lastName'.trim(),
      teamId: player['teamId'] as String? ?? team['id'] as String? ?? '',
      teamName: team['name'] as String? ?? '',
      ageGroupCode: ageGroup['code'] as String? ?? '',
      relationship: json['relationship'] as String? ?? 'GUARDIAN',
      isLegalGuardian: json['isLegalGuardian'] as bool? ?? true,
      canPickup: json['canPickup'] as bool? ?? true,
      receivesCommunication: json['receivesCommunication'] as bool? ?? true,
    );
  }
}

class UserTeamMembership {
  const UserTeamMembership({
    required this.teamId,
    required this.teamName,
    required this.ageGroupCode,
    required this.role,
    required this.status,
  });

  final String teamId;
  final String teamName;
  final String ageGroupCode;
  final UserRole role;
  final AccountStatus status;

  factory UserTeamMembership.fromJson(Map<String, dynamic> json) {
    final team = json['team'] as Map<String, dynamic>;
    final ageGroup = team['ageGroup'] as Map<String, dynamic>;
    return UserTeamMembership(
      teamId: team['id'] as String,
      teamName: team['name'] as String,
      ageGroupCode: ageGroup['code'] as String? ?? '',
      role: userRoleFromApi(json['role'] as String?),
      status: accountStatusFromApi(json['status'] as String?),
    );
  }
}

UserRole userRoleFromApi(String? role) => switch (role) {
      'SUPER_ADMIN' => UserRole.superAdmin,
      'CLUB_ADMIN' => UserRole.clubAdmin,
      'YOUTH_DIRECTOR' => UserRole.youthDirector,
      'COACH' => UserRole.coach,
      'ASSISTANT_COACH' => UserRole.assistantCoach,
      'TEAM_MANAGER' => UserRole.teamManager,
      'TRAINER_ADMIN' => UserRole.trainerAdmin,
      'TRAINER' => UserRole.trainer,
      'PLAYER' => UserRole.player,
      'READ_ONLY' => UserRole.readOnly,
      _ => UserRole.parent,
    };

AccountStatus accountStatusFromApi(String? status) => switch (status) {
      'APPROVED' => AccountStatus.approved,
      'REJECTED' => AccountStatus.rejected,
      'BLOCKED' => AccountStatus.blocked,
      'ARCHIVED' => AccountStatus.archived,
      _ => AccountStatus.pending,
    };

String accountStatusApi(AccountStatus status) => switch (status) {
      AccountStatus.pending => 'PENDING',
      AccountStatus.approved => 'APPROVED',
      AccountStatus.rejected => 'REJECTED',
      AccountStatus.blocked => 'BLOCKED',
      AccountStatus.archived => 'ARCHIVED',
    };

class RegistrationRequestInfo {
  const RegistrationRequestInfo({
    required this.id,
    required this.requestedRole,
    required this.reviewStatus,
    required this.requestedTeams,
    required this.history,
    required this.pushOptIn,
    this.childName,
    this.relationship,
    this.adminNote,
    this.applicantMessage,
  });

  final String id;
  final UserRole requestedRole;
  final RegistrationReviewStatus reviewStatus;
  final List<UserTeamMembership> requestedTeams;
  final List<RegistrationHistoryItem> history;
  final bool pushOptIn;
  final String? childName;
  final String? relationship;
  final String? adminNote;
  final String? applicantMessage;

  factory RegistrationRequestInfo.fromJson(Map<String, dynamic> json) =>
      RegistrationRequestInfo(
        id: json['id'] as String,
        requestedRole: userRoleFromApi(json['requestedRole'] as String?),
        reviewStatus: switch (json['reviewStatus'] as String?) {
          'IN_REVIEW' => RegistrationReviewStatus.inReview,
          'NEEDS_INFO' => RegistrationReviewStatus.needsInfo,
          'COMPLETED' => RegistrationReviewStatus.completed,
          _ => RegistrationReviewStatus.newRequest,
        },
        childName: json['childName'] as String?,
        relationship: json['relationship'] as String?,
        adminNote: json['adminNote'] as String?,
        applicantMessage: json['applicantMessage'] as String?,
        pushOptIn: json['pushOptIn'] as bool? ?? false,
        requestedTeams:
            (json['requestedTeams'] as List<dynamic>? ?? []).map((raw) {
          final wrapper = raw as Map<String, dynamic>;
          final team = wrapper['team'] as Map<String, dynamic>;
          return UserTeamMembership.fromJson({
            'team': team,
            'role': json['requestedRole'],
            'status': 'PENDING',
          });
        }).toList(),
        history: (json['history'] as List<dynamic>? ?? [])
            .map((raw) => RegistrationHistoryItem.fromJson(
                  raw as Map<String, dynamic>,
                ))
            .toList(),
      );
}

class RegistrationHistoryItem {
  const RegistrationHistoryItem({
    required this.createdAt,
    this.toStatus,
    this.toReviewStatus,
    this.note,
    this.actorName,
  });

  final DateTime createdAt;
  final AccountStatus? toStatus;
  final RegistrationReviewStatus? toReviewStatus;
  final String? note;
  final String? actorName;

  factory RegistrationHistoryItem.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    return RegistrationHistoryItem(
      createdAt: DateTime.parse(json['createdAt'] as String),
      toStatus: json['toStatus'] == null
          ? null
          : accountStatusFromApi(json['toStatus'] as String),
      toReviewStatus: switch (json['toReviewStatus'] as String?) {
        'NEW' => RegistrationReviewStatus.newRequest,
        'IN_REVIEW' => RegistrationReviewStatus.inReview,
        'NEEDS_INFO' => RegistrationReviewStatus.needsInfo,
        'COMPLETED' => RegistrationReviewStatus.completed,
        _ => null,
      },
      note: json['note'] as String?,
      actorName: actor?['name'] as String?,
    );
  }
}

String userRoleApi(UserRole role) => switch (role) {
      UserRole.superAdmin => 'SUPER_ADMIN',
      UserRole.clubAdmin => 'CLUB_ADMIN',
      UserRole.youthDirector => 'YOUTH_DIRECTOR',
      UserRole.coach || UserRole.trainer => 'COACH',
      UserRole.assistantCoach => 'ASSISTANT_COACH',
      UserRole.teamManager => 'TEAM_MANAGER',
      UserRole.trainerAdmin => 'TRAINER_ADMIN',
      UserRole.parent => 'PARENT',
      UserRole.player => 'PLAYER',
      UserRole.readOnly => 'READ_ONLY',
    };
