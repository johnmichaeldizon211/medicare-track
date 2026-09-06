import { afterAll, beforeAll } from "vitest";

let prisma: { $connect: () => Promise<void>; $disconnect: () => Promise<void> } | null = null;
const hasDb = Boolean(process.env.DATABASE_URL);

beforeAll(async () => {
  if (!hasDb) {
    return;
  }

  const prismaModule = await import("../../src/lib/prisma.js");
  prisma = prismaModule.prisma;
  try {
    await prisma.$connect();
  } catch {
    prisma = null;
  }
});

afterAll(async () => {
  if (!prisma) {
    return;
  }

  await prisma.$disconnect();
});
