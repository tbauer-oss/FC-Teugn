const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const {
  Permission,
  hasPermission,
  resolveEffectivePermissions,
} = require('../dist/src/security/permissions');
const { AccountStatus, Role } = require('../dist/src/types/enums');
const {
  generateOccurrences,
  icsEscape,
  icsDate,
} = require('../dist/src/controllers/events.controller');
const { RecurrenceFrequency } = require('@prisma/client');
const {
  AnnouncementAudience,
} = require('@prisma/client');
const {
  audienceVisible,
  canPermanentlyDeleteAnnouncement,
} = require('../dist/src/controllers/communications.controller');
const {
  summarizeMatchResults,
} = require('../dist/src/services/statistics.service');
const {
  canSelectStatisticsTeam,
  isDefensivePlayer,
  isStatisticsMatchFinished,
  resolveStatisticsTeamIds,
  statisticsMatchLifecycleScope,
} = require('../dist/src/controllers/statistics.controller');
const {
  calculateStandings,
} = require('../dist/src/controllers/competitions.controller');
const {
  competitionMatchChecksum,
  parseCompetitionSource,
} = require('../dist/src/services/competition-provider');
const {
  buildTransitionTeamPlans,
  nextAgeGroupCode,
} = require('../dist/src/services/season-transition');

test('team-independent pages resolve a valid context team', () => {
  const organization = fs.readFileSync(
    'src/controllers/organization.controller.ts',
    'utf8',
  );
  const trainings = fs.readFileSync(
    'src/controllers/trainings.controller.ts',
    'utf8',
  );
  assert.match(organization, /organizationContext[\s\S]*resolveContextTeamId\(user\)/);
  assert.match(organization, /createTeam[\s\S]*resolveContextTeamId\(user\)/);
  assert.match(trainings, /listPitchOccupancy[\s\S]*resolveContextTeamId\(req\.user!\)/);
});

