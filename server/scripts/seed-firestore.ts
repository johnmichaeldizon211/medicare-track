import "dotenv/config";

import type { ServiceAccount } from "firebase-admin";
import { cert, getApps, initializeApp } from "firebase-admin/app";
import type { UpdateRequest } from "firebase-admin/auth";
import { getAuth } from "firebase-admin/auth";
import type { Firestore } from "firebase-admin/firestore";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

type SeedUser = {
  email: string;
  password: string;
  displayName: string;
  role: "ADMIN" | "CAREGIVER" | "FAMILY";
  username: string;
};

type ServiceAccountJson = ServiceAccount & {
  project_id?: string;
};

const demoPassword = process.env.FIREBASE_DEMO_PASSWORD ?? "password123";
const resetPasswords = process.argv.includes("--reset-passwords");

const notificationSetting = {
  pushEnabled: true,
  soundEnabled: true,
  vibrationEnabled: true,
  medicationCareTaskRemindersEnabled: true,
  urgentAlertsEnabled: true,
  adminMessagesEnabled: true
};

function readServiceAccount() {
  const rawValue =
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON ??
    process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (!rawValue?.trim()) {
    throw new Error(
      "Set FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS before seeding."
    );
  }

  const value = rawValue.trim();
  if (value.startsWith("{")) {
    return JSON.parse(value) as ServiceAccountJson;
  }

  const serviceAccountPath = isAbsolute(value) ? value : resolve(process.cwd(), value);
  if (!existsSync(serviceAccountPath)) {
    throw new Error(`Firebase service account file not found: ${serviceAccountPath}`);
  }

  return JSON.parse(readFileSync(serviceAccountPath, "utf8")) as ServiceAccountJson;
}

function initFirebase() {
  const existingApp = getApps()[0];
  if (existingApp) {
    return existingApp;
  }

  const serviceAccount = readServiceAccount();
  const projectId =
    serviceAccount.projectId ??
    serviceAccount.project_id ??
    process.env.GCLOUD_PROJECT ??
    "medicare-track-af1cf";

  return initializeApp({
    credential: cert(serviceAccount),
    projectId
  });
}

async function ensureAuthUser(user: SeedUser) {
  const auth = getAuth();

  try {
    const existing = await auth.getUserByEmail(user.email);
    const update: UpdateRequest = {
      displayName: user.displayName,
      disabled: false
    };

    if (resetPasswords) {
      update.password = user.password;
    }

    await auth.updateUser(existing.uid, update);
    await auth.setCustomUserClaims(existing.uid, { role: user.role });
    return existing.uid;
  } catch (error) {
    if ((error as { code?: string }).code !== "auth/user-not-found") {
      throw error;
    }

    const created = await auth.createUser({
      email: user.email,
      password: user.password,
      displayName: user.displayName,
      emailVerified: true,
      disabled: false
    });
    await auth.setCustomUserClaims(created.uid, { role: user.role });
    return created.uid;
  }
}

function todayAt(time: string) {
  const match = /^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$/i.exec(time.trim());
  const date = new Date();
  let hour = 0;
  let minute = 0;

  if (match) {
    hour = Number.parseInt(match[1] ?? "0", 10);
    minute = Number.parseInt(match[2] ?? "0", 10);
    const modifier = (match[3] ?? "").toUpperCase();
    if (modifier === "PM" && hour < 12) {
      hour += 12;
    }
    if (modifier === "AM" && hour === 12) {
      hour = 0;
    }
  }

  date.setHours(hour, minute, 0, 0);
  return Timestamp.fromDate(date);
}

async function assertFirestoreReady(db: Firestore) {
  try {
    await db.listCollections();
  } catch (error) {
    const details = (error as { details?: string }).details ?? "";
    const reason = (error as { reason?: string }).reason ?? "";
    if (details.includes("Cloud Firestore API") || reason === "SERVICE_DISABLED") {
      throw new Error(
        "Cloud Firestore is not enabled yet for this Firebase project. " +
          "Create a Firestore database in Firebase Console first, then rerun this seed."
      );
    }
    throw error;
  }
}

