import { applicationDefault, cert, getApps, initializeApp } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { env } from "../config/env.js";
import { logger } from "../config/logger.js";

export const HIGH_IMPORTANCE_ANDROID_CHANNEL_ID =
  "medicare_tract_high_importance_sound_v2";

function readServiceAccountJson(value: string) {
  const trimmed = value.trim();
  if (trimmed.startsWith("{")) {
    return JSON.parse(trimmed);
  }

  const serviceAccountPath = isAbsolute(trimmed)
    ? trimmed
    : resolve(process.cwd(), trimmed);
  if (!existsSync(serviceAccountPath)) {
    throw new Error(`Firebase service account file not found: ${serviceAccountPath}`);
  }

  return JSON.parse(readFileSync(serviceAccountPath, "utf8"));
}

function getFirebaseApp() {
  const existingApp = getApps()[0];
  if (existingApp) {
    return existingApp;
  }

  try {
    if (env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim()) {
      const serviceAccount = readServiceAccountJson(
        env.FIREBASE_SERVICE_ACCOUNT_JSON
      );
      return initializeApp({ credential: cert(serviceAccount) });
    }

    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      return initializeApp({ credential: applicationDefault() });
    }
  } catch (error) {
    logger.error({ err: error }, "Failed to initialize Firebase Admin SDK");
  }

  return null;
}

export function isFirebasePushConfigured() {
  return getFirebaseApp() !== null;
}

function stringifyData(data: Record<string, unknown>) {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined || value === null) {
      continue;
    }
    result[key] =
      typeof value === "string" ? value : JSON.stringify(value);
  }
  return result;
}

export async function sendHighPriorityPush({
  tokens,
  title,
  body,
  data
}: {
  tokens: string[];
  title: string;
  body: string;
  data: Record<string, unknown>;
}) {
  const uniqueTokens = Array.from(new Set(tokens.filter(Boolean)));
  if (uniqueTokens.length === 0) {
    return;
  }

  const app = getFirebaseApp();
  if (!app) {
    logger.warn(
      "Firebase credentials are not configured; skipping FCM push delivery"
    );
    return;
  }

  await getMessaging(app).sendEachForMulticast({
    tokens: uniqueTokens,
    notification: {
      title,
      body
    },
    data: stringifyData(data),
    android: {
      priority: "high",
      notification: {
        channelId: HIGH_IMPORTANCE_ANDROID_CHANNEL_ID,
        priority: "max",
        defaultSound: true,
        defaultVibrateTimings: true
      }
    },
    apns: {
      payload: {
        aps: {
          sound: "default"
        }
      }
    }
  });
}
