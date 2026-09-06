import type { Server as HttpServer } from "http";
import { ConversationType } from "@prisma/client";
import { Server } from "socket.io";
import { socketCorsOrigin } from "../config/cors.js";
import { verifyAccessToken } from "../lib/jwt.js";
import { prisma } from "../lib/prisma.js";

let io: Server | null = null;

export function initSocket(server: HttpServer) {
  io = new Server(server, {
    cors: {
      origin: socketCorsOrigin,
      credentials: true
    }
  });

  io.use(async (socket, next) => {
    try {
      const header = socket.handshake.headers.authorization;
      const tokenFromHeader =
        typeof header === "string" && header.startsWith("Bearer ")
          ? header.slice(7)
          : null;
      const tokenFromAuth =
        typeof socket.handshake.auth?.token === "string"
          ? socket.handshake.auth.token
          : null;
      const token = tokenFromHeader ?? tokenFromAuth;

      if (!token) {
        next(new Error("Unauthorized"));
        return;
      }

      const payload = verifyAccessToken(token);
      const user = await prisma.user.findUnique({ where: { id: payload.userId } });
      if (!user || user.status !== "ACTIVE") {
        next(new Error("Unauthorized"));
        return;
      }

      socket.data.userId = user.id;
      socket.data.role = user.role;
      next();
    } catch (_) {
      next(new Error("Unauthorized"));
    }
  });

  io.on("connection", (socket) => {
    const userId = socket.data.userId as string | undefined;
    if (userId) {
      socket.join(`user:${userId}`);
    }

    socket.on("conversation:join", async (payload: { conversationId: string }) => {
      const conversationId = payload?.conversationId;
      const userId = socket.data.userId as string | undefined;
      const role = socket.data.role as string | undefined;
      if (!conversationId || !userId) {
        return;
      }

      const peerAccessFilter =
        role === "ADMIN"
          ? {}
          : {
              peerId: userId,
              type:
                role === "CAREGIVER"
                  ? ConversationType.CAREGIVER
                  : ConversationType.FAMILY
            };

      const membership = await prisma.conversationMember.findFirst({
        where: {
          conversationId,
          userId,
          conversation: {
            ...peerAccessFilter,
            peer: {
              status: "ACTIVE"
            }
          }
        },
        select: { id: true }
      });

      if (membership) {
        socket.join(`conversation:${conversationId}`);
      }
    });
  });

  return io;
}

export function getIo() {
  return io;
}