async function main() {
  initFirebase();

  const db = getFirestore();
  const now = Timestamp.now();

  await assertFirestoreReady(db);

  const adminUser: SeedUser = {
    email: "admin@lifehouse.com",
    password: demoPassword,
    displayName: "Lifehouse Admin",
    role: "ADMIN",
    username: "admin"
  };
  const caregiverUser: SeedUser = {
    email: "sarah.reyes@lifehouse.com",
    password: demoPassword,
    displayName: "Sarah Reyes",
    role: "CAREGIVER",
    username: "sarah.reyes"
  };
  const familyUser: SeedUser = {
    email: "ryzamae@gmail.com",
    password: demoPassword,
    displayName: "Ryzamae Santos",
    role: "FAMILY",
    username: "ryzamae.family"
  };

  const [adminUid, caregiverUid, familyUid] = await Promise.all([
    ensureAuthUser(adminUser),
    ensureAuthUser(caregiverUser),
    ensureAuthUser(familyUser)
  ]);

  const residentId = "resident-ryzamae-santos";
  const medicationId = "medication-amlodipine";
  const medicationEventId = "medication-amlodipine-today-0800";
  const careTaskId = "care-task-blood-pressure";
  const familyConversationId = `family-${familyUid}`;
  const caregiverConversationId = `caregiver-${caregiverUid}`;

  const batch = db.batch();

  batch.set(
    db.doc("facilityInfo/details"),
    {
      name: "Lifehouse Nursing Home",
      contactNumber: "09171234567",
      email: "admin@lifehouse.com",
      address: "Lifehouse Care Facility",
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`users/${adminUid}`),
    {
      email: adminUser.email,
      username: adminUser.username,
      role: adminUser.role,
      status: "ACTIVE",
      notificationSetting,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`users/${caregiverUid}`),
    {
      email: caregiverUser.email,
      username: caregiverUser.username,
      role: caregiverUser.role,
      status: "ACTIVE",
      caregiverProfile: {
        displayName: caregiverUser.displayName,
        contactNumber: "09175550123",
        address: "Lifehouse Care Facility"
      },
      notificationSetting,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`users/${familyUid}`),
    {
      email: familyUser.email,
      username: familyUser.username,
      role: familyUser.role,
      status: "ACTIVE",
      familyProfile: {
        residentId,
        contactName: familyUser.displayName,
        relationship: "Daughter",
        contactNumber: "09171234567",
        secondaryContactNumber: null,
        address: "Quezon City"
      },
      notificationSetting,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`residents/${residentId}`),
    {
      name: "Ryzamae Santos",
      room: "201",
      age: 72,
      birthday: "1954-02-14",
      gender: "Female",
      address: "Lifehouse Care Facility",
      medicalNotes: "Monitor blood pressure and hydration.",
      overallStatus: "STABLE",
      conditions: [{ name: "Hypertension" }, { name: "Type 2 Diabetes" }],
      assignedCaregiverIds: [caregiverUid],
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`residentAssignments/${residentId}_${caregiverUid}`),
    {
      residentId,
      caregiverId: caregiverUid,
      state: "ASSIGNED",
      assignedAt: now,
      unassignedAt: null,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`medicineInventory/${medicationId}`),
    {
      name: "Amlodipine",
      count: 30,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc("medicineInventory/medicine-metformin"),
    {
      name: "Metformin",
      count: 24,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`medications/${medicationId}`),
    {
      residentId,
      name: "Amlodipine",
      dosage: "5mg",
      type: "Tablet",
      frequency: "Daily",
      startDate: now,
      duration: "Ongoing",
      reminders: [
        {
          id: "reminder-amlodipine-0800",
          time: "8:00 AM",
          meal: "After breakfast"
        }
      ],
      createdById: adminUid,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`medicationEvents/${medicationEventId}`),
    {
      medicationId,
      residentId,
      scheduledAt: todayAt("8:00 AM"),
      status: "PENDING",
      remark: null,
      updatedById: null,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`careTasks/${careTaskId}`),
    {
      residentId,
      title: "Blood pressure check",
      type: "Vitals",
      scheduledTime: "9:00 AM",
      frequency: "Daily",
      assignedCaregiverId: caregiverUid,
      createdById: adminUid,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`careTaskEvents/${careTaskId}`),
    {
      careTaskId,
      residentId,
      status: "PENDING",
      remark: null,
      timeCompleted: null,
      updatedById: null,
      updatedAt: todayAt("9:00 AM")
    },
    { merge: true }
  );

  batch.set(
    db.doc(`conversations/${familyConversationId}`),
    {
      residentId,
      type: "FAMILY",
      peerId: familyUid,
      memberIds: [adminUid, familyUid],
      lastMessage: {
        id: "welcome",
        conversationId: familyConversationId,
        senderId: adminUid,
        content: "Welcome to the family care thread for Ryzamae Santos.",
        createdAt: now
      },
      lastMessageAt: now,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`conversations/${familyConversationId}/messages/welcome`),
    {
      id: "welcome",
      conversationId: familyConversationId,
      senderId: adminUid,
      content: "Welcome to the family care thread for Ryzamae Santos.",
      reads: [{ userId: adminUid, readAt: now }],
      createdAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`conversations/${caregiverConversationId}`),
    {
      residentId: null,
      type: "CAREGIVER",
      peerId: caregiverUid,
      memberIds: [adminUid, caregiverUid],
      lastMessage: {
        id: "welcome",
        conversationId: caregiverConversationId,
        senderId: adminUid,
        content: "Welcome to the caregiver care thread for Ryzamae Santos.",
        createdAt: now
      },
      lastMessageAt: now,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`conversations/${caregiverConversationId}/messages/welcome`),
    {
      id: "welcome",
      conversationId: caregiverConversationId,
      senderId: adminUid,
      content: "Welcome to the caregiver care thread for Ryzamae Santos.",
      reads: [{ userId: adminUid, readAt: now }],
      createdAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`notifications/${caregiverConversationId}-welcome`),
    {
      userId: caregiverUid,
      category: "ADMIN_MESSAGE",
      title: "New message",
      body: "Welcome to the caregiver care thread for Ryzamae Santos.",
      data: {
        conversationId: caregiverConversationId,
        messageId: "welcome"
      },
      sourceKey: `message:welcome:${caregiverUid}`,
      readAt: null,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  batch.set(
    db.doc(`notifications/${familyConversationId}-welcome`),
    {
      userId: familyUid,
      category: "ADMIN_MESSAGE",
      title: "New message",
      body: "Welcome to the family care thread for Ryzamae Santos.",
      data: {
        conversationId: familyConversationId,
        messageId: "welcome"
      },
      sourceKey: `message:welcome:${familyUid}`,
      readAt: null,
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  await batch.commit();

  console.log("Firestore seed completed.");
  console.log({
    project: "medicare-track-af1cf",
    demoPassword,
    resetPasswords,
    users: {
      admin: adminUser.email,
      caregiver: caregiverUser.email,
      family: familyUser.email
    },
    resident: residentId
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