test('player lists expose stored photos through protected media URLs', () => {
  const players = fs.readFileSync(
    'src/controllers/players.controller.ts',
    'utf8',
  );
  assert.match(
    players,
    /publicPlayerSelect[\s\S]*photoAsset:\s*\{[\s\S]*deletedAt:\s*true[\s\S]*photoUrl:\s*true/,
  );
  assert.match(
    players,
    /withCareerStatistics[\s\S]*mediaAssetUrl\(photoAsset\.id,\s*'12h'\)/,
  );
});
const {
  signAccessToken,
  signRefreshToken,
  signEmergencyAccessToken,
  verifyAccessToken,
  verifyEmergencyAccessToken,
  signMediaAccessToken,
  verifyMediaAccessToken,
  verifyRefreshToken,
} = require('../dist/src/lib/jwt');
const {
  checklistItems,
} = require('../dist/src/controllers/team-operations.controller');
const {
  canManageClubOccupancy,
  canManageRecreationalOccupancy,
} = require('../dist/src/controllers/trainings.controller');
const {
  baseFormationOf,
  canDeleteTeamRole,
  teamDisplayName,
  validFormation,
} = require('../dist/src/controllers/organization.controller');
const {
  canManageFormationRole,
  hasOrganizationWideTeamScope,
  roleScopedTeamIds,
  usesStaffTeamScope,
} = require('../dist/src/services/team-access');
const {
  selectPresentAttendance,
} = require('../dist/src/controllers/emergency.controller');
const {
  canHaveParentPlayerLinks,
  canLimitedManagerUpdateMember,
} = require('../dist/src/controllers/admin.controller');

test('access and refresh tokens use separate verifiable token classes', () => {
  const access = signAccessToken({ id: 'user-1' }, '5m');
  const refresh = signRefreshToken(
    { sessionId: 'session-1', userId: 'user-1', familyId: 'family-1' },
    '5m',
  );
  assert.equal(verifyAccessToken(access).id, 'user-1');
  assert.equal(verifyRefreshToken(refresh).sessionId, 'session-1');
  assert.throws(() => verifyRefreshToken(access));
  assert.throws(() => verifyAccessToken(refresh));
});

test('emergency tokens are short-lived, typed and scoped independently', () => {
  const emergency = signEmergencyAccessToken(
    { userId: 'user-1', eventId: 'event-1' },
    '5m',
  );
  const claims = verifyEmergencyAccessToken(emergency);
  assert.equal(claims.kind, 'emergency-access');
  assert.equal(claims.userId, 'user-1');
  assert.equal(claims.eventId, 'event-1');
  assert.throws(() => verifyAccessToken(emergency));
  assert.throws(() => verifyRefreshToken(emergency));
});

test('media tokens are typed, asset-scoped and independent from sessions', () => {
  const media = signMediaAccessToken({ assetId: 'asset-1' }, '5m');
  const claims = verifyMediaAccessToken(media);
  assert.equal(claims.kind, 'media-access');
  assert.equal(claims.assetId, 'asset-1');
  assert.throws(() => verifyAccessToken(media));
  assert.throws(() => verifyRefreshToken(media));
});

test('emergency presence prefers recorded attendance over prior confirmations', () => {
  const attendance = [
    { id: 'one', status: 'YES', actualAttendance: 'NO' },
    { id: 'two', status: 'NO', actualAttendance: 'YES' },
    { id: 'three', status: 'YES', actualAttendance: null },
  ];
  assert.deepEqual(
    selectPresentAttendance(attendance).map((item) => item.id),
    ['two'],
  );
  assert.deepEqual(
    selectPresentAttendance([
      { id: 'one', status: 'YES', actualAttendance: null },
      { id: 'two', status: 'NO', actualAttendance: null },
    ]).map((item) => item.id),
    ['one'],
  );
});

test('club administrators can manage the organization', () => {
  assert.equal(
    hasPermission(Role.CLUB_ADMIN, Permission.MANAGE_ORGANIZATION),
    true,
  );
});

test('formation variants accept a suffix and retain the numeric base', () => {
  assert.equal(baseFormationOf('2-3-1 · offensiv'), '2-3-1');
  assert.equal(validFormation('2-3-1 · mit LM/RM', 7), true);
  assert.equal(validFormation('2-2-1 · falsch', 7), false);
});

test('formation templates are editable only by the requested staff roles', () => {
  for (const role of [
    Role.SUPER_ADMIN,
    Role.CLUB_ADMIN,
    Role.COACH,
    Role.TRAINER,
    Role.ASSISTANT_COACH,
  ]) {
    assert.equal(canManageFormationRole(role), true, role);
  }
  for (const role of [
    Role.YOUTH_DIRECTOR,
    Role.TRAINER_ADMIN,
    Role.TEAM_MANAGER,
    Role.PARENT,
  ]) {
    assert.equal(canManageFormationRole(role), false, role);
  }
});

test('youth directors can manage club-wide training schedules', () => {
  assert.equal(
    hasPermission(Role.YOUTH_DIRECTOR, Permission.MANAGE_ORGANIZATION),
    true,
  );
  assert.equal(
    hasPermission(Role.YOUTH_DIRECTOR, Permission.MANAGE_TRAINING),
    true,
  );
});

test('system administrators always receive every defined permission', () => {
  for (const permission of Object.values(Permission)) {
    assert.equal(hasPermission(Role.SUPER_ADMIN, permission), true);
  }
});

test('system-admin member previews are read-only and resolve the approved target identity', () => {
  const middleware = fs.readFileSync('src/middleware/auth.ts', 'utf8');
  const routes = fs.readFileSync('src/routes/auth.routes.ts', 'utf8');
  assert.match(middleware, /x-view-as-user/);
  assert.match(middleware, /decoded\.role !== Role\.SUPER_ADMIN/);
  assert.match(middleware, /safePreviewMethods/);
  assert.match(middleware, /readOnlyPreview: true/);
  assert.match(middleware, /target\.status !== AccountStatus\.APPROVED/);
  assert.match(routes, /router\.get\('\/me', requireAuth, requireApproved, me\)/);
});

test('only club-wide roles see the complete organization structure', () => {
  assert.equal(hasOrganizationWideTeamScope(Role.SUPER_ADMIN), true);
  assert.equal(hasOrganizationWideTeamScope(Role.CLUB_ADMIN), true);
  assert.equal(hasOrganizationWideTeamScope(Role.YOUTH_DIRECTOR), true);
  assert.equal(hasOrganizationWideTeamScope(Role.TRAINER_ADMIN), false);
  assert.equal(hasOrganizationWideTeamScope(Role.COACH), false);
  assert.equal(hasOrganizationWideTeamScope(Role.TRAINER), false);
  assert.equal(hasOrganizationWideTeamScope(Role.ASSISTANT_COACH), false);
  assert.equal(hasOrganizationWideTeamScope(Role.TEAM_MANAGER), false);
});

test('trainer and assistant-coach team scope takes precedence over family links', () => {
  for (const role of [Role.COACH, Role.TRAINER, Role.ASSISTANT_COACH]) {
    assert.equal(usesStaffTeamScope(role), true, role);
    assert.deepEqual(
      roleScopedTeamIds(
        role,
        'team-e1',
        [
          { teamId: 'team-e1', role: Role.COACH },
          { teamId: 'team-e2', role: Role.ASSISTANT_COACH },
          { teamId: 'team-parent-only', role: Role.PARENT },
        ],
        ['team-parent-only'],
      ),
      ['team-e1', 'team-e2'],
      role,
    );
  }
});

test('parent team scope continues to follow linked children', () => {
  assert.equal(usesStaffTeamScope(Role.PARENT), false);
  assert.deepEqual(
    roleScopedTeamIds(Role.PARENT, 'team-e1', [], ['team-e1', 'team-e2']),
    ['team-e1', 'team-e2'],
  );
});

test('individual permission overrides deny first and can add missing rights', () => {
  const effective = resolveEffectivePermissions(Role.PARENT, [
    { permission: Permission.VIEW_TEAM, state: 'DENY' },
    { permission: Permission.MANAGE_EVENTS, state: 'ALLOW' },
  ]);
  assert.equal(effective.includes(Permission.VIEW_TEAM), false);
  assert.equal(effective.includes(Permission.MANAGE_EVENTS), true);
  assert.deepEqual(
    resolveEffectivePermissions(Role.SUPER_ADMIN, [
      { permission: Permission.MANAGE_ORGANIZATION, state: 'DENY' },
    ]),
    Object.values(Permission),
  );
});

test('clean-sheet eligibility recognizes goalkeepers and defenders only', () => {
  assert.equal(isDefensivePlayer('TW', null, false), true);
  assert.equal(isDefensivePlayer('IV', 'RM', false), true);
  assert.equal(isDefensivePlayer('ST', 'RA', false), false);
  assert.equal(isDefensivePlayer('ST', null, true), true);
});

test('league standings use points, goal difference and goals deterministically', () => {
  const standings = calculateStandings({
    pointsWin: 3,
    pointsDraw: 1,
    pointsLoss: 0,
    entries: [
      { id: 'teugn', displayName: 'FC Teugn E1', ownTeamId: 'team-e1' },
      { id: 'a', displayName: 'SV A E1', ownTeamId: null },
      { id: 'b', displayName: 'SV B E1', ownTeamId: null },
    ],
    matches: [
      { homeEntryId: 'teugn', awayEntryId: 'a', status: 'FINISHED', homeGoals: 2, awayGoals: 0 },
      { homeEntryId: 'b', awayEntryId: 'teugn', status: 'FINISHED', homeGoals: 1, awayGoals: 1 },
      { homeEntryId: 'a', awayEntryId: 'b', status: 'SCHEDULED', homeGoals: null, awayGoals: null },
    ],
  });
  assert.deepEqual(
    standings.map((row) => [row.name, row.points, row.goalDifference]),
    [
      ['FC Teugn E1', 4, 2],
      ['SV B E1', 1, 0],
      ['SV A E1', 0, -2],
    ],
  );
});

test('administrative and club roles can additionally be linked as parents', () => {
  for (const role of [
    Role.SUPER_ADMIN,
    Role.CLUB_ADMIN,
    Role.YOUTH_DIRECTOR,
    Role.COACH,
    Role.ASSISTANT_COACH,
    Role.TEAM_MANAGER,
    Role.PARENT,
    Role.READ_ONLY,
  ]) {
    assert.equal(canHaveParentPlayerLinks(role), true, role);
  }
  assert.equal(canHaveParentPlayerLinks(Role.PLAYER), false);
});

test('coaches can manage players and events but not the organization', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_PLAYERS), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_DOCUMENTS), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_EVENTS), true);
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_DEVELOPMENT),
    true,
  );
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_SENSITIVE_PLAYER),
    true,
  );
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_ORGANIZATION),
    false,
  );
});

