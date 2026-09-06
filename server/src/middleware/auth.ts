import type { NextFunction, Request, Response } from "express";
import jwt from "jsonwebtoken";
import { verifyAccessToken } from "../lib/jwt.js";
import { AppError } from "../utils/api.js";
import { prisma } from "../lib/prisma.js";

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      throw new AppError(401, "Missing access token", "UNAUTHORIZED");
    }

    const token = authHeader.slice(7);
    const payload = verifyAccessToken(token);

    const user = await prisma.user.findUnique({ where: { id: payload.userId } });
    if (!user || user.status !== "ACTIVE") {
      throw new AppError(401, "User is not active", "UNAUTHORIZED");
    }

    req.auth = { userId: user.id, role: user.role, email: user.email };
    next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      next(new AppError(401, "Session expired. Please log in again.", "TOKEN_EXPIRED"));
      return;
    }

    if (error instanceof jwt.JsonWebTokenError) {
      next(new AppError(401, "Invalid access token", "UNAUTHORIZED"));
      return;
    }

    next(error);
  }
}
