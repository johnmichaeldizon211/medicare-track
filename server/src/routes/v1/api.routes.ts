import { CareTaskStatus, CaregiverActivityType, ConversationType, MedicationStatus, NotificationCategory, Prisma } from "@prisma/client";
import { Router } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma.js";
import { requireAuth } from "../../middleware/auth.js";
import { requireRole } from "../../middleware/rbac.js";
import { validateBody } from "../../middleware/validate.js";
import { asyncHandler } from "../../utils/async-handler.js";
import { AppError, ok } from "../../utils/api.js";
import { comparePassword, hashPassword } from "../../lib/password.js";
import { getIo } from "../../socket/index.js";
import { sendHighPriorityPush } from "../../services/push-notification.service.js";
import { logger } from "../../config/logger.js";

const assignCaregiverSchema = z.object({
  caregiverId: z.string().min(1)
});

const medicalNotesSchema = z.object({
  medicalNotes: z.string().min(1)
});

const createMedicationSchema = z.object({
  name: z.string().min(1),
  dosage: z.string().min(1),
  type: z.string().min(1),
  frequency: z.string().min(1),
  startDate: z.string().datetime(),
  duration: z.string().min(1),
  reminders: z.array(z.object({
    time: z.string().min(1),
    meal: z.string().min(1)
  })).min(1)
});

const updateMedicationSchema = createMedicationSchema;

const medicationStatusSchema = z.object({
  status: z.nativeEnum(MedicationStatus),
  remark: z.string().optional()
});

const careTaskStatusSchema = z.object({
  status: z.nativeEnum(CareTaskStatus),
  remark: z.string().optional()
});

const careTaskInputSchema = z.object({
  title: z.string().min(1),
  type: z.string().min(1),
  scheduledTime: z.string().min(1),
  frequency: z.string().min(1).default("Daily")
});

const createCareTaskSchema = careTaskInputSchema.extend({
  assignedCaregiverId: z.string().optional()
});

const createCareTasksBatchSchema = z.object({
  tasks: z.array(careTaskInputSchema).min(1).max(20),
  assignedCaregiverId: z.string().optional()
});

const updateCareTaskSchema = z.object({
  title: z.string().min(1),
  type: z.string().min(1),
  scheduledTime: z.string().min(1),
  frequency: z.string().min(1)
});

const updateProfileSchema = z.object({
  username: z.string().min(2).optional(),
  contactName: z.string().min(2).optional(),
  relationship: z.string().min(2).optional(),
  contactNumber: z.string().min(7).optional(),
  secondaryContactNumber: z.string().optional(),
  address: z.string().optional(),
  displayName: z.string().min(2).optional()
});

const updatePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(6)
});

const updateNotificationSchema = z.object({
  pushEnabled: z.boolean().optional(),
  soundEnabled: z.boolean().optional(),
  vibrationEnabled: z.boolean().optional(),
  medicationCareTaskRemindersEnabled: z.boolean().optional(),
  urgentAlertsEnabled: z.boolean().optional(),
  adminMessagesEnabled: z.boolean().optional()
});

const sendMessageSchema = z.object({
  content: z.string().min(1)
});

const pushTokenSchema = z.object({
  token: z.string().min(20).max(512),
  platform: z.enum(["android", "ios", "web"]).default("android")
});

const facilityInfoSchema = z.object({
  name: z.string().trim().min(1),
  contactNumber: z.string().trim().optional(),
  email: z.string().trim().email().optional().or(z.literal("")),
  address: z.string().trim().optional()
});

const createCaregiverSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  username: z.string().min(2),
  password: z.string().min(6)
});

const createMedicineInventorySchema = z.object({
  name: z.string().trim().min(1),
  count: z.number().int().min(0),
  expirationDate: z.string().datetime().nullable().optional()
});

const adjustMedicineInventorySchema = z.object({
  delta: z.number().int().refine((value) => value !== 0, {
    message: "Stock adjustment cannot be zero"
  })
});

const createPatientAccountSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  username: z.string().min(2),
  contactName: z.string().min(2),
  relationship: z.string().min(2),
  contactNumber: z.string().min(7),
  secondaryContactNumber: z.string().optional(),
  address: z.string().optional(),
  resident: z.object({
    name: z.string().min(2),
    room: z.string().min(1),
    age: z.number().int().min(1),
    birthday: z.string().optional(),
    gender: z.string().optional(),
    address: z.string().optional(),
    conditions: z.array(z.string()).optional()
  })
});

const adminUpdateUserSchema = z.object({
  email: z.string().email(),
  fullName: z.string().min(2),
  primaryContactNumber: z.string().optional(),
  secondaryContactNumber: z.string().optional(),
  address: z.string().optional(),
  relationship: z.string().optional(),
  resident: z.object({
    name: z.string().min(2),
    room: z.string().min(1),
    age: z.number().int().min(1),
    birthday: z.string().optional(),
    gender: z.string().optional(),
    address: z.string().optional(),
    conditions: z.array(z.string()).optional()
  }).optional()
});

async function getAccessibleResidentIds(auth: NonNullable<Express.Request["auth"]>) {
  if (auth.role === "ADMIN") {
    const all = await prisma.resident.findMany({ select: { id: true } });
    return all.map((r) => r.id);
  }

  if (auth.role === "CAREGIVER") {
    const assignments = await prisma.residentAssignment.findMany({
      where: {
        caregiverId: auth.userId,
        state: "ASSIGNED",
        unassignedAt: null
      },
      select: { residentId: true }
    });
    return Array.from(new Set(assignments.map((assignment) => assignment.residentId)));
  }

  const profile = await prisma.familyProfile.findUnique({
    where: { userId: auth.userId },
    select: { residentId: true }
  });

  return profile ? [profile.residentId] : [];
}

async function ensureResidentAccess(residentId: string, auth: NonNullable<Express.Request["auth"]>) {
  const allowedIds = await getAccessibleResidentIds(auth);
  if (!allowedIds.includes(residentId)) {
    throw new AppError(403, "Resident access forbidden", "FORBIDDEN");
  }
}

async function resolveCareTaskAssignee(residentId: string, assignedCaregiverId?: string) {
  let resolvedCaregiverId = assignedCaregiverId;
  if (!resolvedCaregiverId) {
    const assignment = await prisma.residentAssignment.findFirst({
      where: { residentId, state: "ASSIGNED", unassignedAt: null },
      select: { caregiverId: true }
    });
    resolvedCaregiverId = assignment?.caregiverId;
  }

  if (resolvedCaregiverId) {
    const caregiver = await prisma.user.findFirst({
      where: { id: resolvedCaregiverId, role: "CAREGIVER", status: "ACTIVE" },
      select: { id: true }
    });
    if (!caregiver) {
      throw new AppError(404, "Caregiver not found", "CAREGIVER_NOT_FOUND");
    }
  }

  return resolvedCaregiverId;
}

const URGENT_ALERT_WINDOW_MINUTES = 120;
const REMINDER_SCAN_INTERVAL_MS = 60_000;
const REMINDER_LOOKBACK_MS = 5 * 60_000;
const OVERDUE_ALERT_GRACE_MS = 5 * 60_000;
const MEDICINE_EXPIRATION_ALERT_WINDOW_DAYS = 30;

let reminderNotificationScheduler: NodeJS.Timeout | null = null;

function parseScheduledTimeParts(time: string) {
  const match = /^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$/i.exec(time.trim());
  if (!match) {
    return null;
  }

  const hourRaw = Number(match[1]);
  const minute = match[2] ? Number(match[2]) : 0;
  const modifier = match[3]?.toUpperCase();

  if (
    !Number.isInteger(hourRaw) ||
    !Number.isInteger(minute) ||
    minute < 0 ||
    minute > 59
  ) {
    return null;
  }

  if (modifier && (hourRaw < 1 || hourRaw > 12)) {
    return null;
  }

  if (!modifier && (hourRaw < 0 || hourRaw > 23)) {
    return null;
  }

  let hour = hourRaw;
  if (modifier === "PM" && hour < 12) hour += 12;
  if (modifier === "AM" && hour === 12) hour = 0;

  return { hour, minute };
}

function parseTimeToDate(base: Date, time: string) {
  const parsed = parseScheduledTimeParts(time);
  const hour = parsed?.hour ?? 0;
  const minute = parsed?.minute ?? 0;

  const scheduled = new Date(base);
  scheduled.setHours(hour, minute, 0, 0);
  return scheduled;
}

function getUrgentAlertExpiresAt(scheduledAt: Date) {
  return new Date(+scheduledAt + URGENT_ALERT_WINDOW_MINUTES * 60000);
}

function isCompletedTimelineStatus(status: MedicationStatus | CareTaskStatus | string) {
  return ["TAKEN", "DONE", "COMPLETED"].includes(status.toString().toUpperCase());
}

function isUrgentTimelineItem(status: MedicationStatus | CareTaskStatus | string, scheduledAt: Date, now = new Date()) {
  if (isCompletedTimelineStatus(status)) {
    return false;
  }

  return now >= scheduledAt && now <= getUrgentAlertExpiresAt(scheduledAt);
}

function isMedicationCompleted(events: { status: MedicationStatus }[]) {
  return events.length > 0 && events.every((event) => event.status === MedicationStatus.TAKEN);
}

function getTodayWindow(now = new Date()) {
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start, end };
}

function formatDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function minutesBetween(start: Date, end?: Date | null) {
  const resolvedEnd = end ?? new Date();
  return Math.max(0, Math.round((+resolvedEnd - +start) / 60000));
}

function hoursFromMinutes(minutes: number) {
  return Math.round((minutes / 60) * 10) / 10;
}

function firstQueryValue(value: unknown) {
  if (Array.isArray(value)) {
    return value[0];
  }
  return typeof value === "string" ? value : undefined;
}

function parseQueryDate(value: unknown, fieldName: string) {
  const raw = firstQueryValue(value);
  if (!raw) {
    return undefined;
  }

  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new AppError(400, `${fieldName} must be a valid date.`, "INVALID_DATE_RANGE");
  }
  return parsed;
}

function compactDetails(...parts: Array<string | null | undefined>) {
  const values = parts
    .map((part) => part?.trim())
    .filter((part): part is string => Boolean(part));
  return values.length > 0 ? values.join(" - ") : null;
}

const FACILITY_INFO_ID = "details";

function serializeFacilityInfo(info: {
  id: string;
  name: string;
  contactNumber: string | null;
  email: string | null;
  address: string | null;
  updatedAt: Date;
}) {
  return {
    id: info.id,
    name: info.name,
    contactNumber: info.contactNumber ?? "",
    email: info.email ?? "",
    address: info.address ?? "",
    updatedAt: info.updatedAt
  };
}

async function getFacilityInfo() {
  return prisma.facilityInfo.upsert({
    where: { id: FACILITY_INFO_ID },
    create: {
      id: FACILITY_INFO_ID,
      name: "Lifehouse Nursing Home"
    },
    update: {}
  });
}

function caregiverDisplayName(caregiver: {
  email: string;
  caregiverProfile?: { displayName: string } | null;
}) {
  return caregiver.caregiverProfile?.displayName || caregiver.email;
}

type TimeLogWithCaregiver = Prisma.CaregiverTimeLogGetPayload<{
  include: {
    caregiver: {
      include: {
        caregiverProfile: true;
      };
    };
  };
}>;

function serializeTimeLog(log: TimeLogWithCaregiver) {
  const totalMinutes = log.totalMinutes ?? minutesBetween(log.timeIn, log.timeOut);

  return {
    id: log.id,
    caregiverId: log.caregiverId,
    caregiverName: caregiverDisplayName(log.caregiver),
    caregiverEmail: log.caregiver.email,
    timeIn: log.timeIn,
    timeOut: log.timeOut,
    totalMinutes,
    totalHours: hoursFromMinutes(totalMinutes),
    isActive: log.timeOut === null
  };
}

type DailyCareTaskEvent = {
  id: string | null;
  careTaskId: string;
  residentId: string;
  status: CareTaskStatus;
  remark: string | null;
  timeCompleted: Date | null;
  updatedById: string | null;
  updatedAt: Date;
};

type CareTaskWithEvent = {
  id: string;
  residentId: string;
  scheduledTime: string;
  event: DailyCareTaskEvent | null;
};

function getDailyCareTaskEvent(task: CareTaskWithEvent, window = getTodayWindow()): DailyCareTaskEvent {
  if (task.event && task.event.updatedAt >= window.start && task.event.updatedAt < window.end) {
    return task.event;
  }

  return {
    id: null,
    careTaskId: task.id,
    residentId: task.residentId,
    status: CareTaskStatus.PENDING,
    remark: null,
    timeCompleted: null,
    updatedById: null,
    updatedAt: parseTimeToDate(window.start, task.scheduledTime)
  };
}