test('parents can respond to attendance without changing team data', () => {
  assert.equal(
    hasPermission(Role.PARENT, Permission.RESPOND_ATTENDANCE),
    true,
  );
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_PLAYERS), false);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_DOCUMENTS), false);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_EVENTS), false);
  assert.equal(
    hasPermission(Role.PARENT, Permission.VIEW_SENSITIVE_PLAYER),
    false,
  );
});

test('read-only members cannot mutate data', () => {
  assert.equal(hasPermission(Role.READ_ONLY, Permission.VIEW_TEAM), true);
  assert.equal(hasPermission(Role.READ_ONLY, Permission.MANAGE_TEAM), false);
  assert.equal(
    hasPermission(Role.READ_ONLY, Permission.VIEW_SENSITIVE_PLAYER),
    false,
  );
});

test('registration lifecycle exposes all auditable account states', () => {
  assert.deepEqual(Object.values(AccountStatus), [
    'PENDING',
    'APPROVED',
    'REJECTED',
    'BLOCKED',
    'ARCHIVED',
  ]);
});

test('assistant coaches can document development but not edit medical data', () => {
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_DEVELOPMENT),
    true,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_SENSITIVE_PLAYER),
    false,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_MEMBERS),
    true,
  );
});

test('trainers can approve requested accounts but cannot disable or re-role them', () => {
  assert.equal(
    canLimitedManagerUpdateMember(
      AccountStatus.PENDING,
      Role.PARENT,
      AccountStatus.APPROVED,
      Role.PARENT,
    ),
    true,
  );
  assert.equal(
    canLimitedManagerUpdateMember(
      AccountStatus.APPROVED,
      Role.PARENT,
      AccountStatus.BLOCKED,
      Role.PARENT,
    ),
    false,
  );
  assert.equal(
    canLimitedManagerUpdateMember(
      AccountStatus.APPROVED,
      Role.PARENT,
      AccountStatus.APPROVED,
      Role.COACH,
    ),
    false,
  );
  assert.equal(
    canLimitedManagerUpdateMember(
      AccountStatus.PENDING,
      Role.COACH,
      AccountStatus.APPROVED,
      Role.COACH,
    ),
    true,
  );
  assert.equal(
    canLimitedManagerUpdateMember(
      AccountStatus.PENDING,
      Role.PARENT,
      AccountStatus.APPROVED,
      Role.COACH,
    ),
    false,
  );
});

