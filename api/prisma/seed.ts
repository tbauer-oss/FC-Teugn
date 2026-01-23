import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/lib/password';
import { AttendanceStatus, EventType, Role } from '../src/types/enums';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  const team = await prisma.team.upsert({
    where: { id: 'fc-teugn' },
    update: {},
    create: { id: 'fc-teugn', name: 'FC Teugn' },
  });

  const defaultPassword = await hashPassword('FC-Teugn_WEB!');

  const trainer = await prisma.user.upsert({
    where: { email: 'trainer@fc-teugn.local' },
    update: {},
    create: {
      email: 'trainer@fc-teugn.local',
      name: 'Tobias Bauer',
      password: defaultPassword,
      role: Role.TRAINER,
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
      teamId: team.id,
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