function withDailyCareTaskEvent<T extends CareTaskWithEvent>(task: T, window = getTodayWindow()) {
  return {
    ...task,
    event: getDailyCareTaskEvent(task, window)
  };
}

type ConversationPeer = {
  userId: string;
  type: ConversationType;
};

async function getActiveAdminIds() {
  const admins = await prisma.user.findMany({
    where: { role: "ADMIN", status: "ACTIVE" },
    select: { id: true }
  });

  return admins.map((admin) => admin.id);
}

async function getActiveCaregiverIds() {
  const caregivers = await prisma.user.findMany({
    where: { role: "CAREGIVER", status: "ACTIVE" },
    select: { id: true }
  });

  return caregivers.map((caregiver) => caregiver.id);
}

async function getActiveCaregiverIdsForResident(residentId: string) {
  const assignments = await prisma.residentAssignment.findMany({
    where: {
      residentId,
      state: "ASSIGNED",
      unassignedAt: null,
      caregiver: {
        role: "CAREGIVER",
        status: "ACTIVE"
      }
    },
    select: {
      caregiverId: true
    }
  });

  return Array.from(new Set(assignments.map((assignment) => assignment.caregiverId)));
}

async function getConversationPeersForResident(residentId: string): Promise<ConversationPeer[]> {
  const [assignments, familyProfile] = await Promise.all([
    prisma.residentAssignment.findMany({
      where: { residentId, state: "ASSIGNED", unassignedAt: null },
      select: {
        caregiver: {
          select: {
            id: true,
            role: true,
            status: true
          }
        }
      }
    }),
    prisma.familyProfile.findUnique({
      where: { residentId },
      select: {
        userId: true,
        user: {
          select: {
            role: true,
            status: true
          }
        }
      }
    })
  ]);

  const peers: ConversationPeer[] = [];

  for (const assignment of assignments) {
    const caregiver = assignment.caregiver;
    if (caregiver.role === "CAREGIVER" && caregiver.status === "ACTIVE") {
      peers.push({ userId: caregiver.id, type: ConversationType.CAREGIVER });
    }
  }

  if (
    familyProfile?.userId &&
    familyProfile.user.role === "FAMILY" &&
    familyProfile.user.status === "ACTIVE"
  ) {
    peers.push({ userId: familyProfile.userId, type: ConversationType.FAMILY });
  }

  return peers;
}

async function ensureConversationForResidentPeer(
  residentId: string,
  peer: ConversationPeer,
  adminIds: string[]
) {
  const conversationResidentId =
    peer.type === ConversationType.FAMILY ? residentId : null;

  const conversation = await prisma.conversation.upsert({
    where: {
      peerId_type: {
        peerId: peer.userId,
        type: peer.type
      }
    },
    create: {
      residentId: conversationResidentId,
      peerId: peer.userId,
      type: peer.type
    },
    update: {
      residentId: conversationResidentId
    }
  });

  const participantIds = Array.from(new Set([...adminIds, peer.userId]));
  if (participantIds.length === 0) {
    return conversation;
  }

  await prisma.conversationMember.deleteMany({
    where: {
      conversationId: conversation.id,
      userId: { notIn: participantIds }
    }
  });

  await prisma.conversationMember.createMany({
    data: participantIds.map((userId) => ({
      conversationId: conversation.id,
      userId
    })),
    skipDuplicates: true
  });

  return conversation;
}

async function ensureConversationMembersForResident(residentId: string) {
  const [adminIds, peers] = await Promise.all([
    getActiveAdminIds(),
    getConversationPeersForResident(residentId)
  ]);

  if (peers.length === 0) {
    return [];
  }

  return Promise.all(
    peers.map((peer) => ensureConversationForResidentPeer(residentId, peer, adminIds))
  );
}

type NotificationPrefs = {
  pushEnabled: boolean;
  medicationCareTaskRemindersEnabled: boolean;
  urgentAlertsEnabled: boolean;
  adminMessagesEnabled: boolean;
} | null;

function notificationAllowed(
  settings: NotificationPrefs,
  category: NotificationCategory
) {
  if (settings?.pushEnabled === false) {
    return false;
  }

  switch (category) {
    case NotificationCategory.MEDICATION_CARE_TASK:
      return settings?.medicationCareTaskRemindersEnabled ?? true;
    case NotificationCategory.URGENT_ALERT:
      return settings?.urgentAlertsEnabled ?? true;
    case NotificationCategory.ADMIN_MESSAGE:
      return settings?.adminMessagesEnabled ?? true;
    default:
      return true;
  }
}

async function notifyUsers({
  userIds,
  category,
  title,
  body,
  sourceKey,
  data,
  sendPushOnExisting = true
}: {
  userIds: string[];
  category: NotificationCategory;
  title: string;
  body: string;
  sourceKey: string;
  data?: Prisma.InputJsonValue;
  sendPushOnExisting?: boolean;
}) {
  const uniqueUserIds = Array.from(new Set(userIds.filter(Boolean)));
  if (uniqueUserIds.length === 0) {
    return [];
  }

  const recipients = await prisma.user.findMany({
    where: {
      id: { in: uniqueUserIds },
      status: "ACTIVE"
    },
    select: {
      id: true,
      notificationSetting: {
        select: {
          pushEnabled: true,
          medicationCareTaskRemindersEnabled: true,
          urgentAlertsEnabled: true,
          adminMessagesEnabled: true
        }
      }
    }
  });

  const notifications = [];
  for (const recipient of recipients) {
    if (!notificationAllowed(recipient.notificationSetting, category)) {
      continue;
    }

    const notificationSourceKey = `${sourceKey}:user:${recipient.id}`;
    const existingNotification =
      sendPushOnExisting
        ? null
        : await prisma.notification.findUnique({
            where: { sourceKey: notificationSourceKey },
            select: { id: true }
          });

    const notification = await prisma.notification.upsert({
      where: { sourceKey: notificationSourceKey },
      create: {
        userId: recipient.id,
        category,
        title,
        body,
        sourceKey: notificationSourceKey,
        data
      },
      update: {
        title,
        body,
        data
      }
    });

    notifications.push(notification);

    if (existingNotification && !sendPushOnExisting) {
      continue;
    }

    getIo()?.to(`user:${recipient.id}`).emit("notification:new", notification);

    const pushTokens = await prisma.devicePushToken.findMany({
      where: {
        userId: recipient.id,
        isActive: true
      },
      select: { token: true }
    });

    try {
      await sendHighPriorityPush({
        tokens: pushTokens.map((pushToken) => pushToken.token),
        title,
        body,
        data: {
          notificationId: notification.id,
          category,
          sourceKey: notification.sourceKey,
          ...(data && typeof data === "object" && !Array.isArray(data)
            ? data
            : {})
        }
      });
    } catch (error) {
      logger.warn({ err: error }, "Unable to deliver FCM push notification");
    }
  }

  return notifications;
}

async function getFamilyUserId(residentId: string) {
  const profile = await prisma.familyProfile.findUnique({
    where: { residentId },
    select: {
      userId: true,
      user: {
        select: {
          status: true
        }
      }
    }
  });

  return profile?.user.status === "ACTIVE" ? profile.userId : null;
}

async function notifyMedicationScheduleCreated(
  resident: { id: string; name: string; room: string },
  medication: { id: string; name: string; dosage: string; type: string }
) {
  const [caregiverIds, familyUserId] = await Promise.all([
    getActiveCaregiverIdsForResident(resident.id),
    getFamilyUserId(resident.id)
  ]);

  await Promise.all([
    notifyUsers({
      userIds: caregiverIds,
      category: NotificationCategory.MEDICATION_CARE_TASK,
      title: `New medication for ${resident.name}`,
      body: `${medication.name} ${compactDetails(medication.dosage, medication.type) ?? ""}`.trim(),
      sourceKey: `medication-created:${medication.id}:caregiver`,
      data: {
        trigger: "NEW_MEDICATION_SCHEDULE",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        medicationId: medication.id
      }
    }),
    notifyUsers({
      userIds: familyUserId ? [familyUserId] : [],
      category: NotificationCategory.MEDICATION_CARE_TASK,
      title: `New medication scheduled`,
      body: `New medication for ${resident.name}: ${medication.name}.`,
      sourceKey: `medication-created:${medication.id}:family`,
      data: {
        trigger: "NEW_MEDICATION_SCHEDULE",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        medicationId: medication.id
      }
    })
  ]);
}

async function notifyCareTaskCreated(
  resident: { id: string; name: string; room: string },
  task: { id: string; title: string; scheduledTime: string }
) {
  const [caregiverIds, familyUserId] = await Promise.all([
    getActiveCaregiverIdsForResident(resident.id),
    getFamilyUserId(resident.id)
  ]);

  await Promise.all([
    notifyUsers({
      userIds: caregiverIds,
      category: NotificationCategory.MEDICATION_CARE_TASK,
      title: `New Task for ${resident.name}`,
      body: `${task.title} scheduled for ${resident.name} at ${task.scheduledTime}.`,
      sourceKey: `care-task-created:${task.id}:caregiver`,
      data: {
        trigger: "NEW_CARE_TASK",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        careTaskId: task.id
      }
    }),
    notifyUsers({
      userIds: familyUserId ? [familyUserId] : [],
      category: NotificationCategory.MEDICATION_CARE_TASK,
      title: `New care task scheduled`,
      body: `${task.title} was scheduled for ${resident.name}.`,
      sourceKey: `care-task-created:${task.id}:family`,
      data: {
        trigger: "NEW_CARE_TASK",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        careTaskId: task.id
      }
    })
  ]);
}

async function notifyFamilyCareUpdate({
  resident,
  title,
  body,
  sourceKey,
  data
}: {
  resident: { id: string; name: string; room: string };
  title: string;
  body: string;
  sourceKey: string;
  data: Prisma.InputJsonValue;
}) {
  const familyUserId = await getFamilyUserId(resident.id);

  await notifyUsers({
    userIds: familyUserId ? [familyUserId] : [],
    category: NotificationCategory.MEDICATION_CARE_TASK,
    title,
    body,
    sourceKey,
    sendPushOnExisting: false,
    data
  });
}

function isDueReminderInWindow(scheduledAt: Date, now: Date, lookbackStart: Date) {
  return scheduledAt >= lookbackStart && scheduledAt <= now;
}

async function notifyMedicationReminderDue(event: {
  id: string;
  medicationId: string;
  residentId: string;
  scheduledAt: Date;
  medication: { name: string; dosage: string; type: string };
  resident: { id: string; name: string; room: string };
}) {
  const caregiverIds = await getActiveCaregiverIdsForResident(event.residentId);
  const details = compactDetails(event.medication.dosage, event.medication.type);

  await notifyUsers({
    userIds: caregiverIds,
    category: NotificationCategory.MEDICATION_CARE_TASK,
    title: `Medication due for ${event.resident.name}`,
    body: `${event.medication.name}${details ? ` - ${details}` : ""} is due now for ${event.resident.name}.`,
    sourceKey: `medication-reminder-due:${event.id}`,
    sendPushOnExisting: false,
    data: {
      trigger: "MEDICATION_REMINDER_DUE",
      residentId: event.resident.id,
      residentName: event.resident.name,
      room: event.resident.room,
      medicationId: event.medicationId,
      medicationEventId: event.id,
      scheduledAt: event.scheduledAt.toISOString()
    }
  });
}

async function notifyCareTaskReminderDue(task: {
  id: string;
  residentId: string;
  title: string;
  scheduledTime: string;
  resident: { id: string; name: string; room: string };
}, scheduledAt: Date, sourceDate: string) {
  const caregiverIds = await getActiveCaregiverIdsForResident(task.residentId);

  await notifyUsers({
    userIds: caregiverIds,
    category: NotificationCategory.MEDICATION_CARE_TASK,
    title: `Care task due for ${task.resident.name}`,
    body: `${task.title} is due now for ${task.resident.name}.`,
    sourceKey: `care-task-reminder-due:${task.id}:${sourceDate}`,
    sendPushOnExisting: false,
    data: {
      trigger: "CARE_TASK_REMINDER_DUE",
      residentId: task.resident.id,
      residentName: task.resident.name,
      room: task.resident.room,
      careTaskId: task.id,
      scheduledAt: scheduledAt.toISOString()
    }
  });
}

