const baseUrl = process.env.E2E_BASE_URL ?? 'http://localhost:4000';
const trainerEmail =
  process.env.E2E_TRAINER_EMAIL ?? 'trainer@fc-teugn.local';
const password = process.env.E2E_PASSWORD ?? 'FC-Teugn_WEB!';
const teamId = process.env.E2E_TEAM_ID ?? 'fc-teugn';
const playerId = process.env.E2E_PLAYER_ID ?? 'player-2';
const runId = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
const parentEmail = `e2e-parent-${runId}@example.invalid`;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers ?? {}),
    },
  });
  const body =
    response.status === 204
      ? null
      : await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(
      `${options.method ?? 'GET'} ${path}: ${response.status} ${JSON.stringify(body)}`,
    );
  }
  return body;
}

async function login(email) {
  const session = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  return session.accessToken;
}

const auth = (token) => ({ authorization: `Bearer ${token}` });
const json = (method, token, body) => ({
  method,
  headers: auth(token),
  body: JSON.stringify(body),
});

console.log(`E2E acceptance against ${baseUrl}`);

const status = await request('/');
assert(status.status === 'ok', 'API status is not ok');
const contract = await request('/openapi.json');
assert(contract.openapi === '3.1.0', 'OpenAPI contract missing');

const trainerToken = await login(trainerEmail);
const trainerContext = await request('/organization/context', {
  headers: auth(trainerToken),
});
assert(
  trainerContext.permissions.includes('MANAGE_EVENTS'),
  'Trainer lacks MANAGE_EVENTS',
);

const consentTexts = await request('/auth/consent-texts');
const privacy = consentTexts.find((item) => item.type === 'PRIVACY_POLICY');
const terms = consentTexts.find((item) => item.type === 'TERMS_OF_USE');
assert(privacy && terms, 'Active privacy and terms texts are required');

// 1. Elternteil registriert sich für die E1.
const registration = await request('/auth/register', {
  method: 'POST',
  body: JSON.stringify({
    firstName: 'E2E',
    lastName: 'Elternteil',
    email: parentEmail,
    password,
    role: 'PARENT',
    teamIds: [teamId],
    childName: 'E2E Kind',
    relationship: 'GUARDIAN',
    privacyAccepted: true,
    termsAccepted: true,
    privacyTextVersionId: privacy.id,
    termsTextVersionId: terms.id,
  }),
});
assert(registration.user.status === 'PENDING', 'Registration is not pending');

// 2. Admin prüft und genehmigt den Account.
const approval = await request(
  '/admin/approve',
  json('POST', trainerToken, {
    userId: registration.user.id,
    status: 'APPROVED',
    role: 'PARENT',
    teamIds: [teamId],
    reviewStatus: 'COMPLETED',
    adminNote: 'Automatisierte E2E-Abnahme',
  }),
);
assert(approval.status === 'APPROVED', 'Parent approval failed');

// 3. Admin ordnet das Elternteil einem Spieler zu.
await request(
  '/admin/assign-parent-player',
  json('POST', trainerToken, {
    parentId: registration.user.id,
    playerId,
    relationship: 'GUARDIAN',
    isLegalGuardian: true,
  }),
);

const [parentClientAToken, parentClientBToken] = await Promise.all([
  login(parentEmail),
  login(parentEmail),
]);
const parentContext = await request('/organization/context', {
  headers: auth(parentClientAToken),
});
assert(
  !parentContext.permissions.includes('MANAGE_EVENTS'),
  'Parent unexpectedly has MANAGE_EVENTS',
);

const now = Date.now();

// 4. Trainer erstellt ein Training.
const training = await request(
  '/events',
  json('POST', trainerToken, {
    title: `E2E Training ${runId}`,
    category: 'TRAINING',
    startAt: new Date(now + 86_400_000).toISOString(),
    endAt: new Date(now + 90_000_000).toISOString(),
    location: 'E2E Sportplatz',
    teamIds: [teamId],
    visibility: 'TEAM',
  }),
);
assert(training.id, 'Training creation failed');

