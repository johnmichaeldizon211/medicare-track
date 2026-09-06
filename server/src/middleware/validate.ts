import type { NextFunction, Request, Response } from "express";
import { ZodTypeAny } from "zod";
import { AppError } from "../utils/api.js";

export function validateBody(schema: ZodTypeAny) {
  return (req: Request, _res: Response, next: NextFunction) => {
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      return next(new AppError(400, "Invalid request body", "VALIDATION_ERROR", parsed.error.flatten()));
    }
    req.body = parsed.data;
    return next();
  };
}
