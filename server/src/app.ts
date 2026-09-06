import cors from "cors";
import express from "express";
import cookieParser from "cookie-parser";
import pinoHttp from "pino-http";
import { logger } from "./config/logger.js";
import { corsOptions } from "./config/cors.js";
import { rootRouter } from "./routes/index.js";
import { errorHandler, notFoundHandler } from "./middleware/error.js";

export function createApp() {
  const app = express();

  app.use(
    cors(corsOptions)
  );

  app.use(express.json({ limit: "2mb" }));
  app.use(cookieParser());
  app.use(pinoHttp({ logger }));

  app.use(rootRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
