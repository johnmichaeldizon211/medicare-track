import type { NextFunction, Request, Response } from "express";
import { Prisma } from "@prisma/client";
import { ZodError } from "zod";
import { logger } from "../config/logger.js";
import { AppError, fail } from "../utils/api.js";

export function notFoundHandler(_req: Request, res: Response) {
  res.status(404).json(fail("NOT_FOUND", "Route not found"));
}

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json(fail(err.code, err.message, err.details));
  }

  if (err instanceof ZodError) {
    return res.status(400).json(fail("VALIDATION_ERROR", "Invalid input", err.flatten()));
  }

  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === "P2002") {
      const target = Array.isArray(err.meta?.target)
        ? err.meta?.target.map(String)
        : [String(err.meta?.target ?? "")];

      if (target.includes("email")) {
        return res.status(409).json(fail("EMAIL_EXISTS", "Email already used"));
      }

      if (target.includes("username")) {
        return res.status(409).json(fail("USERNAME_EXISTS", "Username already used"));
      }

      return res.status(409).json(fail("DUPLICATE_VALUE", "Duplicate value already exists"));
    }
  }

  logger.error({ err }, "Unhandled error");
  return res.status(500).json(fail("INTERNAL_SERVER_ERROR", "Unexpected server error"));
}
