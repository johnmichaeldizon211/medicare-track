import http from "node:http";
import { createApp } from "./app.js";
import { env } from "./config/env.js";
import { logger } from "./config/logger.js";
import { startReminderNotificationScheduler } from "./routes/v1/api.routes.js";
import { initSocket } from "./socket/index.js";

const app = createApp();
const server = http.createServer(app);

initSocket(server);

server.listen(env.PORT, env.HOST, () => {
  logger.info(`Server listening on http://${env.HOST}:${env.PORT}`);
  startReminderNotificationScheduler();
});
