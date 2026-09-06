import type { Prisma, PrismaClient } from "@prisma/client";

export const DEFAULT_DAILY_CARE_TASKS = [
  {
    title: "Breakfast",
    type: "General Care",
    scheduledTime: "8:00 AM",
    frequency: "Daily"
  },
  {
    title: "Lunch",
    type: "General Care",
    scheduledTime: "12:00 PM",
    frequency: "Daily"
  },
  {
    title: "Dinner",
    type: "General Care",
    scheduledTime: "6:00 PM",
    frequency: "Daily"
  },
  {
    title: "Bathing / Hygiene",
    type: "General Care",
    scheduledTime: "9:00 AM",
    frequency: "Daily"
  }
] as const;

type CareTaskClient = Pick<PrismaClient, "careTask"> | Prisma.TransactionClient;

type EnsureOptions = {
  assignedCaregiverId?: string | null;
  createdById?: string | null;
};

export async function ensureDefaultDailyCareTasksForResident(
  db: CareTaskClient,
  residentId: string,
  options: EnsureOptions = {}
) {
  const existingTasks = await db.careTask.findMany({
    where: { residentId },
    select: { title: true }
  });
  const existingTitles = new Set(
    existingTasks.map((task) => task.title.trim().toUpperCase())
  );
  const missingTasks = DEFAULT_DAILY_CARE_TASKS.filter(
    (task) => !existingTitles.has(task.title)
  );

  if (missingTasks.length === 0) {
    return 0;
  }

  const result = await db.careTask.createMany({
    data: missingTasks.map((task) => ({
      residentId,
      title: task.title,
      type: task.type,
      scheduledTime: task.scheduledTime,
      frequency: task.frequency,
      assignedCaregiverId: options.assignedCaregiverId ?? null,
      createdById: options.createdById ?? null
    }))
  });

  return result.count;
}

export async function ensureDefaultDailyCareTasksForResidents(
  db: CareTaskClient,
  residentIds: string[],
  options: EnsureOptions = {}
) {
  let createdCount = 0;
  for (const residentId of residentIds) {
    createdCount += await ensureDefaultDailyCareTasksForResident(
      db,
      residentId,
      options
    );
  }
  return createdCount;
}
