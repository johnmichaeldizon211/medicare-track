import { Router } from "express";
import jwt from "jsonwebtoken";
import { z } from "zod";
import { comparePassword, hashPassword } from "../../lib/password.js";
import { signAccessToken, signRefreshToken, verifyRefreshToken } from "../../lib/jwt.js";
import { prisma } from "../../lib/prisma.js";
import { generateOtpCode, hashToken } from "../../lib/otp.js";
import { addDurationToNow } from "../../lib/time.js";
import { env } from "../../config/env.js";
import { logger } from "../../config/logger.js";
import { asyncHandler } from "../../utils/async-handler.js";
import { AppError, ok } from "../../utils/api.js";
import { requireAuth } from "../../middleware/auth.js";
import { validateBody } from "../../middleware/validate.js";

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1)
});

const refreshSchema = z.object({
  refreshToken: z.string().min(10)
});

const forgotRequestSchema = z.object({
  email: z.string().email()
});

const forgotVerifySchema = z.object({
  email: z.string().email(),
  code: z.string().length(6)
});

const resetPasswordSchema = z.object({
  email: z.string().email(),
  code: z.string().length(6),
  newPassword: z.string().min(6)
});

async function issueTokens(user: { id: string; role: "ADMIN" | "CAREGIVER" | "FAMILY" }) {
  const accessToken = signAccessToken({ userId: user.id, role: user.role });
  const refreshToken = signRefreshToken({ userId: user.id, role: user.role });
  const tokenHash = hashToken(refreshToken);

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash,
      expiresAt: addDurationToNow(env.JWT_REFRESH_EXPIRES_IN)
    }
  });

  return { accessToken, refreshToken };
}

function parseRefreshTokenOrThrow(refreshToken: string) {
  try {
    return verifyRefreshToken(refreshToken);
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw new AppError(401, "Session expired. Please log in again.", "TOKEN_EXPIRED");
    }

    if (error instanceof jwt.JsonWebTokenError) {
      throw new AppError(401, "Invalid refresh token", "INVALID_REFRESH_TOKEN");
    }

    throw error;
  }
}

export const authRouter = Router();

authRouter.post(
  "/register/family",
  asyncHandler(async () => {
    throw new AppError(
      403,
      "Account creation is restricted to admins.",
      "ADMIN_ONLY_ACCOUNT_CREATION"
    );
  })
);

authRouter.post(
  "/login",
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const payload = req.body as z.infer<typeof loginSchema>;
    const normalizedEmail = payload.email.trim().toLowerCase();
    const user = await prisma.user.findUnique({ where: { email: normalizedEmail } });

    if (!user) {
      throw new AppError(401, "Invalid credentials", "INVALID_CREDENTIALS");
    }

    const isValid = await comparePassword(payload.password, user.passwordHash);
    if (!isValid) {
      throw new AppError(401, "Invalid credentials", "INVALID_CREDENTIALS");
    }

    if (user.status !== "ACTIVE") {
      throw new AppError(
        403,
        "Your account has been disabled by the administrator. Please contact support/admin.",
        "USER_DISABLED"
      );
    }

    const tokens = await issueTokens({ id: user.id, role: user.role });
    res.json(ok({ user: { id: user.id, email: user.email, role: user.role }, tokens }));
  })
);

authRouter.post(
  "/refresh",
  validateBody(refreshSchema),
  asyncHandler(async (req, res) => {
    const { refreshToken } = req.body as z.infer<typeof refreshSchema>;
    const payload = parseRefreshTokenOrThrow(refreshToken);
    const tokenHash = hashToken(refreshToken);

    const existing = await prisma.refreshToken.findFirst({
      where: {
        userId: payload.userId,
        tokenHash,
        revokedAt: null,
        expiresAt: { gt: new Date() }
      }
    });

    if (!existing) {
      throw new AppError(401, "Invalid refresh token", "INVALID_REFRESH_TOKEN");
    }

    await prisma.refreshToken.update({
      where: { id: existing.id },
      data: { revokedAt: new Date() }
    });

    const user = await prisma.user.findUnique({ where: { id: payload.userId } });
    if (!user || user.status !== "ACTIVE") {
      throw new AppError(401, "User not active", "UNAUTHORIZED");
    }

    const tokens = await issueTokens({ id: user.id, role: user.role });
    res.json(ok(tokens));
  })
);

authRouter.post(
  "/logout",
  validateBody(refreshSchema),
  asyncHandler(async (req, res) => {
    const { refreshToken } = req.body as z.infer<typeof refreshSchema>;
    const tokenHash = hashToken(refreshToken);

    await prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() }
    });

    res.json(ok({ loggedOut: true }));
  })
);

authRouter.post(
  "/forgot-password/request",
  validateBody(forgotRequestSchema),
  asyncHandler(async (req, res) => {
    const { email } = req.body as z.infer<typeof forgotRequestSchema>;
    const user = await prisma.user.findUnique({ where: { email } });

    if (!user || user.status !== "ACTIVE") {
      res.json(ok({ sent: true }));
      return;
    }

    const code = generateOtpCode();
    await prisma.passwordResetOtp.create({
      data: {
        userId: user.id,
        email,
        code: hashToken(code),
        expiresAt: addDurationToNow("10m")
      }
    });

    if (env.NODE_ENV !== "production") {
      logger.warn({ email, code }, "Development OTP generated; configure email delivery before production");
    }

    res.json(ok({ sent: true }));
  })
);

authRouter.post(
  "/forgot-password/verify",
  validateBody(forgotVerifySchema),
  asyncHandler(async (req, res) => {
    const { email, code } = req.body as z.infer<typeof forgotVerifySchema>;
    const codeHash = hashToken(code);

    const otp = await prisma.passwordResetOtp.findFirst({
      where: {
        email,
        code: codeHash,
        verifiedAt: null,
        expiresAt: { gt: new Date() }
      },
      orderBy: { createdAt: "desc" }
    });

    if (!otp) {
      throw new AppError(400, "Invalid or expired OTP", "INVALID_OTP");
    }

    await prisma.passwordResetOtp.update({
      where: { id: otp.id },
      data: { verifiedAt: new Date() }
    });

    res.json(ok({ verified: true }));
  })
);

authRouter.post(
  "/reset-password",
  validateBody(resetPasswordSchema),
  asyncHandler(async (req, res) => {
    const { email, code, newPassword } = req.body as z.infer<typeof resetPasswordSchema>;
    const codeHash = hashToken(code);

    const otp = await prisma.passwordResetOtp.findFirst({
      where: {
        email,
        code: codeHash,
        verifiedAt: { not: null },
        expiresAt: { gt: new Date() }
      },
      orderBy: { createdAt: "desc" }
    });

    if (!otp) {
      throw new AppError(400, "Invalid OTP reset request", "INVALID_OTP_RESET");
    }

    const passwordHash = await hashPassword(newPassword);
    const now = new Date();
    await prisma.$transaction([
      prisma.user.update({ where: { id: otp.userId }, data: { passwordHash } }),
      prisma.passwordResetOtp.update({
        where: { id: otp.id },
        data: { expiresAt: now }
      }),
      prisma.refreshToken.updateMany({
        where: { userId: otp.userId, revokedAt: null },
        data: { revokedAt: now }
      })
    ]);

    res.json(ok({ reset: true }));
  })
);

authRouter.get(
  "/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({
      where: { id: req.auth!.userId },
      include: {
        familyProfile: true,
        caregiverProfile: true,
        notificationSetting: true
      }
    });

    if (!user) {
      throw new AppError(404, "User not found", "USER_NOT_FOUND");
    }

    res.json(ok(user));
  })
);
