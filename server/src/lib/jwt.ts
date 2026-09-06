import jwt from "jsonwebtoken";
import { env } from "../config/env.js";

export type JwtPayload = {
  userId: string;
  role: "ADMIN" | "CAREGIVER" | "FAMILY";
};

const accessTokenExpiresIn = env.JWT_ACCESS_EXPIRES_IN as jwt.SignOptions["expiresIn"];
const refreshTokenExpiresIn = env.JWT_REFRESH_EXPIRES_IN as jwt.SignOptions["expiresIn"];

export function signAccessToken(payload: JwtPayload): string {
  return jwt.sign(payload, env.JWT_ACCESS_SECRET, {
    expiresIn: accessTokenExpiresIn
  });
}

export function signRefreshToken(payload: JwtPayload): string {
  return jwt.sign(payload, env.JWT_REFRESH_SECRET, {
    expiresIn: refreshTokenExpiresIn
  });
}

export function verifyAccessToken(token: string): JwtPayload {
  return jwt.verify(token, env.JWT_ACCESS_SECRET) as JwtPayload;
}

export function verifyRefreshToken(token: string): JwtPayload {
  return jwt.verify(token, env.JWT_REFRESH_SECRET) as JwtPayload;
}