// 5. Elternteil sagt für das Kind zu.
const attendance = await request(
  `/events/${training.id}/attendance`,
  json('POST', parentClientAToken, {
    playerId,
    status: 'YES',
  }),
);
assert(attendance.status === 'YES', 'Attendance reply failed');

// 6. Trainer erfasst Anwesenheit.
await request(
  `/events/${training.id}/attendance/actual`,
  json('PUT', trainerToken, {
    entries: [{ playerId, status: 'YES', note: 'E2E anwesend' }],
  }),
);

// 7. Trainer erstellt ein Spiel.
const match = await request(
  '/events',
  json('POST', trainerToken, {
    title: `E2E Spiel ${runId}`,
    category: 'FRIENDLY_MATCH',
    startAt: new Date(now + 172_800_000).toISOString(),
    endAt: new Date(now + 180_000_000).toISOString(),
    location: 'E2E Hauptplatz',
    opponent: 'E2E Gegner',
    homeAway: 'HOME',
    teamIds: [teamId],
    visibility: 'TEAM',
  }),
);
assert(match.id, 'Match creation failed');
await request(
  `/matches/${match.id}`,
  json('PUT', trainerToken, {
    opponent: 'E2E Gegner',
    isHome: true,
    kind: 'FRIENDLY',
    status: 'CONFIRMED',
    competition: 'E2E-Abnahme',
    durationMinutes: 60,
    periodMinutes: 30,
    periodCount: 2,
  }),
);
const editableMatch = await request(`/matches/${match.id}`, {
  headers: auth(trainerToken),
});
assert(
  editableMatch.eligiblePlayers.some((player) => player.id === 'player-1') &&
    editableMatch.eligiblePlayers.some((player) => player.id === playerId),
  'Match-specific eligible squad players are missing',
);

// 8. Trainer nominiert den Kader.
await request(
  `/matches/${match.id}/squad`,
  json('PUT', trainerToken, {
    name: 'E2E Spieltagskader',
    formation: '2-3-1',
    members: [
      { playerId: 'player-1', status: 'NOMINATED', plannedMinutes: 60 },
      { playerId, status: 'NOMINATED', plannedMinutes: 45 },
    ],
  }),
);
await request(`/matches/${match.id}/squad/publish`, {
  method: 'POST',
  headers: auth(trainerToken),
});

// 9. Trainer veröffentlicht die Aufstellung.
const lineup = await request(
  `/matches/${match.id}/lineup`,
  json('PUT', trainerToken, {
    formation: '2-3-1',
    fieldSize: 7,
    status: 'PUBLISHED',
    publicNote: 'E2E-Aufstellung',
    tacticalNote: 'Nur Trainer dürfen diese Notiz sehen.',
    positions: [
      {
        playerId: 'player-1',
        period: 1,
        positionCode: 'ZM',
        x: 0.5,
        y: 0.55,
        isStarter: true,
        isCaptain: true,
        shirtNumber: 8,
      },
      {
        playerId,
        period: 1,
        positionCode: 'ST',
        x: 0.5,
        y: 0.25,
        isStarter: true,
        shirtNumber: 9,
      },
    ],
  }),
);
assert(lineup.status === 'PUBLISHED', 'Lineup publication failed');

// 10. Trainer startet den Liveticker.
await request(
  `/matches/${match.id}/ticker/events`,
  json('POST', trainerToken, {
    clientEventId: `e2e-start-${runId}`,
    type: 'MATCH_START',
  }),
);