async function scanDueReminderNotifications(now = new Date()) {
  const lookbackStart = new Date(+now - REMINDER_LOOKBACK_MS);
  const todayWindow = getTodayWindow(now);
  const sourceDate = formatDateKey(todayWindow.start);

  const medicationEvents = await prisma.medicationEvent.findMany({
    where: {
      scheduledAt: { gte: lookbackStart, lte: now },
      status: MedicationStatus.PENDING
    },
    include: {
      medication: {
        select: { name: true, dosage: true, type: true }
      },
      resident: {
        select: { id: true, name: true, room: true }
      }
    }
  });

  await Promise.all(
    medicationEvents.map((event) => notifyMedicationReminderDue(event))
  );

  const careTasks = await prisma.careTask.findMany({
    include: {
      event: true,
      resident: {
        select: { id: true, name: true, room: true }
      }
    }
  });

  await Promise.all(
    careTasks
      .filter((task) => {
        const event = getDailyCareTaskEvent(task, todayWindow);
        const scheduledAt = parseTimeToDate(todayWindow.start, task.scheduledTime);
        return (
          event.status === CareTaskStatus.PENDING &&
          isDueReminderInWindow(scheduledAt, now, lookbackStart)
        );
      })
      .map((task) =>
        notifyCareTaskReminderDue(
          task,
          parseTimeToDate(todayWindow.start, task.scheduledTime),
          sourceDate
        )
      )
  );
}

async function scanUrgentAlertNotifications(now = new Date()) {
  const overdueCutoff = new Date(+now - OVERDUE_ALERT_GRACE_MS);
  const todayWindow = getTodayWindow(now);
  const sourceDate = formatDateKey(todayWindow.start);

  const medicationEvents = await prisma.medicationEvent.findMany({
    where: {
      scheduledAt: { gte: todayWindow.start, lte: overdueCutoff },
      status: {
        in: [
          MedicationStatus.PENDING,
          MedicationStatus.DELAYED,
          MedicationStatus.MISSED
        ]
      }
    },
    select: { id: true, status: true }
  });

  await Promise.all(
    medicationEvents.map((event) =>
      notifyMedicationAlert(
        event.id,
        event.status === MedicationStatus.MISSED ? "missed" : "overdue"
      )
    )
  );

  const careTasks = await prisma.careTask.findMany({
    include: { event: true }
  });

  await Promise.all(
    careTasks
      .filter((task) => {
        const event = getDailyCareTaskEvent(task, todayWindow);
        const scheduledAt = parseTimeToDate(todayWindow.start, task.scheduledTime);
        return event.status !== CareTaskStatus.DONE && scheduledAt <= overdueCutoff;
      })
      .map((task) =>
        notifyCareTaskAlert(
          {
            id: task.id,
            residentId: task.residentId,
            title: task.title,
            scheduledTime: task.scheduledTime
          },
          sourceDate,
          getDailyCareTaskEvent(task, todayWindow).status === CareTaskStatus.SKIPPED
            ? "skipped"
            : "missed"
        )
      )
  );
}

function daysUntilDate(date: Date, today = getTodayWindow().start) {
  const targetDay = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  return Math.floor((+targetDay - +today) / 86_400_000);
}

function formatShortDate(date: Date) {
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    year: "numeric"
  }).format(date);
}

async function notifyMedicineExpirationAlert(
  item: { id: string; name: string; expirationDate: Date | null },
  adminIds: string[],
  today: Date
) {
  if (!item.expirationDate) {
    return;
  }

  const days = daysUntilDate(item.expirationDate, today);
  if (days > MEDICINE_EXPIRATION_ALERT_WINDOW_DAYS) {
    return;
  }

  const expired = days < 0;
  const title = expired
    ? "Medicine expired"
    : days === 0
      ? "Medicine expires today"
      : "Medicine expiring soon";
  const body = expired
    ? `${item.name} expired on ${formatShortDate(item.expirationDate)}.`
    : `${item.name} expires on ${formatShortDate(item.expirationDate)} (${days} day${days === 1 ? "" : "s"} left).`;

  await notifyUsers({
    userIds: adminIds,
    category: NotificationCategory.URGENT_ALERT,
    title,
    body,
    sourceKey: `medicine-expiration:${item.id}:${formatDateKey(item.expirationDate)}`,
    sendPushOnExisting: false,
    data: {
      trigger: "MEDICINE_EXPIRATION",
      medicineId: item.id,
      medicineName: item.name,
      expirationDate: item.expirationDate.toISOString(),
      daysUntilExpiration: days
    }
  });
}

async function scanMedicineExpirationNotifications(now = new Date()) {
  const todayWindow = getTodayWindow(now);
  const alertEnd = new Date(todayWindow.start);
  alertEnd.setDate(alertEnd.getDate() + MEDICINE_EXPIRATION_ALERT_WINDOW_DAYS);
  alertEnd.setHours(23, 59, 59, 999);

  const [adminIds, items] = await Promise.all([
    getActiveAdminIds(),
    prisma.medicineInventoryItem.findMany({
      where: {
        expirationDate: {
          not: null,
          lte: alertEnd
        }
      },
      select: {
        id: true,
        name: true,
        expirationDate: true
      }
    })
  ]);

  await Promise.all(
    items.map((item) =>
      notifyMedicineExpirationAlert(item, adminIds, todayWindow.start)
    )
  );
}

async function runScheduledNotificationScan() {
  try {
    await scanDueReminderNotifications();
    await scanUrgentAlertNotifications();
    await scanMedicineExpirationNotifications();
  } catch (error) {
    logger.warn({ err: error }, "Scheduled notification scan failed");
  }
}

export function startReminderNotificationScheduler() {
  if (reminderNotificationScheduler) {
    return;
  }

  void runScheduledNotificationScan();
  reminderNotificationScheduler = setInterval(
    () => void runScheduledNotificationScan(),
    REMINDER_SCAN_INTERVAL_MS
  );
  reminderNotificationScheduler.unref?.();
  logger.info("Medication, care task, and urgent alert notification scheduler started");
}

async function notifyMedicationAlert(eventId: string, statusLabel = "overdue") {
  const event = await prisma.medicationEvent.findUnique({
    where: { id: eventId },
    include: {
      medication: true,
      resident: true
    }
  });
  if (!event) {
    return;
  }

  const [adminIds, caregiverIds, familyUserId] = await Promise.all([
    getActiveAdminIds(),
    getActiveCaregiverIdsForResident(event.residentId),
    getFamilyUserId(event.residentId)
  ]);

  const residentLabel = `${event.resident.name} (Room ${event.resident.room})`;
  await Promise.all([
    notifyUsers({
      userIds: adminIds,
      category: NotificationCategory.URGENT_ALERT,
      title: `ALERT: ${residentLabel}`,
      body: `ALERT: ${residentLabel} ${statusLabel} scheduled medication: ${event.medication.name}.`,
      sourceKey: `medication-alert:${event.id}:admin:${statusLabel}`,
      sendPushOnExisting: false,
      data: {
        trigger: "OVERDUE_MEDICATION",
        residentId: event.residentId,
        residentName: event.resident.name,
        room: event.resident.room,
        medicationEventId: event.id,
        medicationId: event.medicationId,
        status: event.status
      }
    }),
    notifyUsers({
      userIds: caregiverIds,
      category: NotificationCategory.URGENT_ALERT,
      title: `Urgent medication for ${event.resident.name}`,
      body: `${event.resident.name} has an ${statusLabel} medication: ${event.medication.name}.`,
      sourceKey: `medication-alert:${event.id}:caregiver:${statusLabel}`,
      sendPushOnExisting: false,
      data: {
        trigger: "OVERDUE_MEDICATION",
        residentId: event.residentId,
        residentName: event.resident.name,
        room: event.resident.room,
        medicationEventId: event.id,
        medicationId: event.medicationId,
        status: event.status
      }
    }),
    notifyUsers({
      userIds: familyUserId ? [familyUserId] : [],
      category: NotificationCategory.URGENT_ALERT,
      title: `Urgent update for ${event.resident.name}`,
      body: `${event.resident.name} has an ${statusLabel} medication update: ${event.medication.name}.`,
      sourceKey: `medication-alert:${event.id}:family:${statusLabel}`,
      sendPushOnExisting: false,
      data: {
        trigger: "OVERDUE_MEDICATION",
        residentId: event.residentId,
        residentName: event.resident.name,
        room: event.resident.room,
        medicationEventId: event.id,
        medicationId: event.medicationId,
        status: event.status
      }
    })
  ]);
}

async function notifyCareTaskAlert(
  task: { id: string; residentId: string; title: string; scheduledTime: string },
  sourceDate: string,
  statusLabel = "missed"
) {
  const resident = await prisma.resident.findUnique({ where: { id: task.residentId } });
  if (!resident) {
    return;
  }

  const [adminIds, caregiverIds, familyUserId] = await Promise.all([
    getActiveAdminIds(),
    getActiveCaregiverIdsForResident(task.residentId),
    getFamilyUserId(task.residentId)
  ]);

  const residentLabel = `${resident.name} (Room ${resident.room})`;
  await Promise.all([
    notifyUsers({
      userIds: adminIds,
      category: NotificationCategory.URGENT_ALERT,
      title: `ALERT: ${residentLabel}`,
      body: `ALERT: ${residentLabel} ${statusLabel} care task: ${task.title}.`,
      sourceKey: `care-task-alert:${task.id}:${sourceDate}:admin:${statusLabel}`,
      sendPushOnExisting: false,
      data: {
        trigger: "MISSED_CARE_TASK",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        careTaskId: task.id
      }
    }),
    notifyUsers({
      userIds: caregiverIds,
      category: NotificationCategory.URGENT_ALERT,
      title: `Urgent care task for ${resident.name}`,
      body: `${resident.name} has a ${statusLabel} care task: ${task.title}.`,
      sourceKey: `care-task-alert:${task.id}:${sourceDate}:caregiver:${statusLabel}`,
      sendPushOnExisting: false,
      data: {
        trigger: "MISSED_CARE_TASK",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        careTaskId: task.id
      }
    }),
    notifyUsers({
      userIds: familyUserId ? [familyUserId] : [],
      category: NotificationCategory.URGENT_ALERT,
      title: `Urgent update for ${resident.name}`,
      body: `${resident.name} has a ${statusLabel} care task update: ${task.title}.`,
      sourceKey: `care-task-alert:${task.id}:${sourceDate}:family:${statusLabel}`,
      sendPushOnExisting: false,
      data: {
        trigger: "MISSED_CARE_TASK",
        residentId: resident.id,
        residentName: resident.name,
        room: resident.room,
        careTaskId: task.id
      }
    })
  ]);
}

async function notifyAdminMessage(conversationId: string, messageId: string, content: string) {
  const conversation = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: {
      resident: true,
      peer: {
        select: {
          id: true,
          role: true,
          status: true
        }
      }
    }
  });

  if (!conversation || conversation.peer.status !== "ACTIVE") {
    return;
  }

  let resident = conversation.resident;
  if (!resident && conversation.type === ConversationType.CAREGIVER) {
    resident = await prisma.resident.findFirst({
      where: {
        assignments: {
          some: {
            caregiverId: conversation.peerId,
            state: "ASSIGNED",
            unassignedAt: null
          }
        }
      },
      orderBy: { name: "asc" }
    });
  }

  const residentName = resident?.name ?? "assigned resident";
  const room = resident?.room ?? "";
  const preview = content.length > 120 ? `${content.slice(0, 117)}...` : content;

  await notifyUsers({
    userIds: [conversation.peerId],
    category: NotificationCategory.ADMIN_MESSAGE,
    title: `Admin message for ${residentName}`,
    body: room
      ? `Admin message for ${residentName} (Room ${room}): ${preview}`
      : `Admin message for ${residentName}: ${preview}`,
    sourceKey: `admin-message:${messageId}`,
    data: {
      trigger: "ADMIN_MESSAGE",
      conversationId,
      messageId,
      residentId: resident?.id ?? null,
      residentName,
      room
    }
  });
}

async function getNotificationResidentIds(auth: NonNullable<Express.Request["auth"]>) {
  return getAccessibleResidentIds(auth);
}

async function syncDueNotifications(auth: NonNullable<Express.Request["auth"]>) {
  const residentIds = await getNotificationResidentIds(auth);
  if (residentIds.length === 0) {
    return;
  }

  const now = new Date();
  const window = getTodayWindow(now);
  const sourceDate = formatDateKey(window.start);

  const medicationEvents = await prisma.medicationEvent.findMany({
    where: {
      residentId: { in: residentIds },
      scheduledAt: { gte: window.start, lte: now },
      status: { in: [MedicationStatus.PENDING, MedicationStatus.DELAYED, MedicationStatus.MISSED] }
    },
    select: { id: true, status: true }
  });

  await Promise.all(
    medicationEvents.map((event) =>
      notifyMedicationAlert(
        event.id,
        event.status === MedicationStatus.MISSED ? "missed" : "overdue"
      )
    )
  );

  const careTasks = await prisma.careTask.findMany({
    where: { residentId: { in: residentIds } },
    include: { event: true }
  });

  await Promise.all(
    careTasks
      .filter((task) => {
        const event = getDailyCareTaskEvent(task, window);
        const scheduledAt = parseTimeToDate(window.start, task.scheduledTime);
        return event.status !== CareTaskStatus.DONE && scheduledAt <= now;
      })
      .map((task) =>
        notifyCareTaskAlert(
          {
            id: task.id,
            residentId: task.residentId,
            title: task.title,
            scheduledTime: task.scheduledTime
          },
          sourceDate,
          getDailyCareTaskEvent(task, window).status === CareTaskStatus.SKIPPED
            ? "skipped"
            : "missed"
        )
      )
  );
}

