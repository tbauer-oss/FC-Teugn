import {
  EventCategory,
  EventVisibility,
  HomeAway,
  PrismaClient,
} from '@prisma/client';
import { hashPassword } from '../src/lib/password';
import { AttendanceStatus, EventType, Role } from '../src/types/enums';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  const configuredDemoPassword = process.env.DEMO_SEED_PASSWORD?.trim();
  if (process.env.APP_ENVIRONMENT === 'demo' && !configuredDemoPassword) {
    throw new Error(
      'DEMO_SEED_PASSWORD is required when seeding the isolated demo environment.',
    );
  }

  const club = await prisma.club.upsert({
    where: { name: 'FC Teugn' },
    update: {},
    create: {
      id: 'seed-club-fc-teugn',
      name: 'FC Teugn',
      shortName: 'FCT',
    },
  });
  const season = await prisma.season.upsert({
    where: { clubId_name: { clubId: club.id, name: '2026/27' } },
    update: { isActive: true },
    create: {
      id: 'seed-season-2026-2027',
      clubId: club.id,
      name: '2026/27',
      startDate: new Date('2026-07-01T00:00:00.000Z'),
      endDate: new Date('2027-06-30T23:59:59.000Z'),
      isActive: true,
    },
  });
  const ageGroup = await prisma.ageGroup.upsert({
    where: { seasonId_code: { seasonId: season.id, code: 'E' } },
    update: {},
    create: {
      id: 'seed-agegroup-e',
      seasonId: season.id,
      name: 'E-Jugend',
      code: 'E',
      sortOrder: 30,
    },
  });
  const team = await prisma.team.upsert({
    where: { id: 'fc-teugn' },
    update: {
      ageGroupId: ageGroup.id,
      teamNumber: 1,
      gameFormat: 'FOOTBALL_5',
    },
    create: {
      id: 'fc-teugn',
      teamNumber: 1,
      name: 'E1',
      shortName: 'E1',
      ageGroupId: ageGroup.id,
      gameFormat: 'FOOTBALL_5',
    },
  });
  const secondTeam = await prisma.team.upsert({
    where: { id: 'fc-teugn-e2' },
    update: {
      ageGroupId: ageGroup.id,
      teamNumber: 2,
      gameFormat: 'FOOTBALL_4',
    },
    create: {
      id: 'fc-teugn-e2',
      teamNumber: 2,
      name: 'E2',
      shortName: 'E2',
      ageGroupId: ageGroup.id,
      gameFormat: 'FOOTBALL_4',
    },
  });

  const defaultPassword = await hashPassword(
    configuredDemoPassword ?? 'FC-Teugn_WEB!',
  );

  const trainer = await prisma.user.upsert({
    where: { email: 'trainer@fc-teugn.local' },
    update: {},
    create: {
      email: 'trainer@fc-teugn.local',
      name: 'Max Beispiel',
      password: defaultPassword,
      role: Role.SUPER_ADMIN,
      status: 'APPROVED',
      teamId: team.id,
    },
  });

  const parent = await prisma.user.upsert({
    where: { email: 'eltern@fc-teugn.local' },
    update: {},
    create: {
      email: 'eltern@fc-teugn.local',
      name: 'Familie Muster',
      password: defaultPassword,
      role: Role.PARENT,
      status: 'APPROVED',
      teamId: team.id,
    },
  });

  await prisma.teamMembership.upsert({
    where: { userId_teamId: { userId: trainer.id, teamId: team.id } },
    update: { role: trainer.role, status: trainer.status },
    create: {
      userId: trainer.id,
      teamId: team.id,
      role: trainer.role,
      status: trainer.status,
    },
  });
  await prisma.teamMembership.upsert({
    where: { userId_teamId: { userId: parent.id, teamId: team.id } },
    update: { role: parent.role, status: parent.status },
    create: {
      userId: parent.id,
      teamId: team.id,
      role: parent.role,
      status: parent.status,
    },
  });

  const player = await prisma.player.upsert({
    where: { id: 'player-1' },
    update: {
      preferredName: 'Lena',
      position: 'Mittelfeld',
      secondaryPosition: 'Abwehr',
      dominantFoot: 'RIGHT',
      shirtNumber: 8,
      status: 'ACTIVE',
      joinedAt: new Date('2024-07-01'),
    },
    create: {
      id: 'player-1',
      clubId: club.id,
      teamId: team.id,
      firstName: 'Lena',
      lastName: 'Bauer',
      birthDate: new Date('2014-03-15'),
      preferredName: 'Lena',
      position: 'Mittelfeld',
      secondaryPosition: 'Abwehr',
      dominantFoot: 'RIGHT',
      shirtNumber: 8,
      joinedAt: new Date('2024-07-01'),
    },
  });

  const playerTwo = await prisma.player.upsert({
    where: { id: 'player-2' },
    update: {},
    create: {
      id: 'player-2',
      clubId: club.id,
      teamId: team.id,
      firstName: 'Finn',
      lastName: 'Stark',
      birthDate: new Date('2013-11-02'),
    },
  });
  await prisma.player.upsert({
    where: { id: 'player-3' },
    update: { teamId: secondTeam.id, status: 'ACTIVE' },
    create: {
      id: 'player-3',
      clubId: club.id,
      teamId: secondTeam.id,
      firstName: 'Mia',
      lastName: 'Reserve',
      birthDate: new Date('2015-06-10'),
      status: 'ACTIVE',
    },
  });

  await prisma.parentPlayerLink.upsert({
    where: { parentId_playerId: { parentId: parent.id, playerId: player.id } },
    update: { relationship: 'MOTHER', isLegalGuardian: true },
    create: {
      parentId: parent.id,
      playerId: player.id,
      relationship: 'MOTHER',
      isLegalGuardian: true,
    },
  });

  await prisma.playerMedicalProfile.upsert({
    where: { playerId: player.id },
    update: {},
    create: {
      playerId: player.id,
      allergies: 'Keine bekannt',
      emergencyNotes: 'Im Notfall zuerst den hinterlegten Kontakt anrufen.',
      updatedById: trainer.id,
    },
  });

  await prisma.playerEmergencyContact.upsert({
    where: { id: 'emergency-contact-1' },
    update: {},
    create: {
      id: 'emergency-contact-1',
      playerId: player.id,
      name: 'Familie Muster',
      relationship: 'Mutter',
      phone: '+49 170 0000000',
      priority: 1,
      isAuthorizedPickup: true,
    },
  });

  await prisma.playerDevelopmentNote.upsert({
    where: { id: 'development-note-1' },
    update: {},
    create: {
      id: 'development-note-1',
      playerId: player.id,
      authorId: trainer.id,
      category: 'TECHNIQUE',
      visibility: 'GUARDIANS_AND_STAFF',
      rating: 4,
      title: 'Ballmitnahme unter Druck',
      notes: 'Sehr gute Entwicklung bei der offenen Ballmitnahme.',
    },
  });

  await prisma.playerConsent.upsert({
    where: { playerId_type: { playerId: player.id, type: 'TEAM_PHOTO' } },
    update: {},
    create: {
      playerId: player.id,
      type: 'TEAM_PHOTO',
      status: 'GRANTED',
      grantedBy: parent.id,
      grantedAt: new Date(),
    },
  });

  const event = await prisma.event.upsert({
    where: { id: 'event-1' },
    update: {},
    create: {
      id: 'event-1',
      teamId: team.id,
      type: EventType.TRAINING,
      category: EventCategory.TRAINING,
      visibility: EventVisibility.TEAM,
      title: 'Techniktraining E-Jugend',
      startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
      meetingAt: new Date(Date.now() + 23.75 * 60 * 60 * 1000),
      location: 'Sportplatz Teugn A',
      address: 'Ringstraße 20, 93356 Teugn',
      description: 'Schwerpunkt Ballmitnahme und Umschaltspiel.',
      equipment: 'Fußballschuhe, Schienbeinschoner, Trinkflasche',
      clothing: 'Trainingsanzug und wetterfeste Jacke',
      responseDeadline: new Date(Date.now() + 12 * 60 * 60 * 1000),
      reminderMinutes: [1440, 120],
      carpoolRequired: false,
      targetTeams: { create: { teamId: team.id } },
    },
  });

  await prisma.attendance.upsert({
    where: { eventId_playerId: { eventId: event.id, playerId: player.id } },
    update: {
      status: AttendanceStatus.YES,
      respondedById: parent.id,
      respondedAt: new Date(),
    },
    create: {
      eventId: event.id,
      playerId: player.id,
      status: AttendanceStatus.YES,
      respondedById: parent.id,
      respondedAt: new Date(),
    },
  });

  const exercise = await prisma.trainingExercise.upsert({
    where: { id: 'exercise-rondo-1' },
    update: {},
    create: {
      id: 'exercise-rondo-1',
      teamId: team.id,
      createdById: trainer.id,
      title: 'Rondo mit Umschaltmoment',
      category: 'Technik & Wahrnehmung',
      ageGroups: ['E', 'D'],
      minPlayers: 6,
      maxPlayers: 12,
      durationMinutes: 15,
      materials: '8 Hütchen, 4 Leibchen, 2 Bälle',
      setup: 'Quadrat 14 × 14 Meter, zwei neutrale Außenspieler.',
      instructions:
        'Vier Spieler halten den Ball gegen zwei Verteidiger. Nach Ballgewinn sofort auf die Außenspieler umschalten.',
      coachingPoints: 'Vororientierung, offener erster Kontakt, direktes Gegenpressing.',
      variations: 'Kontaktbegrenzung oder zweites Quadrat ergänzen.',
      isFavorite: true,
    },
  });
  const trainingPlan = await prisma.trainingPlan.upsert({
    where: { eventId: event.id },
    update: {},
    create: {
      eventId: event.id,
      createdById: trainer.id,
      focusAreas: ['Ballmitnahme', 'Umschalten', 'Kommunikation'],
      learningGoals: 'Offene Ballmitnahme und schnelles Reagieren nach Ballverlust.',
      durationMinutes: 60,
      coaches: trainer.name,
      materials: 'Bälle, Leibchen, Hütchen, zwei Minitore',
      pitchSetup: 'Halber Platz, drei klar markierte Zonen.',
    },
  });
  await prisma.trainingPlanItem.deleteMany({ where: { trainingPlanId: trainingPlan.id } });
  await prisma.trainingPlanItem.createMany({
    data: [
      {
        trainingPlanId: trainingPlan.id,
        phase: 'WARM_UP',
        title: 'Fangspiel mit Ball',
        durationMinutes: 10,
        position: 0,
      },
      {
        trainingPlanId: trainingPlan.id,
        exerciseId: exercise.id,
        phase: 'MAIN_PART',
        title: exercise.title,
        durationMinutes: exercise.durationMinutes,
        position: 1,
      },
      {
        trainingPlanId: trainingPlan.id,
        phase: 'GAME_FORM',
        title: '4 gegen 4 auf Minitore',
        durationMinutes: 25,
        position: 2,
      },
      {
        trainingPlanId: trainingPlan.id,
        phase: 'COOL_DOWN',
        title: 'Teamkreis und Feedback',
        durationMinutes: 10,
        position: 3,
      },
    ],
  });

  const awayMatch = await prisma.event.upsert({
    where: { id: 'event-away-friendly' },
    update: {},
    create: {
      id: 'event-away-friendly',
      teamId: team.id,
      type: EventType.MATCH,
      category: EventCategory.FRIENDLY_MATCH,
      visibility: EventVisibility.TEAM,
      title: 'Testspiel gegen SV Saal',
      startAt: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + (4 * 24 + 2) * 60 * 60 * 1000),
      meetingAt: new Date(Date.now() + (4 * 24 - 1) * 60 * 60 * 1000),
      location: 'Sportgelände Saal',
      address: 'Lindenstraße 30, 93342 Saal an der Donau',
      opponent: 'SV Saal',
      homeAway: HomeAway.AWAY,
      venue: 'Hauptplatz',
      carpoolRequired: true,
      responseDeadline: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000),
      equipment: 'Trikot wird gestellt, Fußballschuhe, Schienbeinschoner',
      catering: 'Ausreichend Getränke mitbringen',
      reminderMinutes: [2880, 180],
      targetTeams: { create: { teamId: team.id } },
    },
  });
  await prisma.matchDetails.upsert({
    where: { eventId: awayMatch.id },
    update: {},
    create: {
      eventId: awayMatch.id,
      kind: 'FRIENDLY',
      status: 'CONFIRMED',
      opponent: 'SV Saal',
      isHome: false,
      competition: 'Vorbereitung',
      durationMinutes: 60,
      periodMinutes: 30,
      periodCount: 2,
    },
  });

  const pastMatch = await prisma.event.upsert({
    where: { id: 'event-past-match' },
    update: {},
    create: {
      id: 'event-past-match',
      teamId: team.id,
      type: EventType.MATCH,
      category: EventCategory.FRIENDLY_MATCH,
      visibility: EventVisibility.TEAM,
      title: 'Testspiel gegen TSV Beispiel',
      startAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() - (7 * 24 * 60 - 70) * 60 * 1000),
      location: 'Sportplatz Teugn A',
      opponent: 'TSV Beispiel',
      homeAway: HomeAway.HOME,
      targetTeams: { create: { teamId: team.id } },
    },
  });
  await prisma.matchDetails.upsert({
    where: { eventId: pastMatch.id },
    update: { status: 'FINISHED', ourGoals: 2, theirGoals: 1 },
    create: {
      eventId: pastMatch.id,
      kind: 'FRIENDLY',
      status: 'FINISHED',
      opponent: 'TSV Beispiel',
      isHome: true,
      competition: 'Vorbereitung',
      durationMinutes: 60,
      periodMinutes: 30,
      periodCount: 2,
      ourGoals: 2,
      theirGoals: 1,
    },
  });
  const squad = await prisma.squad.upsert({
    where: { eventId: pastMatch.id },
    update: {},
    create: {
      eventId: pastMatch.id,
      name: 'Spieltagskader',
      formation: '2-3-1',
      publishedAt: new Date(),
    },
  });
  await prisma.squadMember.createMany({
    data: [
      { squadId: squad.id, playerId: player.id, plannedMinutes: 60 },
      { squadId: squad.id, playerId: playerTwo.id, plannedMinutes: 45 },
    ],
    skipDuplicates: true,
  });
  await prisma.teamMatchStatistic.upsert({
    where: { eventId: pastMatch.id },
    update: { ourGoals: 2, theirGoals: 1, result: 'WIN', recalculatedAt: new Date() },
    create: {
      eventId: pastMatch.id,
      ourGoals: 2,
      theirGoals: 1,
      result: 'WIN',
      isHome: true,
    },
  });
  await prisma.playerMatchStatistic.upsert({
    where: { eventId_playerId: { eventId: pastMatch.id, playerId: player.id } },
    update: { appeared: true, started: true, minutesPlayed: 60, goals: 1, assists: 1 },
    create: {
      eventId: pastMatch.id,
      playerId: player.id,
      appeared: true,
      started: true,
      minutesPlayed: 60,
      goals: 1,
      assists: 1,
      isCaptain: true,
    },
  });

  console.log(`Seed finished for team ${team.name} with trainer ${trainer.name}.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
