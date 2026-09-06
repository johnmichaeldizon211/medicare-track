import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const isTestMode = process.env.NODE_ENV === "test";
const envSource = {
  ...process.env,
  NODE_ENV: process.env.NODE_ENV ?? (isTestMode ? "test" : "development"),
  DATABASE_URL:
    process.env.DATABASE_URL ??
    (isTestMode ? "mysql://root@localhost:3306/medicare_track" : undefined),
  JWT_ACCESS_SECRET:
    process.env.JWT_ACCESS_SECRET ?? (isTestMode ? "test-access-secret-1234567890" : undefined),
  JWT_REFRESH_SECRET:
    process.env.JWT_REFRESH_SECRET ?? (isTestMode ? "test-refresh-secret-1234567890" : undefined)
};

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(4000),
  HOST: z.string().default("0.0.0.0"),
  DATABASE_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(16),
  JWT_REFRESH_SECRET: z.string().min(16),
  JWT_ACCESS_EXPIRES_IN: z.string().default("15m"),
  JWT_REFRESH_EXPIRES_IN: z.string().default("7d"),
  APP_ORIGIN: z.string().default("http://localhost:3000"),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().optional()
});

const parsed = envSchema.safeParse(envSource);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error("Invalid environment configuration", parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
