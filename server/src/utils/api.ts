export class AppError extends Error {
  statusCode: number;
  code: string;
  details?: unknown;

  constructor(statusCode: number, message: string, code = "APP_ERROR", details?: unknown) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

function stripSensitiveFields<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.map(stripSensitiveFields) as T;
  }

  if (value instanceof Date || value === null || typeof value !== "object") {
    return value;
  }

  const safe: Record<string, unknown> = {};
  for (const [key, nestedValue] of Object.entries(value as Record<string, unknown>)) {
    if (key === "passwordHash") {
      continue;
    }
    safe[key] = stripSensitiveFields(nestedValue);
  }

  return safe as T;
}

export function ok<T>(data: T) {
  return { success: true, data: stripSensitiveFields(data) } as const;
}

export function fail(code: string, message: string, details?: unknown) {
  return { success: false, error: { code, message, details } } as const;
}