test('matchday operations are restricted to assigned staff roles', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_LINEUPS),
    true,
  );
  assert.equal(
    hasPermission(Role.ASSISTANT_COACH, Permission.MANAGE_LIVE_TICKER),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.MANAGE_LINEUPS),
    false,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.MANAGE_LIVE_TICKER),
    false,
  );
  assert.equal(
    hasPermission(Role.PLAYER, Permission.MANAGE_LIVE_TICKER),
    false,
  );
});

test('training and statistics mutations remain staff-only', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_TRAINING), true);
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_STATISTICS), true);
  assert.equal(hasPermission(Role.PARENT, Permission.VIEW_PLAYER_STATS), true);
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_TRAINING), false);
  assert.equal(hasPermission(Role.PLAYER, Permission.MANAGE_STATISTICS), false);
});

test('statistics team selection is reserved for administrator roles', () => {
  assert.equal(canSelectStatisticsTeam(Role.SUPER_ADMIN), true);
  assert.equal(canSelectStatisticsTeam(Role.CLUB_ADMIN), true);
  assert.equal(canSelectStatisticsTeam(Role.TRAINER_ADMIN), true);
  assert.equal(canSelectStatisticsTeam(Role.YOUTH_DIRECTOR), true);
  assert.equal(canSelectStatisticsTeam(Role.COACH), false);
  assert.equal(canSelectStatisticsTeam(Role.TRAINER), false);
  assert.equal(canSelectStatisticsTeam(Role.PARENT), false);
  assert.equal(canSelectStatisticsTeam(Role.PLAYER), false);
});

test('statistics include every assigned team for non-admin users', () => {
  const accessible = ['team-registration', 'team-membership'];
  for (const role of [Role.COACH, Role.TRAINER, Role.PARENT, Role.PLAYER]) {
    assert.deepEqual(
      resolveStatisticsTeamIds(
        { role, teamId: 'team-registration' },
        accessible,
        ['team-membership'],
      ),
      ['team-registration', 'team-membership'],
    );
  }
});

