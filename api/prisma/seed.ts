import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/lib/password';
import { AttendanceStatus, EventType, Role } from '../src/types/enums';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

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
    update: { ageGroupId: ageGroup.id },
    create: {
      id: 'fc-teugn',
      name: 'E1',
      shortName: 'E1',
      ageGroupId: ageGroup.id,
    },
  });

  const defaultPassword = await hashPassword('FC-Teugn_WEB!');

  const trainer = await prisma.user.upsert({
    where: { email: 'trainer@fc-teugn.local' },
    update: {},
    create: {
      email: 'trainer@fc-teugn.local',
      name: 'Max Beispiel',
      password: defaultPassword,
      role: Role.CLUB_ADMIN,
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
    update: {},
    create: {
      id: 'player-1',
      teamId: team.id,
      firstName: 'Lena',
      lastName: 'Bauer',
      birthDate: new Date('2014-03-15'),
    },
  });

  await prisma.player.upsert({
    where: { id: 'player-2' },
    update: {},
    create: {
      id: 'player-2',
      teamId: team.id,
      firstName: 'Finn',
      lastName: 'Stark',
      birthDate: new Date('2013-11-02'),
    },
  });

  await prisma.parentPlayerLink.upsert({
    where: { parentId_playerId: { parentId: parent.id, playerId: player.id } },
    update: {},
    create: { parentId: parent.id, playerId: player.id },
  });

  const event = await prisma.event.upsert({
    where: { id: 'event-1' },
    update: {},
    create: {
      id: 'event-1',
      teamId: team.id,
      type: EventType.TRAINING,
      title: 'Trainingseinheit',
      startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
      location: 'Sportplatz Teugn A',
      description: 'Bitte 15 Minuten früher da sein.',
    },
  });

  await prisma.attendance.upsert({
    where: { eventId_playerId: { eventId: event.id, playerId: player.id } },
    update: { status: AttendanceStatus.YES },
    create: { eventId: event.id, playerId: player.id, status: AttendanceStatus.YES },
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
