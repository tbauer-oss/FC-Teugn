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

  const password = await hashPassword('coach123');

  for (const c of coachesData) {
    await prisma.user.upsert({
      where: { email: c.email },
      update: {},
      create: {
        email: c.email,
        name: c.name,
        password,
        role: Role.COACH,
      },
    });
  }

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