async function getActiveConversationMembership(
  conversationId: string,
  auth: NonNullable<Express.Request["auth"]>
) {
  const peerAccessFilter =
    auth.role === "ADMIN"
      ? {}
      : {
          peerId: auth.userId,
          type:
            auth.role === "CAREGIVER"
              ? ConversationType.CAREGIVER
              : ConversationType.FAMILY
        };

  return prisma.conversationMember.findFirst({
    where: {
      conversationId,
      userId: auth.userId,
      conversation: {
        ...peerAccessFilter,
        peer: {
          status: "ACTIVE"
        }
      }
    },
    include: {
      conversation: {
        select: {
          id: true,
          residentId: true,
          peerId: true,
          type: true
        }
      }
    }
  });
}

async function ensureAndGetConversationMembership(
  conversationId: string,
  auth: NonNullable<Express.Request["auth"]>
) {
  let membership = await getActiveConversationMembership(conversationId, auth);

  if (!membership) {
    const conversation = await prisma.conversation.findUnique({
      where: { id: conversationId },
      select: { residentId: true, peerId: true, type: true }
    });

    if (conversation?.peerId && (auth.role === "ADMIN" || conversation.peerId === auth.userId)) {
      await ensureConversationForResidentPeer(
        conversation.residentId ?? "",
        { userId: conversation.peerId, type: conversation.type },
        await getActiveAdminIds()
      );
      membership = await getActiveConversationMembership(conversationId, auth);
    }
  }

  if (!membership) {
    throw new AppError(403, "Conversation access denied", "FORBIDDEN");
  }

  return membership;
}

async function syncConversationsForAccessibleResidents(
  auth: NonNullable<Express.Request["auth"]>
) {
  const residentIds = await getAccessibleResidentIds(auth);
  if (residentIds.length === 0) {
    return residentIds;
  }

  await Promise.all(
    residentIds.map((residentId) => ensureConversationMembersForResident(residentId))
  );

  return residentIds;
}

export const apiRouter = Router();

apiRouter.use(requireAuth);

apiRouter.get(
  "/facility-info",
  asyncHandler(async (_req, res) => {
    const info = await getFacilityInfo();
    res.json(ok(serializeFacilityInfo(info)));
  })
);

apiRouter.patch(
  "/facility-info",
  requireRole("ADMIN"),
  validateBody(facilityInfoSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof facilityInfoSchema>;

    const info = await prisma.facilityInfo.upsert({
      where: { id: FACILITY_INFO_ID },
      create: {
        id: FACILITY_INFO_ID,
        name: payload.name.trim(),
        contactNumber: payload.contactNumber?.trim() || null,
        email: payload.email?.trim() || null,
        address: payload.address?.trim() || null,
        updatedById: req.auth!.userId
      },
      update: {
        name: payload.name.trim(),
        contactNumber: payload.contactNumber?.trim() || null,
        email: payload.email?.trim() || null,
        address: payload.address?.trim() || null,
        updatedById: req.auth!.userId
      }
    });

    const serialized = serializeFacilityInfo(info);
    getIo()?.emit("facility-info:updated", serialized);
    res.json(ok(serialized));
  })
);

apiRouter.get(
  "/residents",
  asyncHandler(async (req, res) => {
    const auth = req.auth!;
    const search = String(req.query.search || "").trim();
    const status = String(req.query.status || "").trim();
    const unassigned = String(req.query.unassigned || "false") === "true";

    const accessibleIds = await getAccessibleResidentIds(auth);

    const where: Prisma.ResidentWhereInput = {
      id: { in: accessibleIds }
    };

    if (search) {
      where.OR = [
        { name: { contains: search } },
        { room: { contains: search } }
      ];
    }

    if (status) {
      const statusMap: Record<string, "STABLE" | "NEEDS_ATTENTION" | "CRITICAL"> = {
        stable: "STABLE",
        needs_attention: "NEEDS_ATTENTION",
        critical: "CRITICAL"
      };

      if (statusMap[status.toLowerCase()]) {
        where.overallStatus = statusMap[status.toLowerCase()];
      }
    }

    if (unassigned) {
      where.assignments = {
        none: {
          state: "ASSIGNED",
          unassignedAt: null
        }
      };
    }

    const residents = await prisma.resident.findMany({
      where,
      include: {
        conditions: true,
        assignments: {
          where: { state: "ASSIGNED", unassignedAt: null },
          include: {
            caregiver: {
              include: { caregiverProfile: true }
            }
          }
        },
        medications: {
          include: { events: true }
        },
        careTasks: {
          include: { event: true }
        },
        familyProfile: {
          include: { user: true }
        }
      },
      orderBy: { name: "asc" }
    });

    const window = getTodayWindow();
    const mapped = residents.map((r) => {
      const todayMedicationEvents = r.medications.flatMap((med) => med.events ?? []);
      const todayMedicationEventsFiltered = todayMedicationEvents.filter((event) => {
        if (!event.scheduledAt) {
          return false;
        }
        return event.scheduledAt >= window.start && event.scheduledAt < window.end;
      });
      const todayMedicationEventsCompleted = todayMedicationEventsFiltered.filter((event) => isCompletedTimelineStatus(event.status)).length;
      const todayCareTasksTotal = r.careTasks.length;
      const todayCareTasksCompleted = r.careTasks.filter((task) => isCompletedTimelineStatus(getDailyCareTaskEvent(task, window).status)).length;
      return {
        id: r.id,
        name: r.name,
        room: r.room,
        age: r.age,
        overallStatus: r.overallStatus,
        conditions: r.conditions.map((c) => c.name),
        assignedCaregivers: r.assignments.map((a) => ({
          id: a.caregiver.id,
          name: a.caregiver.caregiverProfile?.displayName || a.caregiver.email
        })),
        medicationCount: r.medications.length,
        careTaskCount: r.careTasks.length,
        todayMedicationEventsTotal: todayMedicationEventsFiltered.length,
        todayMedicationEventsCompleted,
        todayCareTasksTotal,
        todayCareTasksCompleted,
        familyEmail: r.familyProfile?.user.email || null
      };
    });

    res.json(ok(mapped));
  })
);

apiRouter.get(
  "/residents/:id",
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    await ensureResidentAccess(residentId, req.auth!);

    const resident = await prisma.resident.findUnique({
      where: { id: residentId },
      include: {
        conditions: true,
        assignments: {
          where: { state: "ASSIGNED", unassignedAt: null },
          include: {
            caregiver: {
              include: { caregiverProfile: true }
            }
          }
        },
        medications: {
          include: { events: true, reminders: true }
        },
        careTasks: {
          include: { event: true }
        },
        familyProfile: true
      }
    });

    if (!resident) {
      throw new AppError(404, "Resident not found", "RESIDENT_NOT_FOUND");
    }

    const window = getTodayWindow();

    res.json(ok({
      ...resident,
      careTasks: resident.careTasks.map((task) => withDailyCareTaskEvent(task, window))
    }));
  })
);

apiRouter.get(
  "/residents/:id/completion-history",
  requireRole("FAMILY"),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    await ensureResidentAccess(residentId, req.auth!);

    const start = parseQueryDate(req.query.start, "start");
    const end = parseQueryDate(req.query.end, "end");
    const type = firstQueryValue(req.query.type)?.toUpperCase();
    const activityType =
      type === "MEDICATION"
        ? CaregiverActivityType.MEDICATION
        : type === "CARE_TASK"
          ? CaregiverActivityType.CARE_TASK
          : undefined;

    if (start && end && end <= start) {
      throw new AppError(400, "end must be after start.", "INVALID_DATE_RANGE");
    }

    const logs = await prisma.caregiverActivityLog.findMany({
      where: {
        residentId,
        ...(activityType ? { activityType } : {}),
        ...(start || end
          ? {
              completedAt: {
                ...(start ? { gte: start } : {}),
                ...(end ? { lt: end } : {})
              }
            }
          : {})
      },
      include: {
        caregiver: {
          include: { caregiverProfile: true }
        },
        resident: true
      },
      orderBy: { completedAt: "desc" },
      take: 100
    });

    res.json(
      ok(
        logs.map((log) => ({
          id: log.id,
          caregiverId: log.caregiverId,
          caregiverName: caregiverDisplayName(log.caregiver),
          residentId: log.residentId,
          residentName: log.resident.name,
          roomNumber: log.resident.room,
          type:
            log.activityType === CaregiverActivityType.CARE_TASK
              ? "Care Task"
              : "Medication",
          itemTitle: log.itemTitle,
          itemDetails: log.itemDetails,
          completedAt: log.completedAt
        }))
      )
    );
  })
);

apiRouter.patch(
  "/residents/:id/assign-caregiver",
  requireRole("ADMIN"),
  validateBody(assignCaregiverSchema),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    const { caregiverId } = req.body as z.infer<typeof assignCaregiverSchema>;

    const caregiver = await prisma.user.findUnique({ where: { id: caregiverId } });
    if (!caregiver || caregiver.role !== "CAREGIVER" || caregiver.status !== "ACTIVE") {
      throw new AppError(400, "Invalid caregiver", "INVALID_CAREGIVER");
    }

    const resident = await prisma.resident.findUnique({ where: { id: residentId } });
    if (!resident) {
      throw new AppError(404, "Resident not found", "RESIDENT_NOT_FOUND");
    }

    await prisma.$transaction(async (tx) => {
      await tx.residentAssignment.updateMany({
        where: { residentId, state: "ASSIGNED", unassignedAt: null },
        data: { state: "UNASSIGNED", unassignedAt: new Date() }
      });

      await tx.residentAssignment.create({
        data: {
          residentId,
          caregiverId,
          state: "ASSIGNED"
        }
      });
    });

    await ensureConversationMembersForResident(residentId);

    const io = getIo();
    io?.emit("resident:status-updated", { residentId, caregiverId, type: "assignment" });

    res.json(ok({ assigned: true }));
  })
);

apiRouter.patch(
  "/residents/:id/unassign-caregiver",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;

    const resident = await prisma.resident.findUnique({ where: { id: residentId } });
    if (!resident) {
      throw new AppError(404, "Resident not found", "RESIDENT_NOT_FOUND");
    }

    const result = await prisma.residentAssignment.updateMany({
      where: { residentId, state: "ASSIGNED", unassignedAt: null },
      data: { state: "UNASSIGNED", unassignedAt: new Date() }
    });

    const io = getIo();
    io?.emit("resident:status-updated", { residentId, type: "unassignment" });

    res.json(ok({ unassigned: result.count > 0 }));
  })
);

apiRouter.patch(
  "/residents/:id/medical-notes",
  requireRole("ADMIN", "CAREGIVER"),
  validateBody(medicalNotesSchema),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    await ensureResidentAccess(residentId, req.auth!);

    const { medicalNotes } = req.body as z.infer<typeof medicalNotesSchema>;

    const resident = await prisma.resident.update({
      where: { id: residentId },
      data: { medicalNotes }
    });

    const io = getIo();
    io?.emit("resident:status-updated", { residentId, type: "medical_notes" });

    res.json(ok(resident));
  })
);

apiRouter.post(
  "/residents/:id/medications",
  requireRole("ADMIN"),
  validateBody(createMedicationSchema),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    const payload = req.body as z.infer<typeof createMedicationSchema>;

    const resident = await prisma.resident.findUnique({ where: { id: residentId } });
    if (!resident) {
      throw new AppError(404, "Resident not found", "RESIDENT_NOT_FOUND");
    }

    const startDate = new Date(payload.startDate);

    const medication = await prisma.medication.create({
      data: {
        residentId,
        name: payload.name,
        dosage: payload.dosage,
        type: payload.type,
        frequency: payload.frequency,
        startDate,
        duration: payload.duration,
        createdById: req.auth!.userId,
        reminders: {
          createMany: {
            data: payload.reminders
          }
        }
      },
      include: { reminders: true }
    });

    for (const reminder of payload.reminders) {
      await prisma.medicationEvent.create({
        data: {
          medicationId: medication.id,
          residentId,
          scheduledAt: parseTimeToDate(startDate, reminder.time),
          status: "PENDING"
        }
      });
    }

    await notifyMedicationScheduleCreated(resident, medication);

    const io = getIo();
    io?.emit("resident:status-updated", { residentId, type: "medication_created" });

    res.status(201).json(ok(medication));
  })
);

