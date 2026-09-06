import bcrypt from "bcryptjs";

const SALT_ROUNDS = 10;

export async function hashPassword(value: string): Promise<string> {
  return bcrypt.hash(value, SALT_ROUNDS);
}

export async function comparePassword(value: string, hash: string): Promise<boolean> {
  if (!hash || !hash.startsWith("$2")) {
    return false;
  }

  try {
    return await bcrypt.compare(value, hash);
  } catch {
    return false;
  }
}
