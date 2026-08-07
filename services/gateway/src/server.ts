import { createServer, type Server } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { createDb } from "@sakina/db";
import { chatsRepo, createTokenSigner, DomainError, messagesRepo, usersRepo } from "@sakina/core";
import {
  decodeClientFrame,
  PROTOCOL_VERSION,
  type ClientFrame,
  type ErrorCode,
  type ServerFrame,
} from "@sakina/protocol";
import { createBus } from "./bus.js";
import { ConnectionRegistry, sendFrame, type Connection } from "./registry.js";
import type { Env } from "./env.js";

/** A socket that has not said `hello` in this long is closed. */
const HELLO_TIMEOUT_MS = 10_000;
const HEARTBEAT_INTERVAL_MS = 30_000;
/** Per chat, per sync frame. Beyond this the client is told to backfill over HTTP. */
const SYNC_PAGE_SIZE = 200;

export async function startGateway(env: Env) {
  const { db, sql } = createDb(env.DATABASE_URL);
  const signer = createTokenSigner(env.JWT_SECRET);
  const registry = new ConnectionRegistry();

  const bus = createBus(env.REDIS_URL, (envelope) => {
    registry.deliver(envelope.user_ids, envelope.frame, envelope.exclude_device_id);
  });

  const httpServer: Server = createServer((req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, service: "gateway", connections: registry.size }));
      return;
    }
    res.writeHead(404).end();
  });

  const wss = new WebSocketServer({ server: httpServer, path: "/ws", maxPayload: 256 * 1024 });

  wss.on("connection", (socket: WebSocket) => {
    let conn: Connection | null = null;

    const helloTimer = setTimeout(() => {
      if (!conn) {
        fail(socket, "unauthorized", "no hello frame");
        socket.close();
      }
    }, HELLO_TIMEOUT_MS);

    socket.on("pong", () => {
      if (conn) conn.alive = true;
    });

    socket.on("message", (raw) => {
      void (async () => {
        const frame = decodeClientFrame(raw.toString());
        if (!frame) return fail(socket, "bad_frame", "unparseable frame");

        try {
          if (!conn) {
            if (frame.t !== "hello") return fail(socket, "unauthorized", "expected hello");
            conn = await handleHello(frame, socket);
            if (conn) clearTimeout(helloTimer);
            return;
          }

          await handleFrame(conn, frame);
        } catch (err) {
          if (err instanceof DomainError) {
            return fail(socket, toErrorCode(err.code), err.message, refOf(frame));
          }
          console.error("gateway frame error:", err);
          fail(socket, "internal", "internal error", refOf(frame));
        }
      })();
    });

    socket.on("close", () => {
      clearTimeout(helloTimer);
      if (conn) registry.remove(conn);
    });

    socket.on("error", () => {
      clearTimeout(helloTimer);
      if (conn) registry.remove(conn);
    });
  });

  async function handleHello(
    frame: Extract<ClientFrame, { t: "hello" }>,
    socket: WebSocket,
  ): Promise<Connection | null> {
    if (frame.d.v !== PROTOCOL_VERSION) {
      fail(socket, "bad_frame", `unsupported protocol version ${frame.d.v}`);
      socket.close();
      return null;
    }

    const claims = await signer.verifyAccessToken(frame.d.token);
    if (!claims) {
      fail(socket, "unauthorized", "invalid token");
      socket.close();
      return null;
    }

    // The token is bound to a device; a token replayed from a different install
    // is refused rather than silently accepted.
    if (claims.did !== frame.d.device_id) {
      fail(socket, "unauthorized", "token does not match device");
      socket.close();
      return null;
    }

    const user = await usersRepo.findById(db, claims.sub);
    if (!user) {
      fail(socket, "unauthorized", "unknown user");
      socket.close();
      return null;
    }

    const connection: Connection = {
      socket,
      userId: claims.sub,
      deviceId: claims.did,
      alive: true,
      sendCount: 0,
      windowStartedAt: Date.now(),
    };

    const replaced = registry.add(connection);
    if (replaced && replaced.socket !== socket) replaced.socket.close();

    await usersRepo.touchDevice(db, claims.did);
    const chats = await chatsRepo.listChatsForUser(db, claims.sub);

    sendFrame(socket, {
      t: "ready",
      d: {
        user: usersRepo.toPublicUser(user),
        server_time: Date.now(),
        chats,
      },
    });

    return connection;
  }

  async function handleFrame(conn: Connection, frame: ClientFrame): Promise<void> {
    switch (frame.t) {
      case "hello":
        return; // already authenticated; ignore duplicates
      case "ping":
        return sendFrame(conn.socket, { t: "pong", d: {} });
      case "send":
        return handleSend(conn, frame);
      case "read":
        return handleRead(conn, frame);
      case "typing":
        return handleTyping(conn, frame);
      case "sync":
        return handleSync(conn, frame);
    }
  }

  async function handleSend(
    conn: Connection,
    frame: Extract<ClientFrame, { t: "send" }>,
  ): Promise<void> {
    if (!withinRateLimit(conn, env)) {
      throw new DomainError("rate_limited", "too many messages; slow down");
    }

    const { message, deduped } = await messagesRepo.insertMessage(db, {
      chatId: frame.d.chat_id,
      senderId: conn.userId,
      clientId: frame.d.client_id,
      payload: frame.d.payload,
    });

    // The ack goes back even on a dedup: the client is retrying precisely
    // because it never saw one, and it needs the seq to settle its local row.
    sendFrame(conn.socket, {
      t: "sent",
      d: {
        client_id: message.client_id,
        chat_id: message.chat_id,
        id: message.id,
        seq: message.seq,
        created_at: message.created_at,
      },
    });

    if (deduped) return;

    const memberIds = await chatsRepo.getMemberIds(db, frame.d.chat_id);
    await bus.publish({
      user_ids: memberIds,
      frame: { t: "message", d: message },
      // Everyone gets the message — including the sender's other devices. Only
      // the device that sent it is skipped, since it already got the ack.
      exclude_device_id: conn.deviceId,
    });
  }

  async function handleRead(
    conn: Connection,
    frame: Extract<ClientFrame, { t: "read" }>,
  ): Promise<void> {
    if (!(await chatsRepo.isMember(db, frame.d.chat_id, conn.userId))) {
      throw new DomainError("forbidden", "not a member of this chat");
    }

    await chatsRepo.setReadCursor(db, frame.d.chat_id, conn.userId, frame.d.up_to_seq);

    const memberIds = await chatsRepo.getMemberIds(db, frame.d.chat_id);
    await bus.publish({
      user_ids: memberIds,
      frame: {
        t: "read",
        d: { chat_id: frame.d.chat_id, user_id: conn.userId, up_to_seq: frame.d.up_to_seq },
      },
      exclude_device_id: conn.deviceId,
    });
  }

  async function handleTyping(
    conn: Connection,
    frame: Extract<ClientFrame, { t: "typing" }>,
  ): Promise<void> {
    const memberIds = await chatsRepo.getMemberIds(db, frame.d.chat_id);
    if (!memberIds.includes(conn.userId)) {
      throw new DomainError("forbidden", "not a member of this chat");
    }

    // Typing is ephemeral and never stored — it does not consume a seq.
    await bus.publish({
      user_ids: memberIds.filter((id) => id !== conn.userId),
      frame: { t: "typing", d: { chat_id: frame.d.chat_id, user_id: conn.userId } },
    });
  }

  /**
   * The reconnect path. The client says where it got to in each chat and gets
   * the diff — this is the whole point of a per-chat seq. A client that has been
   * offline for a week is told `has_more` and backfills over HTTP instead of
   * dragging a week of history through the socket.
   */
  async function handleSync(
    conn: Connection,
    frame: Extract<ClientFrame, { t: "sync" }>,
  ): Promise<void> {
    for (const cursor of frame.d.cursors) {
      if (!(await chatsRepo.isMember(db, cursor.chat_id, conn.userId))) continue;

      const { messages, hasMore } = await messagesRepo.getHistory(db, {
        chatId: cursor.chat_id,
        afterSeq: cursor.last_seq,
        limit: SYNC_PAGE_SIZE,
      });

      sendFrame(conn.socket, {
        t: "sync",
        d: { chat_id: cursor.chat_id, messages, has_more: hasMore },
      });
    }
  }

  const heartbeat = setInterval(() => {
    for (const conn of registry.all()) {
      if (!conn.alive) {
        registry.remove(conn);
        conn.socket.terminate();
        continue;
      }
      conn.alive = false;
      conn.socket.ping();
    }
  }, HEARTBEAT_INTERVAL_MS);

  await new Promise<void>((resolve) => {
    httpServer.listen(env.GATEWAY_PORT, env.GATEWAY_HOST, resolve);
  });

  console.log(`gateway listening on ws://${env.GATEWAY_HOST}:${env.GATEWAY_PORT}/ws`);

  return {
    registry,
    async close() {
      clearInterval(heartbeat);
      for (const conn of registry.all()) conn.socket.close();
      wss.close();
      await new Promise<void>((resolve) => httpServer.close(() => resolve()));
      await bus.close();
      await sql.end();
    },
  };
}

function withinRateLimit(conn: Connection, env: Env): boolean {
  const now = Date.now();
  if (now - conn.windowStartedAt > env.SEND_RATE_WINDOW_MS) {
    conn.windowStartedAt = now;
    conn.sendCount = 0;
  }
  conn.sendCount += 1;
  return conn.sendCount <= env.SEND_RATE_LIMIT;
}

function refOf(frame: ClientFrame): string | undefined {
  return frame.t === "send" ? frame.d.client_id : undefined;
}

function toErrorCode(code: DomainError["code"]): ErrorCode {
  switch (code) {
    case "unauthorized":
      return "unauthorized";
    case "forbidden":
      return "forbidden";
    case "not_found":
      return "not_found";
    case "rate_limited":
      return "rate_limited";
    case "bad_request":
    case "conflict":
      return "bad_frame";
    case "internal":
      return "internal";
  }
}

function fail(socket: WebSocket, code: ErrorCode, message: string, ref?: string): void {
  const frame: ServerFrame = { t: "error", d: { code, message, ...(ref ? { ref } : {}) } };
  sendFrame(socket, frame);
}