apiRouter.get(
  "/residents/:id/medications",
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    await ensureResidentAccess(residentId, req.auth!);

    const medications = await prisma.medication.findMany({
      where: { residentId },
      include: {
        reminders: true,
        events: {
          orderBy: { scheduledAt: "asc" }
        }
      },
      orderBy: { createdAt: "desc" }
    });

    res.json(ok(medications));
  })
);

apiRouter.patch(
  "/medications/:id",
  requireRole("ADMIN"),
  validateBody(updateMedicationSchema),
  asyncHandler(async (req, res) => {
    const medicationId = req.params.id;
    const payload = req.body as z.infer<typeof updateMedicationSchema>;

    const existing = await prisma.medication.findUnique({
      where: { id: medicationId },
      include: { events: true }
    });
    if (!existing) {
      throw new AppError(404, "Medication not found", "MEDICATION_NOT_FOUND");
    }

    await ensureResidentAccess(existing.residentId, req.auth!);
    if (isMedicationCompleted(existing.events)) {
      throw new AppError(
        400,
        "Completed medications cannot be edited",
        "MEDICATION_COMPLETED"
      );
    }

    const startDate = new Date(payload.startDate);
    const medication = await prisma.$transaction(async (tx) => {
      await tx.medicationReminder.deleteMany({ where: { medicationId } });
      await tx.medicationEvent.deleteMany({ where: { medicationId } });

      await tx.medication.update({
        where: { id: medicationId },
        data: {
          name: payload.name,
          dosage: payload.dosage,
          type: payload.type,
          frequency: payload.frequency,
          startDate,
          duration: payload.duration,
          reminders: {
            createMany: {
              data: payload.reminders
            }
          }
        },
        include: { reminders: true, events: true }
      });

      await tx.medicationEvent.createMany({
        data: payload.reminders.map((reminder) => ({
          medicationId,
          residentId: existing.residentId,
          scheduledAt: parseTimeToDate(startDate, reminder.time),
          status: MedicationStatus.PENDING
        }))
      });

      return tx.medication.findUniqueOrThrow({
        where: { id: medicationId },
        include: {
          reminders: true,
          events: {
            orderBy: { scheduledAt: "asc" }
          }
        }
      });
    });

    const io = getIo();
    io?.emit("resident:status-updated", {
      residentId: existing.residentId,
      type: "medication_updated"
    });

    res.json(ok(medication));
  })
);

apiRouter.delete(
  "/medications/:id",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const medicationId = req.params.id;
    const medication = await prisma.medication.findUnique({
      where: { id: medicationId },
      include: { events: true }
    });
    if (!medication) {
      throw new AppError(404, "Medication not found", "MEDICATION_NOT_FOUND");
    }

    await ensureResidentAccess(medication.residentId, req.auth!);
    await prisma.medication.delete({ where: { id: medicationId } });

    const io = getIo();
    io?.emit("resident:status-updated", {
      residentId: medication.residentId,
      type: "medication_deleted"
    });

    res.json(ok({ deleted: true }));
  })
);

apiRouter.patch(
  "/medication-events/:id/status",
  requireRole("ADMIN", "CAREGIVER"),
  validateBody(medicationStatusSchema),
  asyncHandler(async (req, res) => {
    const { status, remark } = req.body as z.infer<typeof medicationStatusSchema>;
    const id = req.params.id;

    const event = await prisma.medicationEvent.findUnique({
      where: { id },
      include: { medication: true, resident: true }
    });
    if (!event) {
      throw new AppError(404, "Medication event not found", "MEDICATION_EVENT_NOT_FOUND");
    }

    await ensureResidentAccess(event.residentId, req.auth!);

    const completedAt = new Date();
    const updated = await prisma.$transaction(async (tx) => {
      const medicationEvent = await tx.medicationEvent.update({
        where: { id },
        data: {
          status,
          remark,
          updatedById: req.auth!.userId
        }
      });

      if (status === MedicationStatus.TAKEN && event.status !== MedicationStatus.TAKEN) {
        await tx.caregiverActivityLog.create({
          data: {
            caregiverId: req.auth!.userId,
            residentId: event.residentId,
            activityType: CaregiverActivityType.MEDICATION,
            itemTitle: event.medication.name,
            itemDetails: compactDetails(event.medication.dosage, event.medication.type),
            completedAt,
            medicationEventId: event.id
          }
        });
      }

      return medicationEvent;
    });

    if (
      status === MedicationStatus.MISSED ||
      status === MedicationStatus.DELAYED ||
      status === MedicationStatus.SKIPPED
    ) {
      await notifyMedicationAlert(
        event.id,
        status === MedicationStatus.MISSED ? "missed" : status.toLowerCase()
      );
    }

    if (status === MedicationStatus.TAKEN && event.status !== MedicationStatus.TAKEN) {
      await notifyFamilyCareUpdate({
        resident: event.resident,
        title: `Care update for ${event.resident.name}`,
        body: `${event.medication.name} was marked taken for ${event.resident.name}.`,
        sourceKey: `family-care-update:medication:${event.id}:taken`,
        data: {
          trigger: "MEDICATION_TAKEN",
          residentId: event.residentId,
          residentName: event.resident.name,
          room: event.resident.room,
          medicationId: event.medicationId,
          medicationEventId: event.id,
          status
        }
      });
    }

    const io = getIo();
    io?.emit("resident:status-updated", { residentId: event.residentId, type: "medication_event" });

    res.json(ok(updated));
  })
);

apiRouter.get(
  "/residents/:id/care-tasks",
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    await ensureResidentAccess(residentId, req.auth!);

    const tasks = await prisma.careTask.findMany({
      where: { residentId },
      include: {
        event: true
      },
      orderBy: { createdAt: "asc" }
    });

    const window = getTodayWindow();
    res.json(ok(tasks.map((task) => withDailyCareTaskEvent(task, window))));
  })
);

apiRouter.post(
  "/residents/:id/care-tasks",
  requireRole("ADMIN"),
  validateBody(createCareTaskSchema),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    const payload = req.body as z.infer<typeof createCareTaskSchema>;

    const resident = await prisma.resident.findUnique({ where: { id: residentId } });
    if (!resident) {
      throw new AppError(404, "Resident not found", "RESIDENT_NOT_FOUND");
    }

    const assignedCaregiverId = await resolveCareTaskAssignee(
      residentId,
      payload.assignedCaregiverId
    );

    const task = await prisma.careTask.create({
      data: {
        residentId,
        title: payload.title,
        type: payload.type,
        scheduledTime: payload.scheduledTime,
        frequency: payload.frequency,
        assignedCaregiverId,
        createdById: req.auth!.userId
      },
      include: { event: true, assignedCaregiver: { include: { caregiverProfile: true } } }
    });

    await notifyCareTaskCreated(resident, task);

    const io = getIo();
    io?.emit("resident:status-updated", { residentId, caregiverId: assignedCaregiverId, type: "care_task_created" });

    res.status(201).json(ok(task));
  })
);

apiRouter.post(
  "/residents/:id/care-tasks/batch",
  requireRole("ADMIN"),
  validateBody(createCareTasksBatchSchema),
  asyncHandler(async (req, res) => {
    const residentId = req.params.id;
    const payload = req.body as z.infer<typeof createCareTasksBatchSchema>;

    const resident = await prisma.resident.findUnique({ where: { id: residentId } });
    if (!resident) {
      throw new AppError(404, "Resident not found", "RESIDENT_NOT_FOUND");
    }

    const assignedCaregiverId = await resolveCareTaskAssignee(
      residentId,
      payload.assignedCaregiverId
    );

    const tasks = await prisma.$transaction(
      payload.tasks.map((task) =>
        prisma.careTask.create({
          data: {
            residentId,
            title: task.title,
            type: task.type,
            scheduledTime: task.scheduledTime,
            frequency: task.frequency,
            assignedCaregiverId,
            createdById: req.auth!.userId
          },
          include: { event: true, assignedCaregiver: { include: { caregiverProfile: true } } }
        })
      )
    );

    await Promise.all(tasks.map((task) => notifyCareTaskCreated(resident, task)));

    const io = getIo();
    io?.emit("resident:status-updated", { residentId, caregiverId: assignedCaregiverId, type: "care_tasks_created" });

    res.status(201).json(ok(tasks));
  })
);

apiRouter.patch(
  "/care-tasks/:id",
  requireRole("ADMIN"),
  validateBody(updateCareTaskSchema),
  asyncHandler(async (req, res) => {
    const careTaskId = req.params.id;
    const payload = req.body as z.infer<typeof updateCareTaskSchema>;

    const task = await prisma.careTask.findUnique({
      where: { id: careTaskId },
      include: { event: true, resident: true }
    });
    if (!task) {
      throw new AppError(404, "Care task not found", "CARE_TASK_NOT_FOUND");
    }

    if (getDailyCareTaskEvent(task).status === CareTaskStatus.DONE) {
      throw new AppError(
        409,
        "Completed care tasks cannot be edited",
        "CARE_TASK_COMPLETED"
      );
    }

    const updated = await prisma.careTask.update({
      where: { id: careTaskId },
      data: {
        title: payload.title,
        type: payload.type,
        scheduledTime: payload.scheduledTime,
        frequency: payload.frequency
      },
      include: { event: true, assignedCaregiver: { include: { caregiverProfile: true } } }
    });

    const io = getIo();
    io?.emit("resident:status-updated", { residentId: task.residentId, type: "care_task_updated" });

    res.json(ok(updated));
  })
);

apiRouter.delete(
  "/care-tasks/:id",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const careTaskId = req.params.id;

    const task = await prisma.careTask.findUnique({ where: { id: careTaskId } });
    if (!task) {
      throw new AppError(404, "Care task not found", "CARE_TASK_NOT_FOUND");
    }

    await prisma.careTask.delete({ where: { id: careTaskId } });

    const io = getIo();
    io?.emit("resident:status-updated", { residentId: task.residentId, type: "care_task_deleted" });

    res.json(ok({ deleted: true, id: careTaskId }));
  })
);

apiRouter.patch(
  "/care-task-events/:id/status",
  requireRole("ADMIN", "CAREGIVER"),
  validateBody(careTaskStatusSchema),
  asyncHandler(async (req, res) => {
    const careTaskId = req.params.id;
    const payload = req.body as z.infer<typeof careTaskStatusSchema>;

    const task = await prisma.careTask.findUnique({
      where: { id: careTaskId },
      include: { event: true, resident: true }
    });
    if (!task) {
      throw new AppError(404, "Care task not found", "CARE_TASK_NOT_FOUND");
    }

    await ensureResidentAccess(task.residentId, req.auth!);

    const completedAt = new Date();
    const currentTaskEvent = getDailyCareTaskEvent(task);
    const updated = await prisma.$transaction(async (tx) => {
      const careTaskEvent = await tx.careTaskEvent.upsert({
        where: { careTaskId },
        create: {
          careTaskId,
          residentId: task.residentId,
          status: payload.status,
          remark: payload.remark,
          timeCompleted: payload.status === CareTaskStatus.DONE ? completedAt : null,
          updatedById: req.auth!.userId
        },
        update: {
          status: payload.status,
          remark: payload.remark,
          timeCompleted: payload.status === CareTaskStatus.DONE ? completedAt : null,
          updatedById: req.auth!.userId
        }
      });

      if (payload.status === CareTaskStatus.DONE && currentTaskEvent.status !== CareTaskStatus.DONE) {
        await tx.caregiverActivityLog.create({
          data: {
            caregiverId: req.auth!.userId,
            residentId: task.residentId,
            activityType: CaregiverActivityType.CARE_TASK,
            itemTitle: task.title,
            itemDetails: compactDetails(task.type, task.scheduledTime),
            completedAt,
            careTaskEventId: careTaskEvent.id
          }
        });
      }

      return careTaskEvent;
    });

    if (payload.status === CareTaskStatus.SKIPPED) {
      await notifyCareTaskAlert(
        {
          id: task.id,
          residentId: task.residentId,
          title: task.title,
          scheduledTime: task.scheduledTime
        },
        formatDateKey(getTodayWindow().start),
        "skipped"
      );
    }

    if (
      payload.status === CareTaskStatus.DONE &&
      currentTaskEvent.status !== CareTaskStatus.DONE
    ) {
      await notifyFamilyCareUpdate({
        resident: task.resident,
        title: `Care update for ${task.resident.name}`,
        body: `${task.title} was completed for ${task.resident.name}.`,
        sourceKey: `family-care-update:care-task:${task.id}:${formatDateKey(completedAt)}`,
        data: {
          trigger: "CARE_TASK_DONE",
          residentId: task.residentId,
          residentName: task.resident.name,
          room: task.resident.room,
          careTaskId: task.id,
          careTaskEventId: updated.id,
          status: payload.status
        }
      });
    }

    const io = getIo();
    io?.emit("resident:status-updated", { residentId: task.residentId, type: "care_task_event" });

    res.json(ok(updated));
  })
);

