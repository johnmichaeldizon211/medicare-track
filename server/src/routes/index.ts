import { Router } from "express";
import { authRouter } from "./v1/auth.routes.js";
import { apiRouter } from "./v1/api.routes.js";

export const rootRouter = Router();

rootRouter.get("/", (_req, res) => {
  res.json({
    success: true,
    data: {
      message: "Medicare Track API is running",
      health: "/health",
      authBase: "/api/v1/auth",
      apiBase: "/api/v1"
    }
  });
});

rootRouter.get("/health", (_req, res) => {
  res.json({ success: true, data: { status: "ok" } });
});

rootRouter.use("/api/v1/auth", authRouter);
rootRouter.use("/api/v1", apiRouter);
