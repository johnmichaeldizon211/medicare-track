import type { CorsOptionsDelegate } from "cors";
import { env } from "./env.js";

const localhostPattern = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i;

function normalizeOrigins(value: string) {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function isAllowedOrigin(origin: string) {
  const configured = normalizeOrigins(env.APP_ORIGIN);

  if (configured.includes("*")) {
    return true;
  }

  if (configured.includes(origin)) {
    return true;
  }

  // In development/test, allow local web origins (Flutter web uses dynamic ports).
  if (env.NODE_ENV !== "production" && localhostPattern.test(origin)) {
    return true;
  }

  return false;
}

export const corsOptions: CorsOptionsDelegate = (req, callback) => {
  const rawOrigin = req.headers?.origin;
  const requestOrigin = Array.isArray(rawOrigin) ? rawOrigin[0] : rawOrigin;

  // Non-browser clients or same-origin requests may not send Origin.
  if (!requestOrigin) {
    callback(null, { origin: true, credentials: true });
    return;
  }

  if (isAllowedOrigin(requestOrigin)) {
    callback(null, { origin: true, credentials: true });
    return;
  }

  callback(new Error(`Origin not allowed by CORS: ${requestOrigin}`), {
    origin: false
  });
};

export function socketCorsOrigin(origin: string | undefined, callback: (err: Error | null, allow?: boolean) => void) {
  if (!origin || isAllowedOrigin(origin)) {
    callback(null, true);
    return;
  }

  callback(new Error(`Origin not allowed by CORS: ${origin}`));
}