apiRouter.get(
  "/conversations",
  asyncHandler(async (req, res) => {
    const auth = req.auth!;
    const userId = auth.userId;
    const residentIds = await syncConversationsForAccessibleResidents(auth);
    if (auth.role !== "ADMIN" && residentIds.length === 0) {
      res.json(ok([]));
      return;
    }

    const conversationWhere: Prisma.ConversationWhereInput =
      auth.role === "ADMIN"
        ? {
            peer: {
              status: "ACTIVE"
            }
          }
        : auth.role === "CAREGIVER"
          ? {
              type: ConversationType.CAREGIVER,
              peerId: userId,
              peer: {
                status: "ACTIVE"
              }
            }
          : {
              type: ConversationType.FAMILY,
              peerId: userId,
              residentId: { in: residentIds },
              peer: {
                status: "ACTIVE"
              }
            };

    const conversations = await prisma.conversationMember.findMany({
      where: {
        userId,
        conversation: conversationWhere
      },
      include: {
        conversation: {
          include: {
            resident: true,
            peer: {
              include: {
                caregiverProfile: true,
                familyProfile: true
              }
            },
            messages: {
              orderBy: { createdAt: "desc" },
              take: 1
            }
          }
        }
      }
    });

    const result = await Promise.all(
      conversations.map(async (member) => {
        const isCaregiverConversation =
          member.conversation.type === ConversationType.CAREGIVER;
        const assignedResidents = isCaregiverConversation
          ? await prisma.resident.findMany({
              where: {
                assignments: {
                  some: {
                    caregiverId: member.conversation.peerId,
                    state: "ASSIGNED",
                    unassignedAt: null
                  }
                }
              },
              orderBy: { name: "asc" }
            })
          : [];
        const unreadCount = await prisma.message.count({
          where: {
            conversationId: member.conversationId,
            senderId: { not: userId },
            reads: {
              none: {
                userId
              }
            }
          }
        });

        return {
          conversationId: member.conversationId,
          type: member.conversation.type,
          peer: member.conversation.peer,
          resident: member.conversation.resident ?? assignedResidents[0] ?? null,
          residents: isCaregiverConversation
            ? assignedResidents
            : member.conversation.resident
              ? [member.conversation.resident]
              : [],
          lastMessage: member.conversation.messages[0] ?? null,
          unreadCount
        };
      })
    );

    res.json(ok(result));
  })
);

apiRouter.get(
  "/conversations/:id/messages",
  asyncHandler(async (req, res) => {
    const conversationId = req.params.id;
    await ensureAndGetConversationMembership(conversationId, req.auth!);

    const messages = await prisma.message.findMany({
      where: { conversationId },
      include: {
        sender: {
          include: {
            caregiverProfile: true,
            familyProfile: true
          }
        },
        reads: true
      },
      orderBy: { createdAt: "asc" }
    });

    res.json(ok(messages));
  })
);

apiRouter.post(
  "/conversations/:id/messages",
  validateBody(sendMessageSchema),
  asyncHandler(async (req, res) => {
    const conversationId = req.params.id;
    const { content } = req.body as z.infer<typeof sendMessageSchema>;
    await ensureAndGetConversationMembership(conversationId, req.auth!);

    const message = await prisma.message.create({
      data: {
        conversationId,
        senderId: req.auth!.userId,
        content,
        reads: {
          create: { userId: req.auth!.userId }
        }
      },
      include: {
        sender: true,
        reads: true
      }
    });

    const io = getIo();
    io?.to(`conversation:${conversationId}`).emit("message:new", message);
    io?.to(`conversation:${conversationId}`).emit("conversation:updated", {
      conversationId,
      lastMessageId: message.id
    });

    if (req.auth!.role === "ADMIN") {
      await notifyAdminMessage(conversationId, message.id, content);
    }

    res.status(201).json(ok(message));
  })
);

apiRouter.post(
  "/messages/:id/read",
  asyncHandler(async (req, res) => {
    const messageId = req.params.id;

    const message = await prisma.message.findUnique({ where: { id: messageId } });
    if (!message) {
      throw new AppError(404, "Message not found", "MESSAGE_NOT_FOUND");
    }

    await ensureAndGetConversationMembership(message.conversationId, req.auth!);

    await prisma.messageRead.upsert({
      where: {
        messageId_userId: {
          messageId,
          userId: req.auth!.userId
        }
      },
      create: {
        messageId,
        userId: req.auth!.userId
      },
      update: {
        readAt: new Date()
      }
    });

    const io = getIo();
    io?.to(`conversation:${message.conversationId}`).emit("message:read", {
      messageId,
      userId: req.auth!.userId
    });

    res.json(ok({ read: true }));
  })
);

apiRouter.get(
  "/reports/overview",
  requireRole("ADMIN"),
  asyncHandler(async (_req, res) => {
    const { start, end } = getTodayWindow();

    const todayMedicationWhere: Prisma.MedicationEventWhereInput = {
      updatedAt: { gte: start, lt: end }
    };
    const [
      totalResidents,
      totalMedicationEvents,
      takenMedicationEvents,
      missedMedicationEvents,
      totalTaskEvents,
      doneTaskEvents
    ] = await Promise.all([
      prisma.resident.count(),
      prisma.medicationEvent.count({ where: todayMedicationWhere }),
      prisma.medicationEvent.count({
        where: { ...todayMedicationWhere, status: "TAKEN" }
      }),
      prisma.medicationEvent.count({
        where: { ...todayMedicationWhere, status: "MISSED" }
      }),
      prisma.careTask.count(),
      prisma.careTaskEvent.count({
        where: {
          updatedAt: { gte: start, lt: end },
          status: "DONE"
        }
      })
    ]);

    const medCompliance = totalMedicationEvents === 0 ? 0 : Math.round((takenMedicationEvents / totalMedicationEvents) * 100);
    const taskCompletion = totalTaskEvents === 0 ? 0 : Math.round((doneTaskEvents / totalTaskEvents) * 100);

    res.json(ok({
      totalResidents,
      totalMedicationEvents,
      takenMedicationEvents,
      missedMedicationEvents,
      totalTaskEvents,
      doneTaskEvents,
      medCompliance,
      taskCompletion
    }));
  })
);

apiRouter.get(
  "/reports/caregiver-performance",
  requireRole("ADMIN", "CAREGIVER"),
  asyncHandler(async (req, res) => {
    const { start, end } = getTodayWindow();

    const caregivers = await prisma.user.findMany({
      where: {
        role: "CAREGIVER",
        status: "ACTIVE",
        ...(req.auth!.role === "CAREGIVER" ? { id: req.auth!.userId } : {})
      },
      include: { caregiverProfile: true }
    });

    const result = await Promise.all(
      caregivers.map(async (caregiver) => {
        const [assignedResidents, medicationsGiven, medicationsMissed, medicationsTotal, tasksDone, tasksTotal] =
          await Promise.all([
            prisma.residentAssignment.count({
              where: {
                caregiverId: caregiver.id,
                state: "ASSIGNED",
                unassignedAt: null
              }
            }),
            prisma.medicationEvent.count({
              where: {
                updatedById: caregiver.id,
                updatedAt: { gte: start, lt: end },
                status: "TAKEN"
              }
            }),
            prisma.medicationEvent.count({
              where: {
                updatedById: caregiver.id,
                updatedAt: { gte: start, lt: end },
                status: "MISSED"
              }
            }),
            prisma.medicationEvent.count({
              where: {
                updatedById: caregiver.id,
                updatedAt: { gte: start, lt: end }
              }
            }),
            prisma.careTaskEvent.count({
              where: {
                updatedById: caregiver.id,
                updatedAt: { gte: start, lt: end },
                status: "DONE"
              }
            }),
            prisma.careTask.count({
              where: {
                assignedCaregiverId: caregiver.id
              }
            })
          ]);

        const medScore = medicationsTotal === 0 ? 0 : (medicationsGiven / medicationsTotal) * 100;
        const taskScore = tasksTotal === 0 ? 0 : (tasksDone / tasksTotal) * 100;
        const scoreParts = [medicationsTotal > 0 ? medScore : null, tasksTotal > 0 ? taskScore : null]
          .filter((value): value is number => value !== null);
        const score = scoreParts.length === 0
          ? 0
          : Math.round(scoreParts.reduce((sum, value) => sum + value, 0) / scoreParts.length);

        return {
          caregiverId: caregiver.id,
          caregiverName: caregiver.caregiverProfile?.displayName || caregiver.email,
          assignedResidents,
          medicationsGiven,
          medicationsMissed,
          medicationsTotal,
          tasksDone,
          tasksTotal,
          score
        };
      })
    );

    res.json(ok(result));
  })
);

apiRouter.get(
  "/reports/caregiver-activity-history",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const today = getTodayWindow();
    const start = parseQueryDate(req.query.start, "start") ?? today.start;
    const end = parseQueryDate(req.query.end, "end") ?? today.end;
    const caregiverId = firstQueryValue(req.query.caregiverId);
    const selectedCaregiverId =
      caregiverId && caregiverId.toLowerCase() !== "all" ? caregiverId : undefined;

    if (end <= start) {
      throw new AppError(400, "end must be after start.", "INVALID_DATE_RANGE");
    }

    const [caregivers, logs] = await Promise.all([
      prisma.user.findMany({
        where: {
          role: "CAREGIVER",
          status: "ACTIVE"
        },
        include: { caregiverProfile: true },
        orderBy: { createdAt: "desc" }
      }),
      prisma.caregiverActivityLog.findMany({
        where: {
          completedAt: { gte: start, lt: end },
          ...(selectedCaregiverId ? { caregiverId: selectedCaregiverId } : {})
        },
        include: {
          caregiver: {
            include: { caregiverProfile: true }
          },
          resident: true
        },
        orderBy: { completedAt: "desc" },
        take: 500
      })
    ]);

    res.json(ok({
      caregivers: caregivers.map((caregiver) => ({
        caregiverId: caregiver.id,
        caregiverName: caregiverDisplayName(caregiver),
        caregiverEmail: caregiver.email
      })),
      records: logs.map((log) => ({
        id: log.id,
        caregiverId: log.caregiverId,
        caregiverName: caregiverDisplayName(log.caregiver),
        residentId: log.residentId,
        residentName: log.resident.name,
        roomNumber: log.resident.room,
        type: log.activityType === CaregiverActivityType.CARE_TASK ? "Care Task" : "Medication",
        itemTitle: log.itemTitle,
        itemDetails: log.itemDetails,
        completedAt: log.completedAt
      }))
    }));
  })
);

apiRouter.get(
  "/time-clock/me",
  requireRole("CAREGIVER"),
  asyncHandler(async (req, res) => {
    const caregiverId = req.auth!.userId;
    const { start, end } = getTodayWindow();

    const logs = await prisma.caregiverTimeLog.findMany({
      where: {
        caregiverId,
        OR: [
          { timeIn: { gte: start, lt: end } },
          { timeOut: { gte: start, lt: end } },
          { timeOut: null }
        ]
      },
      include: {
        caregiver: {
          include: { caregiverProfile: true }
        }
      },
      orderBy: { timeIn: "desc" }
    });

    const activeLog = logs.find((log) => log.timeOut === null) ?? null;
    const todayTotalMinutes = logs.reduce(
      (sum, log) => sum + (log.totalMinutes ?? minutesBetween(log.timeIn, log.timeOut)),
      0
    );

    res.json(ok({
      activeLog: activeLog ? serializeTimeLog(activeLog) : null,
      logs: logs.map(serializeTimeLog),
      todayTotalMinutes,
      todayTotalHours: hoursFromMinutes(todayTotalMinutes)
    }));
  })
);

apiRouter.post(
  "/time-clock/time-in",
  requireRole("CAREGIVER"),
  asyncHandler(async (req, res) => {
    const caregiverId = req.auth!.userId;

    const existingOpenLog = await prisma.caregiverTimeLog.findFirst({
      where: { caregiverId, timeOut: null },
      include: {
        caregiver: {
          include: { caregiverProfile: true }
        }
      },
      orderBy: { timeIn: "desc" }
    });

    if (existingOpenLog) {
      res.json(ok({
        activeLog: serializeTimeLog(existingOpenLog),
        created: false
      }));
      return;
    }

    const log = await prisma.caregiverTimeLog.create({
      data: { caregiverId },
      include: {
        caregiver: {
          include: { caregiverProfile: true }
        }
      }
    });

    res.status(201).json(ok({
      activeLog: serializeTimeLog(log),
      created: true
    }));
  })
);