test('statistics administrators can select one authorized team only', () => {
  const accessible = ['team-registration', 'team-selected'];
  assert.deepEqual(
    resolveStatisticsTeamIds(
      { role: Role.SUPER_ADMIN, teamId: 'team-registration' },
      accessible,
      ['team-selected'],
    ),
    ['team-selected'],
  );
  assert.equal(
    resolveStatisticsTeamIds(
      { role: Role.CLUB_ADMIN, teamId: 'team-registration' },
      accessible,
      ['team-outside-club'],
    ),
    null,
  );
});

test('statistics accept the ticker as authoritative lifecycle fallback', () => {
  assert.equal(
    isStatisticsMatchFinished({
      matchDetails: { status: 'PLANNED' },
      liveTicker: { status: 'FINISHED' },
    }),
    true,
  );
  assert.equal(
    isStatisticsMatchFinished({
      matchDetails: { status: 'PLANNED' },
      liveTicker: { status: 'NOT_STARTED' },
    }),
    false,
  );
  const lifecycle = statisticsMatchLifecycleScope();
  assert.equal(Array.isArray(lifecycle.OR), true);
  assert.equal(lifecycle.OR.length, 2);
});

test('team communications can only be sent by staff roles', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.SEND_ANNOUNCEMENTS),
    true,
  );
  assert.equal(
    hasPermission(Role.TEAM_MANAGER, Permission.SEND_ANNOUNCEMENTS),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.SEND_ANNOUNCEMENTS),
    false,
  );
  assert.equal(
    hasPermission(Role.PLAYER, Permission.SEND_ANNOUNCEMENTS),
    false,
  );
});

test('only the system administration can permanently delete announcements', () => {
  assert.equal(canPermanentlyDeleteAnnouncement(Role.SUPER_ADMIN), true);
  assert.equal(canPermanentlyDeleteAnnouncement(Role.CLUB_ADMIN), false);
  assert.equal(canPermanentlyDeleteAnnouncement(Role.YOUTH_DIRECTOR), false);
  assert.equal(canPermanentlyDeleteAnnouncement(Role.COACH), false);
});

test('announcement audiences are separated by member role', () => {
  assert.equal(
    audienceVisible(Role.PARENT, AnnouncementAudience.PARENTS),
    true,
  );
  assert.equal(
    audienceVisible(Role.PLAYER, AnnouncementAudience.PARENTS),
    false,
  );
  assert.equal(
    audienceVisible(Role.COACH, AnnouncementAudience.STAFF),
    true,
  );
  assert.equal(
    audienceVisible(Role.PARENT, AnnouncementAudience.STAFF),
    false,
  );
  assert.equal(
    audienceVisible(Role.PARENT, AnnouncementAudience.ALL_MEMBERS),
    true,
  );
});

test('competition imports are restricted to staff roles', () => {
  assert.equal(hasPermission(Role.COACH, Permission.MANAGE_IMPORTS), true);
  assert.equal(
    hasPermission(Role.TEAM_MANAGER, Permission.MANAGE_IMPORTS),
    true,
  );
  assert.equal(hasPermission(Role.PARENT, Permission.MANAGE_IMPORTS), false);
});

test('team operations are visible to members but mutable only by staff', () => {
  assert.equal(
    hasPermission(Role.COACH, Permission.MANAGE_TEAM_OPERATIONS),
    true,
  );
  assert.equal(
    hasPermission(Role.TEAM_MANAGER, Permission.MANAGE_TEAM_OPERATIONS),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.VIEW_TEAM_OPERATIONS),
    true,
  );
  assert.equal(
    hasPermission(Role.PARENT, Permission.MANAGE_TEAM_OPERATIONS),
    false,
  );
});

test('checklist templates discard empty items and preserve required flags', () => {
  assert.deepEqual(checklistItems([
    { title: 'Trikots prüfen', isRequired: true },
    'Bälle einladen',
    { title: '   ' },
    { title: 'Getränke', isRequired: false },
  ]), [
    { title: 'Trikots prüfen', position: 0, isRequired: true },
    { title: 'Bälle einladen', position: 1, isRequired: true },
    { title: 'Getränke', position: 3, isRequired: false },
  ]);
});

