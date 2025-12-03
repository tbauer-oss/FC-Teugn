import { PrismaClient, Role } from '@prisma/client';
import { hashPassword } from '../src/lib/password';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  const coachesData = [
    { email: 'tobias.bauer@fc-teugn.local', name: 'Tobias Bauer' },
    { email: 'michael.stark@fc-teugn.local', name: 'Michael Stark' },
    { email: 'andreas.wallner@fc-teugn.local', name: 'Andreas Wallner' },
  ];

  const defaultPassword = await hashPassword('FC-Teugn_WEB!');

  for (const c of coachesData) {
    await prisma.user.upsert({
      where: { email: c.email },
      update: {},
      create: {
        email: c.email,
        name: c.name,
        password: defaultPassword,
        role: Role.COACH,
      },
    });
  }

  const parent = await prisma.user.upsert({
    where: { email: 'eltern@fc-teugn.local' },
    update: {},
    create: {
      email: 'eltern@fc-teugn.local',
      name: 'Familie Muster',
      password: defaultPassword,
      role: Role.PARENT,
    },
  });

  const players = await prisma.$transaction([
    prisma.player.upsert({
      where: { id: 'player-1' },
      update: {},
      create: {
        id: 'player-1',
        firstName: 'Lena',
        lastName: 'Bauer',
        birthDate: new Date('2014-03-15'),
        gender: 'weiblich',
        position: 'Mittelfeld',
        shirtNumber: 8,
        team: 'E2',
        userLinks: { create: { userId: parent.id, relation: 'Elternteil' } },
      },
    }),
    prisma.player.upsert({
      where: { id: 'player-2' },
      update: {},
      create: {
        id: 'player-2',
        firstName: 'Finn',
        lastName: 'Stark',
        birthDate: new Date('2013-11-02'),
        gender: 'männlich',
        position: 'Sturm',
        shirtNumber: 9,
        team: 'E3',
      },
    }),
  ]);

  await prisma.training.createMany({
    data: [
      {
        date: new Date(),
        startTime: new Date(),
        endTime: new Date(Date.now() + 60 * 60 * 1000),
        location: 'Sportplatz Teugn A',
        note: 'Bitte 15 Minuten früher da sein.',
      },
      {
        date: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000),
        startTime: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000 + 18 * 60 * 60 * 1000),
        endTime: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000 + 19 * 60 * 60 * 1000),
        location: 'Kunstrasen Kelheim',
        note: 'Kunstrasen-Schuhe mitbringen.',
      },
    ],
  });

  const match = await prisma.match.create({
    data: {
      type: 'LEAGUE',
      date: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000),
      kickOff: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000 + 15 * 60 * 60 * 1000),
      location: 'Heim - Platz B',
      opponent: 'SV Ihrlerstein',
      isHome: true,
      competition: 'Liga',
      notes: 'Treffpunkt 45 Minuten vorher.',
    },
  });

  await prisma.matchRSVP.create({
    data: { matchId: match.id, playerId: players[0].id, status: 'YES' },
  });

  await prisma.event.create({
    data: {
      title: 'Saisonabschluss',
      date: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000),
      startTime: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000 + 17 * 60 * 60 * 1000),
      location: 'Vereinsheim',
      description: 'Grillen & Spiele mit Eltern und Kindern',
      rsvpEnabled: true,
      rsvps: { create: { userId: parent.id, status: 'YES' } },
    },
  });

  console.log('Seed finished.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