// 11. Trainer erfasst Tore; Idempotenz und Korrektur werden mitgeprüft.
const firstGoalId = `e2e-goal-1-${runId}`;
const firstGoal = await request(
  `/matches/${match.id}/ticker/events`,
  json('POST', trainerToken, {
    clientEventId: firstGoalId,
    type: 'HOME_GOAL',
    scorerId: 'player-1',
  }),
);
const duplicateGoal = await request(
  `/matches/${match.id}/ticker/events`,
  json('POST', trainerToken, {
    clientEventId: firstGoalId,
    type: 'HOME_GOAL',
    scorerId: 'player-1',
  }),
);
assert(duplicateGoal.duplicate === true, 'Ticker idempotency failed');
assert(
  duplicateGoal.ticker.ourGoals === firstGoal.ticker.ourGoals,
  'Duplicate ticker event changed the score',
);
await request(
  `/matches/${match.id}/ticker/undo`,
  json('POST', trainerToken, {
    clientEventId: `e2e-undo-${runId}`,
    comment: 'E2E-Korrektur',
  }),
);
await request(
  `/matches/${match.id}/ticker/events`,
  json('POST', trainerToken, {
    clientEventId: `e2e-goal-2-${runId}`,
    type: 'HOME_GOAL',
    scorerId: playerId,
    assistId: 'player-1',
  }),
);

// 12. Zwei unabhängige Eltern-Sitzungen sehen denselben neuen Live-Spielstand.
const initialA = await request(`/matches/${match.id}/ticker`, {
  headers: auth(parentClientAToken),
});
const initialB = await request(`/matches/${match.id}/ticker`, {
  headers: auth(parentClientBToken),
});
assert(
  initialA.lastSequence === initialB.lastSequence &&
    initialA.ourGoals === initialB.ourGoals,
  'Two clients disagree on the initial ticker state',
);
const nextGoal = await request(
  `/matches/${match.id}/ticker/events`,
  json('POST', trainerToken, {
    clientEventId: `e2e-goal-3-${runId}`,
    type: 'HOME_GOAL',
    scorerId: 'player-1',
  }),
);
const [updatedA, updatedB] = await Promise.all([
  request(`/matches/${match.id}/ticker?after=${initialA.lastSequence}`, {
    headers: auth(parentClientAToken),
  }),
  request(`/matches/${match.id}/ticker?after=${initialB.lastSequence}`, {
    headers: auth(parentClientBToken),
  }),
]);
for (const updated of [updatedA, updatedB]) {
  assert(
    updated.lastSequence === nextGoal.ticker.lastSequence &&
      updated.events.some(
        (event) => event.clientEventId === `e2e-goal-3-${runId}`,
      ),
    'A parent client did not receive the live update',
  );
}
const parentMatch = await request(`/matches/${match.id}`, {
  headers: auth(parentClientAToken),
});
assert(
  parentMatch.squads[0]?.lineup?.status === 'PUBLISHED',
  'Parent cannot see the published lineup',
);
assert(
  parentMatch.squads[0]?.lineup?.tacticalNote == null,
  'Private tactical note leaked to parent',
);

// 13. Trainer beendet das Spiel.
const finished = await request(
  `/matches/${match.id}/ticker/events`,
  json('POST', trainerToken, {
    clientEventId: `e2e-end-${runId}`,
    type: 'MATCH_END',
  }),
);
assert(finished.ticker.status === 'FINISHED', 'Match did not finish');

// 14. Statistiken werden aus dem abgeschlossenen Spiel aktualisiert.
await request(`/statistics/matches/${match.id}/recalculate`, {
  method: 'POST',
  headers: auth(trainerToken),
});
const statistics = await request('/statistics', {
  headers: auth(trainerToken),
});
const matchStatistic = statistics.matches.find((item) => item.id === match.id);
assert(matchStatistic, 'Finished match is missing from statistics');
assert(
  matchStatistic.ourGoals === finished.ticker.ourGoals &&
    matchStatistic.theirGoals === finished.ticker.theirGoals,
  'Statistics score differs from the final ticker score',
);
const scorerStatistic = statistics.players.find((item) => item.id === playerId);
const assistStatistic = statistics.players.find((item) => item.id === 'player-1');
assert(
  scorerStatistic?.goals >= 1,
  'Ticker scorer was not added to the player statistics',
);
assert(
  assistStatistic?.assists >= 1,
  'Ticker assist was not added to the player statistics',
);

console.log(
  'E2E acceptance passed: registration, approval, guardian link, training, attendance, match, squad, lineup, two-client ticker, correction and statistics',
);
