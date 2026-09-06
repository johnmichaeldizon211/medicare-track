import type { NextFunction, Request, Response } from "express";
import { AppError } from "../utils/api.js";

export function requireRole(...roles: Array<"ADMIN" | "CAREGIVER" | "FAMILY">) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.auth) {
      return next(new AppError(401, "Unauthorized", "UNAUTHORIZED"));
    }

    if (!roles.includes(req.auth.role)) {
      return next(new AppError(403, "Forbidden", "FORBIDDEN"));
    }

    return next();
  };
}
