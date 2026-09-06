import crypto from "node:crypto";

export function generateOtpCode(): string {
  return String(crypto.randomInt(100000, 999999));
}

export function hashToken(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}