apiRouter.post(
  "/time-clock/time-out",
  requireRole("CAREGIVER"),
  asyncHandler(async (req, res) => {
    const caregiverId = req.auth!.userId;
    const now = new Date();

    const openLog = await prisma.caregiverTimeLog.findFirst({
      where: { caregiverId, timeOut: null },
      orderBy: { timeIn: "desc" }
    });

    if (!openLog) {
      throw new AppError(400, "No active time-in record found.", "NO_ACTIVE_TIME_LOG");
    }

    const totalMinutes = minutesBetween(openLog.timeIn, now);
    const updatedLog = await prisma.caregiverTimeLog.update({
      where: { id: openLog.id },
      data: {
        timeOut: now,
        totalMinutes
      },
      include: {
        caregiver: {
          include: { caregiverProfile: true }
        }
      }
    });

    await prisma.refreshToken.updateMany({
      where: { userId: caregiverId, revokedAt: null },
      data: { revokedAt: now }
    });

    res.json(ok({
      log: serializeTimeLog(updatedLog),
      loggedOut: true
    }));
  })
);

apiRouter.get(
  "/time-clock/admin/today",
  requireRole("ADMIN"),
  asyncHandler(async (_req, res) => {
    const { start, end } = getTodayWindow();

    const [caregivers, logs] = await Promise.all([
      prisma.user.findMany({
        where: {
          role: "CAREGIVER",
          status: "ACTIVE"
        },
        include: { caregiverProfile: true },
        orderBy: { createdAt: "desc" }
      }),
      prisma.caregiverTimeLog.findMany({
        where: {
          OR: [
            { timeIn: { gte: start, lt: end } },
            { timeOut: { gte: start, lt: end } },
            { timeOut: null }
          ]
        },
        include: {
          caregiver: {
            include: { caregiverProfile: true }
          }
        },
        orderBy: { timeIn: "desc" }
      })
    ]);

    const logsByCaregiver = new Map<string, TimeLogWithCaregiver[]>();
    for (const log of logs) {
      const caregiverLogs = logsByCaregiver.get(log.caregiverId) ?? [];
      caregiverLogs.push(log);
      logsByCaregiver.set(log.caregiverId, caregiverLogs);
    }

    const caregiverSummaries = caregivers.map((caregiver) => {
      const caregiverLogs = logsByCaregiver.get(caregiver.id) ?? [];
      const activeLog = caregiverLogs.find((log) => log.timeOut === null) ?? null;
      const totalMinutes = caregiverLogs.reduce(
        (sum, log) => sum + (log.totalMinutes ?? minutesBetween(log.timeIn, log.timeOut)),
        0
      );
      const latestLog = caregiverLogs[0] ?? null;

      return {
        caregiverId: caregiver.id,
        caregiverName: caregiverDisplayName(caregiver),
        caregiverEmail: caregiver.email,
        isTimedIn: activeLog !== null,
        timeIn: activeLog?.timeIn ?? latestLog?.timeIn ?? null,
        timeOut: latestLog?.timeOut ?? null,
        totalMinutes,
        totalHours: hoursFromMinutes(totalMinutes),
        logs: caregiverLogs.map(serializeTimeLog)
      };
    });

    const totalMinutes = caregiverSummaries.reduce(
      (sum, caregiver) => sum + caregiver.totalMinutes,
      0
    );

    res.json(ok({
      date: start,
      activeCount: caregiverSummaries.filter((caregiver) => caregiver.isTimedIn).length,
      completedCount: logs.filter((log) => log.timeOut !== null).length,
      totalMinutes,
      totalHours: hoursFromMinutes(totalMinutes),
      caregivers: caregiverSummaries,
      logs: logs.map(serializeTimeLog)
    }));
  })
);

apiRouter.get(
  "/alerts/shift-timeline",
  requireRole("ADMIN", "CAREGIVER"),
  asyncHandler(async (req, res) => {
    const residentIds = await getAccessibleResidentIds(req.auth!);
    const window = getTodayWindow();
    const now = new Date();

    const medicationEvents = await prisma.medicationEvent.findMany({
      where: {
        residentId: { in: residentIds },
        scheduledAt: { gte: window.start, lt: window.end }
      },
      include: {
        medication: true,
        resident: true
      },
      orderBy: { scheduledAt: "asc" },
      take: 100
    });

    const careTasks = await prisma.careTask.findMany({
      where: { residentId: { in: residentIds } },
      include: {
        event: true,
        resident: true
      },
      orderBy: { createdAt: "asc" },
      take: 100
    });

    const timeline = [
      ...medicationEvents.map((e) => {
        const urgentExpiresAt = getUrgentAlertExpiresAt(e.scheduledAt);
        return {
          id: e.id,
          kind: "medication",
          title: e.medication.name,
          residentName: e.resident.name,
          scheduledAt: e.scheduledAt,
          urgentExpiresAt,
          status: e.status,
          urgent: isUrgentTimelineItem(e.status, e.scheduledAt, now)
        };
      }),
      ...careTasks.map((task) => {
        const event = getDailyCareTaskEvent(task, window);
        const scheduledAt = parseTimeToDate(window.start, task.scheduledTime);
        const urgentExpiresAt = getUrgentAlertExpiresAt(scheduledAt);
        return {
          id: task.id,
          kind: "care_task",
          taskType: task.type,
          title: task.title,
          residentName: task.resident.name,
          scheduledAt,
          urgentExpiresAt,
          status: event.status,
          urgent: isUrgentTimelineItem(event.status, scheduledAt, now)
        };
      })
    ].sort((a, b) => +new Date(a.scheduledAt) - +new Date(b.scheduledAt));

    res.json(ok(timeline));
  })
);

apiRouter.get(
  "/notifications",
  asyncHandler(async (req, res) => {
    await syncDueNotifications(req.auth!);

    const notifications = await prisma.notification.findMany({
      where: { userId: req.auth!.userId },
      orderBy: { createdAt: "desc" },
      take: 100
    });

    res.json(ok(notifications));
  })
);

apiRouter.patch(
  "/notifications/:id/read",
  asyncHandler(async (req, res) => {
    const notification = await prisma.notification.findFirst({
      where: {
        id: req.params.id,
        userId: req.auth!.userId
      }
    });
    if (!notification) {
      throw new AppError(404, "Notification not found", "NOTIFICATION_NOT_FOUND");
    }

    const updated = await prisma.notification.update({
      where: { id: notification.id },
      data: { readAt: new Date() }
    });

    res.json(ok(updated));
  })
);

apiRouter.patch(
  "/notifications/read-all",
  asyncHandler(async (req, res) => {
    const result = await prisma.notification.updateMany({
      where: {
        userId: req.auth!.userId,
        readAt: null
      },
      data: { readAt: new Date() }
    });

    res.json(ok({ updated: result.count }));
  })
);

apiRouter.post(
  "/push-tokens",
  validateBody(pushTokenSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof pushTokenSchema>;

    const token = await prisma.devicePushToken.upsert({
      where: { token: payload.token },
      create: {
        userId: req.auth!.userId,
        token: payload.token,
        platform: payload.platform,
        isActive: true,
        lastSeenAt: new Date()
      },
      update: {
        userId: req.auth!.userId,
        platform: payload.platform,
        isActive: true,
        lastSeenAt: new Date()
      }
    });

    res.json(ok({ registered: true, id: token.id }));
  })
);

apiRouter.get(
  "/profile/me",
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({
      where: { id: req.auth!.userId },
      include: {
        familyProfile: true,
        caregiverProfile: true,
        notificationSetting: true
      }
    });

    if (!user) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    res.json(ok(user));
  })
);

apiRouter.patch(
  "/profile/me",
  validateBody(updateProfileSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof updateProfileSchema>;

    const user = await prisma.user.update({
      where: { id: req.auth!.userId },
      data: {
        username: payload.username
      }
    });

    if (req.auth!.role === "FAMILY") {
      await prisma.familyProfile.update({
        where: { userId: req.auth!.userId },
        data: {
          contactName: payload.contactName,
          relationship: payload.relationship,
          contactNumber: payload.contactNumber,
          secondaryContactNumber: payload.secondaryContactNumber,
          address: payload.address
        }
      });
    }

    if (req.auth!.role === "CAREGIVER") {
      await prisma.caregiverProfile.update({
        where: { userId: req.auth!.userId },
        data: {
          displayName: payload.displayName
        }
      });
    }

    res.json(ok(user));
  })
);

apiRouter.patch(
  "/profile/me/password",
  validateBody(updatePasswordSchema),
  asyncHandler(async (req, res) => {
    const { currentPassword, newPassword } = req.body as z.infer<typeof updatePasswordSchema>;

    const user = await prisma.user.findUnique({ where: { id: req.auth!.userId } });
    if (!user) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    const valid = await comparePassword(currentPassword, user.passwordHash);
    if (!valid) {
      throw new AppError(400, "Current password is incorrect", "INVALID_PASSWORD");
    }

    await prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: await hashPassword(newPassword) }
    });

    await prisma.refreshToken.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date() }
    });

    res.json(ok({ updated: true }));
  })
);

apiRouter.patch(
  "/profile/me/notifications",
  validateBody(updateNotificationSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof updateNotificationSchema>;

    const settings = await prisma.notificationSetting.upsert({
      where: { userId: req.auth!.userId },
      create: {
        userId: req.auth!.userId,
        pushEnabled: payload.pushEnabled ?? true,
        soundEnabled: payload.soundEnabled ?? true,
        vibrationEnabled: payload.vibrationEnabled ?? true,
        medicationCareTaskRemindersEnabled:
          payload.medicationCareTaskRemindersEnabled ?? true,
        urgentAlertsEnabled: payload.urgentAlertsEnabled ?? true,
        adminMessagesEnabled: payload.adminMessagesEnabled ?? true
      },
      update: {
        pushEnabled: payload.pushEnabled,
        soundEnabled: payload.soundEnabled,
        vibrationEnabled: payload.vibrationEnabled,
        medicationCareTaskRemindersEnabled:
          payload.medicationCareTaskRemindersEnabled,
        urgentAlertsEnabled: payload.urgentAlertsEnabled,
        adminMessagesEnabled: payload.adminMessagesEnabled
      }
    });

    res.json(ok(settings));
  })
);

apiRouter.delete(
  "/profile/me",
  asyncHandler(async (req, res) => {
    const userId = req.auth!.userId;

    await prisma.user.update({
      where: { id: userId },
      data: { status: "DEACTIVATED" }
    });

    await prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() }
    });

    res.json(ok({ deleted: true }));
  })
);

apiRouter.get(
  "/admin/medicine-inventory",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const search = String(req.query.search || "").trim();

    const items = await prisma.medicineInventoryItem.findMany({
      where: search
        ? {
            name: {
              contains: search
            }
          }
        : undefined,
      orderBy: [
        { count: "asc" },
        { name: "asc" }
      ]
    });

    res.json(ok(items));
  })
);

apiRouter.post(
  "/admin/medicine-inventory",
  requireRole("ADMIN"),
  validateBody(createMedicineInventorySchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof createMedicineInventorySchema>;
    const name = payload.name.trim();

    const existing = await prisma.medicineInventoryItem.findUnique({
      where: { name },
      select: { id: true }
    });
    if (existing) {
      throw new AppError(409, "Medicine already exists in inventory", "MEDICINE_EXISTS");
    }

    const item = await prisma.medicineInventoryItem.create({
      data: {
        name,
        count: payload.count,
        expirationDate: payload.expirationDate
          ? new Date(payload.expirationDate)
          : null
      }
    });

    await notifyMedicineExpirationAlert(
      item,
      await getActiveAdminIds(),
      getTodayWindow().start
    );

    res.status(201).json(ok(item));
  })
);

apiRouter.patch(
  "/admin/medicine-inventory/:id/adjust",
  requireRole("ADMIN"),
  validateBody(adjustMedicineInventorySchema),
  asyncHandler(async (req, res) => {
    const medicineId = req.params.id;
    const { delta } = req.body as z.infer<typeof adjustMedicineInventorySchema>;

    const item = await prisma.$transaction(async (tx) => {
      const current = await tx.medicineInventoryItem.findUnique({
        where: { id: medicineId }
      });
      if (!current) {
        throw new AppError(404, "Medicine not found", "MEDICINE_NOT_FOUND");
      }

      const nextCount = current.count + delta;
      if (nextCount < 0) {
        throw new AppError(400, "Medicine count cannot go below zero", "INVALID_STOCK_COUNT");
      }

      return tx.medicineInventoryItem.update({
        where: { id: medicineId },
        data: { count: nextCount }
      });
    });

    res.json(ok(item));
  })
);