test('season transition advances youth age groups without changing A youth', () => {
  assert.equal(nextAgeGroupCode('G'), 'F');
  assert.equal(nextAgeGroupCode('E'), 'D');
  assert.equal(nextAgeGroupCode('A'), 'A');
});

test('team display names omit the number only for a single youth team', () => {
  assert.equal(teamDisplayName('E', 1, 1), 'E-Jugend');
  assert.equal(teamDisplayName('E', 2, 1), 'E2-Jugend');
  assert.equal(teamDisplayName('E', 1, 3), 'E1-Jugend');
  assert.equal(teamDisplayName('E', 2, 3), 'E2-Jugend');
  assert.equal(teamDisplayName('E', 3, 3), 'E3-Jugend');
});

test('only system administrators can delete teams', () => {
  assert.equal(canDeleteTeamRole(Role.SUPER_ADMIN), true);
  assert.equal(canDeleteTeamRole(Role.CLUB_ADMIN), false);
  assert.equal(canDeleteTeamRole(Role.YOUTH_DIRECTOR), false);
  assert.equal(canDeleteTeamRole(Role.TRAINER_ADMIN), false);
});

test('only system administrators can manage recreational pitch slots', () => {
  assert.equal(canManageRecreationalOccupancy(Role.SUPER_ADMIN), true);
  assert.equal(canManageRecreationalOccupancy(Role.CLUB_ADMIN), false);
  assert.equal(canManageRecreationalOccupancy(Role.YOUTH_DIRECTOR), false);
  assert.equal(canManageRecreationalOccupancy(Role.COACH), false);
});

test('club occupancy confirmations and senior slots are limited to leadership', () => {
  assert.equal(canManageClubOccupancy(Role.SUPER_ADMIN), true);
  assert.equal(canManageClubOccupancy(Role.CLUB_ADMIN), true);
  assert.equal(canManageClubOccupancy(Role.YOUTH_DIRECTOR), true);
  assert.equal(canManageClubOccupancy(Role.TRAINER_ADMIN), false);
  assert.equal(canManageClubOccupancy(Role.COACH), false);
});

test('season transition preview respects explicit team overrides', () => {
  const plans = buildTransitionTeamPlans(
    [
      {
        id: 'team-e1',
        teamNumber: 1,
        name: 'E1',
        shortName: 'E1',
        level: 'Kreisliga',
        ageGroup: { code: 'E', name: 'E-Jugend' },
        playerCount: 14,
        activePlayerCount: 12,
        staffCount: 3,
      },
    ],
    [
      {
        sourceTeamId: 'team-e1',
        targetAgeGroupCode: 'D',
        targetName: 'D2',
        includeStaff: false,
      },
    ],
  );
  assert.deepEqual(
    {
      targetAgeGroupCode: plans[0].targetAgeGroupCode,
      teamNumber: plans[0].teamNumber,
      targetName: plans[0].targetName,
      includePlayers: plans[0].includePlayers,
      includeStaff: plans[0].includeStaff,
      archivedPlayerCount: plans[0].archivedPlayerCount,
    },
    {
      targetAgeGroupCode: 'D',
      teamNumber: 1,
      targetName: 'D2',
      includePlayers: true,
      includeStaff: false,
      archivedPlayerCount: 2,
    },
  );
});

test('CSV competition provider normalizes German exports deterministically', () => {
  const rows = parseCompetitionSource(
    'CSV',
    [
      'Spielkennung;Datum;Uhrzeit;Gegner;Heimspiel;Wettbewerb;Ort',
      'bfv-4711;15.08.2026;10:30;SV Beispiel;ja;Kreisliga;Sportplatz Teugn',
    ].join('\n'),
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].match.externalId, 'bfv-4711');
  assert.equal(rows[0].match.opponent, 'SV Beispiel');
  assert.equal(rows[0].match.isHome, true);
  assert.equal(
    competitionMatchChecksum(rows[0].match),
    competitionMatchChecksum(rows[0].match),
  );
});

