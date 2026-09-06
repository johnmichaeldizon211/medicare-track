import { prisma } from "../../src/lib/prisma.js";

let databaseAvailable: Promise<boolean> | null = null;

export function isDatabaseAvailable() {
  databaseAvailable ??= (async () => {
    if (!process.env.DATABASE_URL) {
      return false;
    }

    try {
      await prisma.$queryRaw`SELECT 1`;
      return true;
    } catch {
      return false;
    }
  })();

  return databaseAvailable;
}