apiRouter.patch(
  "/admin/medicine-inventory/:id",
  requireRole("ADMIN"),
  validateBody(createMedicineInventorySchema),
  asyncHandler(async (req, res) => {
    const medicineId = req.params.id;
    const payload = req.body as z.infer<typeof createMedicineInventorySchema>;
    const name = payload.name.trim();

    const existing = await prisma.medicineInventoryItem.findUnique({
      where: { name },
      select: { id: true }
    });
    if (existing && existing.id !== medicineId) {
      throw new AppError(409, "Medicine already exists in inventory", "MEDICINE_EXISTS");
    }

    const item = await prisma.medicineInventoryItem.update({
      where: { id: medicineId },
      data: {
        name,
        count: payload.count,
        expirationDate: payload.expirationDate
          ? new Date(payload.expirationDate)
          : null
      }
    });

    await notifyMedicineExpirationAlert(
      item,
      await getActiveAdminIds(),
      getTodayWindow().start
    );

    res.json(ok(item));
  })
);

apiRouter.delete(
  "/admin/medicine-inventory/:id",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const medicineId = req.params.id;

    const existing = await prisma.medicineInventoryItem.findUnique({
      where: { id: medicineId }
    });
    if (!existing) {
      throw new AppError(404, "Medicine not found", "MEDICINE_NOT_FOUND");
    }

    await prisma.medicineInventoryItem.delete({ where: { id: medicineId } });

    res.json(ok({ deleted: true }));
  })
);

apiRouter.get(
  "/admin/users",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const requestedRole = String(req.query.role || "").toUpperCase();
    const includeInactive = String(req.query.includeInactive || "false") === "true";
    const roleFilter =
      requestedRole === "ADMIN" || requestedRole === "CAREGIVER" || requestedRole === "FAMILY"
        ? requestedRole
        : undefined;

    const users = await prisma.user.findMany({
      where: {
        ...(includeInactive ? {} : { status: "ACTIVE" }),
        ...(roleFilter ? { role: roleFilter } : {})
      },
      include: {
        caregiverProfile: true,
        familyProfile: {
          include: {
            resident: {
              include: { conditions: true }
            }
          }
        },
        residentAssignments: {
          where: { state: "ASSIGNED", unassignedAt: null },
          include: { resident: true }
        }
      },
      orderBy: { createdAt: "desc" }
    });

    res.json(ok(users));
  })
);

apiRouter.post(
  "/admin/users/caregiver",
  requireRole("ADMIN"),
  validateBody(createCaregiverSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof createCaregiverSchema>;
    const normalizedEmail = payload.email.trim().toLowerCase();
    const normalizedUsername = payload.username.trim();
    const normalizedName = payload.name.trim();

    const existingByEmail = await prisma.user.findUnique({
      where: { email: normalizedEmail },
      select: { id: true }
    });
    if (existingByEmail) {
      throw new AppError(409, "Email already used", "EMAIL_EXISTS");
    }

    const existingByUsername = await prisma.user.findUnique({
      where: { username: normalizedUsername },
      select: { id: true }
    });
    if (existingByUsername) {
      throw new AppError(409, "Username already used", "USERNAME_EXISTS");
    }

    const user = await prisma.user.create({
      data: {
        email: normalizedEmail,
        username: normalizedUsername,
        passwordHash: await hashPassword(payload.password),
        role: "CAREGIVER",
        caregiverProfile: {
          create: {
            displayName: normalizedName
          }
        },
        notificationSetting: {
          create: {
            pushEnabled: true,
            soundEnabled: true,
            vibrationEnabled: true,
            medicationCareTaskRemindersEnabled: true,
            urgentAlertsEnabled: true,
            adminMessagesEnabled: true
          }
        }
      },
      include: {
        caregiverProfile: true
      }
    });

    res.status(201).json(ok(user));
  })
);

apiRouter.post(
  "/admin/users/patient",
  requireRole("ADMIN"),
  validateBody(createPatientAccountSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof createPatientAccountSchema>;
    const normalizedEmail = payload.email.trim().toLowerCase();
    const normalizedUsername = payload.username.trim();
    const secondaryContactNumber = payload.secondaryContactNumber?.trim() ?? "";

    if (secondaryContactNumber && secondaryContactNumber.length < 7) {
      throw new AppError(400, "Secondary contact number must be valid", "INVALID_SECONDARY_CONTACT_NUMBER");
    }

    const existingByEmail = await prisma.user.findUnique({
      where: { email: normalizedEmail },
      select: { id: true }
    });
    if (existingByEmail) {
      throw new AppError(409, "Email already in use", "EMAIL_EXISTS");
    }

    const existingByUsername = await prisma.user.findUnique({
      where: { username: normalizedUsername },
      select: { id: true }
    });
    if (existingByUsername) {
      throw new AppError(409, "Username already used", "USERNAME_EXISTS");
    }

    const passwordHash = await hashPassword(payload.password);

    const user = await prisma.$transaction(async (tx) => {
      const createdUser = await tx.user.create({
        data: {
          email: normalizedEmail,
          username: normalizedUsername,
          passwordHash,
          role: "FAMILY",
          notificationSetting: {
            create: {
              pushEnabled: true,
              soundEnabled: true,
              vibrationEnabled: true,
              medicationCareTaskRemindersEnabled: true,
              urgentAlertsEnabled: true,
              adminMessagesEnabled: true
            }
          }
        }
      });

      const conditionNames = Array.from(new Set(
        (payload.resident.conditions ?? [])
          .map((condition) => condition.trim())
          .filter(Boolean)
      ));

      const resident = await tx.resident.create({
        data: {
          name: payload.resident.name.trim(),
          room: payload.resident.room.trim(),
          age: payload.resident.age,
          birthday: payload.resident.birthday,
          gender: payload.resident.gender,
          address: payload.resident.address,
          overallStatus: "STABLE",
          conditions: {
            create: conditionNames.map((name) => ({ name }))
          }
        }
      });

      await tx.familyProfile.create({
        data: {
          userId: createdUser.id,
          residentId: resident.id,
          contactName: payload.contactName.trim(),
          relationship: payload.relationship.trim(),
          contactNumber: payload.contactNumber.trim(),
          secondaryContactNumber: secondaryContactNumber || null,
          address: payload.address
        }
      });

      const conversation = await tx.conversation.create({
        data: {
          residentId: resident.id,
          peerId: createdUser.id,
          type: ConversationType.FAMILY
        }
      });

      const admins = await tx.user.findMany({
        where: { role: "ADMIN", status: "ACTIVE" },
        select: { id: true }
      });

      await tx.conversationMember.createMany({
        data: [
          { conversationId: conversation.id, userId: createdUser.id },
          ...admins.map((adminUser) => ({
            conversationId: conversation.id,
            userId: adminUser.id
          }))
        ],
        skipDuplicates: true
      });

      return tx.user.findUniqueOrThrow({
        where: { id: createdUser.id },
        include: {
          familyProfile: {
            include: {
              resident: {
                include: { conditions: true }
              }
            }
          }
        }
      });
    });

    res.status(201).json(ok(user));
  })
);

apiRouter.patch(
  "/admin/users/:id",
  requireRole("ADMIN"),
  validateBody(adminUpdateUserSchema),
  asyncHandler(async (req, res) => {
    const userId = req.params.id;
    const payload = req.body as z.infer<typeof adminUpdateUserSchema>;
    const normalizedEmail = payload.email.trim().toLowerCase();
    const fullName = payload.fullName.trim();
    const primaryContactNumber = payload.primaryContactNumber?.trim() ?? "";
    const secondaryContactNumber = payload.secondaryContactNumber?.trim() ?? "";
    const address = payload.address?.trim() ?? "";

    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        caregiverProfile: true,
        familyProfile: {
          include: { resident: true }
        }
      }
    });

    if (!user || (user.role !== "CAREGIVER" && user.role !== "FAMILY")) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    const existingByEmail = await prisma.user.findUnique({
      where: { email: normalizedEmail },
      select: { id: true }
    });
    if (existingByEmail && existingByEmail.id !== userId) {
      throw new AppError(409, "Email already used", "EMAIL_EXISTS");
    }

    if (user.role === "FAMILY") {
      if (primaryContactNumber.length < 7) {
        throw new AppError(400, "Primary contact number must be valid", "INVALID_CONTACT_NUMBER");
      }
      if (secondaryContactNumber && secondaryContactNumber.length < 7) {
        throw new AppError(400, "Secondary contact number must be valid", "INVALID_SECONDARY_CONTACT_NUMBER");
      }
      if (!payload.resident || !user.familyProfile) {
        throw new AppError(400, "Resident details are required", "RESIDENT_REQUIRED");
      }
    } else if (primaryContactNumber && primaryContactNumber.length < 7) {
      throw new AppError(400, "Primary contact number must be valid", "INVALID_CONTACT_NUMBER");
    }

    await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { email: normalizedEmail }
      });

      if (user.role === "CAREGIVER") {
        await tx.caregiverProfile.update({
          where: { userId },
          data: {
            displayName: fullName,
            contactNumber: primaryContactNumber || null,
            address: address || null
          }
        });
      }

      if (user.role === "FAMILY" && user.familyProfile && payload.resident) {
        const relationship = payload.relationship?.trim() || user.familyProfile.relationship;
        const conditionNames = Array.from(new Set(
          (payload.resident.conditions ?? [])
            .map((condition) => condition.trim())
            .filter(Boolean)
        ));

        await tx.familyProfile.update({
          where: { userId },
          data: {
            contactName: fullName,
            relationship,
            contactNumber: primaryContactNumber,
            secondaryContactNumber: secondaryContactNumber || null,
            address: address || null
          }
        });

        await tx.resident.update({
          where: { id: user.familyProfile.residentId },
          data: {
            name: payload.resident.name.trim(),
            room: payload.resident.room.trim(),
            age: payload.resident.age,
            birthday: payload.resident.birthday?.trim() || null,
            gender: payload.resident.gender?.trim() || null,
            address: payload.resident.address?.trim() || null,
            conditions: {
              deleteMany: {},
              create: conditionNames.map((name) => ({ name }))
            }
          }
        });
      }
    });

    if (user.role === "FAMILY" && user.familyProfile?.residentId) {
      getIo()?.emit("resident:status-updated", {
        residentId: user.familyProfile.residentId,
        type: "family_profile_updated"
      });
    }

    const updatedUser = await prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: {
        caregiverProfile: true,
        familyProfile: {
          include: {
            resident: {
              include: { conditions: true }
            }
          }
        },
        residentAssignments: {
          where: { state: "ASSIGNED", unassignedAt: null },
          include: { resident: true }
        }
      }
    });

    res.json(ok(updatedUser));
  })
);

apiRouter.patch(
  "/admin/users/:id/deactivate",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const userId = req.params.id;

    const existing = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, role: true }
    });
    if (!existing || (existing.role !== "CAREGIVER" && existing.role !== "FAMILY")) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    const user = await prisma.user.update({
      where: { id: userId },
      data: { status: "DEACTIVATED" }
    });

    await prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() }
    });

    res.json(ok({ id: user.id, status: user.status }));
  })
);

apiRouter.patch(
  "/admin/users/:id/activate",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const userId = req.params.id;

    const existing = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, role: true }
    });
    if (!existing || (existing.role !== "CAREGIVER" && existing.role !== "FAMILY")) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    const user = await prisma.user.update({
      where: { id: userId },
      data: { status: "ACTIVE" }
    });

    if (user.role === "FAMILY") {
      const familyProfile = await prisma.familyProfile.findUnique({
        where: { userId },
        select: { residentId: true }
      });
      if (familyProfile) {
        await ensureConversationMembersForResident(familyProfile.residentId);
      }
    }

    res.json(ok({ id: user.id, status: user.status }));
  })
);

apiRouter.delete(
  "/admin/users/:id",
  requireRole("ADMIN"),
  asyncHandler(async (req, res) => {
    const userId = req.params.id;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        familyProfile: {
          select: { residentId: true }
        }
      }
    });

    if (!user || (user.role !== "CAREGIVER" && user.role !== "FAMILY")) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    await prisma.$transaction(async (tx) => {
      await tx.refreshToken.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() }
      });

      if (user.role === "FAMILY" && user.familyProfile?.residentId) {
        await tx.resident.delete({
          where: { id: user.familyProfile.residentId }
        });
      }

      await tx.user.delete({ where: { id: userId } });
    });

    res.json(ok({ deleted: true, id: userId }));
  })
);