test('ICS competition provider requires events and preserves UID', () => {
  const rows = parseCompetitionSource(
    'ICS',
    [
      'BEGIN:VCALENDAR',
      'BEGIN:VEVENT',
      'UID:spiel-123@example.test',
      'DTSTART:20260822T090000Z',
      'SUMMARY:FC Teugn - TSV Muster',
      'LOCATION:Waldstadion',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n'),
  );
  assert.equal(rows[0].match.externalId, 'spiel-123@example.test');
  assert.equal(rows[0].match.opponent, 'TSV Muster');
  assert.equal(rows[0].match.isHome, true);
  assert.equal(rows[0].match.location, 'Waldstadion');
});

test('ICS competition provider converts Europe/Berlin summer time to UTC', () => {
  const rows = parseCompetitionSource(
    'ICS',
    [
      'BEGIN:VEVENT',
      'UID:spiel-sommer@example.test',
      'DTSTART;TZID=Europe/Berlin:20260822T110000',
      'SUMMARY:FC Teugn - TSV Sommer',
      'END:VEVENT',
    ].join('\r\n'),
  );
  assert.equal(rows[0].match.startAt, '2026-08-22T09:00:00.000Z');
});

test('team statistics summarize results, form and home-away records', () => {
  const summary = summarizeMatchResults([
    { ourGoals: 3, theirGoals: 1, result: 'WIN', isHome: true },
    { ourGoals: 1, theirGoals: 1, result: 'DRAW', isHome: false },
    { ourGoals: 0, theirGoals: 2, result: 'LOSS', isHome: false },
    { ourGoals: 2, theirGoals: 0, result: 'WIN', isHome: true },
  ]);
  assert.deepEqual(
    {
      matches: summary.matches,
      wins: summary.wins,
      draws: summary.draws,
      losses: summary.losses,
      goalsFor: summary.goalsFor,
      goalsAgainst: summary.goalsAgainst,
      winRate: summary.winRate,
      goalsPerMatch: summary.goalsPerMatch,
      home: summary.home,
      away: summary.away,
    },
    {
      matches: 4,
      wins: 2,
      draws: 1,
      losses: 1,
      goalsFor: 6,
      goalsAgainst: 4,
      winRate: 50,
      goalsPerMatch: 1.5,
      home: { matches: 2, wins: 2 },
      away: { matches: 2, wins: 0 },
    },
  );
  assert.deepEqual(summary.form, ['WIN', 'DRAW', 'LOSS', 'WIN']);
});

test('weekly and biweekly calendar series include the boundary occurrence', () => {
  const start = new Date('2026-08-03T16:00:00.000Z');
  const weekly = generateOccurrences(
    start,
    new Date('2026-08-24T16:00:00.000Z'),
    RecurrenceFrequency.WEEKLY,
    1,
    [],
  );
  const biweekly = generateOccurrences(
    start,
    new Date('2026-08-31T16:00:00.000Z'),
    RecurrenceFrequency.BIWEEKLY,
    1,
    [],
  );
  assert.deepEqual(
    weekly.map((value) => value.toISOString()),
    [
      '2026-08-03T16:00:00.000Z',
      '2026-08-10T16:00:00.000Z',
      '2026-08-17T16:00:00.000Z',
      '2026-08-24T16:00:00.000Z',
    ],
  );
  assert.equal(biweekly.length, 3);
});

test('custom calendar series supports selected weekdays and an interval', () => {
  const dates = generateOccurrences(
    new Date('2026-08-03T16:00:00.000Z'),
    new Date('2026-08-16T16:00:00.000Z'),
    RecurrenceFrequency.CUSTOM,
    1,
    [1, 3],
  );
  assert.deepEqual(
    dates.map((value) => value.toISOString().slice(0, 10)),
    ['2026-08-03', '2026-08-05', '2026-08-10', '2026-08-12'],
  );
});

test('calendar generation is bounded and ICS values are escaped safely', () => {
  const dates = generateOccurrences(
    new Date('2026-01-01T10:00:00.000Z'),
    new Date('2030-01-01T10:00:00.000Z'),
    RecurrenceFrequency.CUSTOM,
    1,
    [1, 2, 3, 4, 5, 6, 7],
  );
  assert.equal(dates.length, 120);
  assert.equal(icsEscape('FC, Teugn; A\\B\nTraining'), 'FC\\, Teugn\\; A\\\\B\\nTraining');
  assert.equal(
    icsDate(new Date('2026-08-03T16:00:00.123Z')),
    '20260803T160000Z',
  );
});
