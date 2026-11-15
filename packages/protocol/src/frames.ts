import { z } from "zod";
import { ChatSummary, Message, MessagePayload, PublicUser, Uuid } from "./message.js";

/**
 * The realtime wire protocol.
 *
 * One persistent WebSocket per DEVICE (not per user — multi-device is a day-one
 * constraint, see docs/ARCHITECTURE.md). Every frame is `{ t, d }`: a short tag
 * and a payload. HTTP is used only for auth bootstrap, media transfer, and deep
 * history backfill; everything else lives on this socket.
 *
 * Format is JSON for M0 because it is debuggable and Dart/TS agree on it for
 * free. It is expected to become protobuf around M2, once the frame set stops
 * churning and per-MB cost starts to matter. Keep the envelope keys short and
 * the payloads flat so that swap is mechanical.
 */

export const PROTOCOL_VERSION = 1;

// ---------------------------------------------------------------------------
// Client -> Server
// ---------------------------------------------------------------------------

/** Must be the first frame on a new socket. The socket is unauthenticated until `ready` comes back. */
export const HelloFrame = z.object({
  t: z.literal("hello"),
  d: z.object({
    v: z.number().int().default(PROTOCOL_VERSION),
    token: z.string().min(1), // short-lived access JWT
    device_id: Uuid,
  }),
});

export const SendFrame = z.object({
  t: z.literal("send"),
  d: z.object({
    client_id: Uuid, // idempotency key — resend verbatim on retry, never regenerate
    chat_id: Uuid,
    payload: MessagePayload,
  }),
});

/** Read receipts are a cursor, not per-message flags: O(1) per member instead of O(messages). */
export const ReadFrame = z.object({
  t: z.literal("read"),
  d: z.object({ chat_id: Uuid, up_to_seq: z.number().int().nonnegative() }),
});

export const TypingFrame = z.object({
  t: z.literal("typing"),
  d: z.object({ chat_id: Uuid }),
});

/** Reconnect path: "here is where I got to in each chat, send me the diff". */
export const SyncFrame = z.object({
  t: z.literal("sync"),
  d: z.object({
    cursors: z
      .array(z.object({ chat_id: Uuid, last_seq: z.number().int().nonnegative() }))
      .max(500),
  }),
});

export const PingFrame = z.object({ t: z.literal("ping"), d: z.object({}).default({}) });

export const ClientFrame = z.discriminatedUnion("t", [
  HelloFrame,
  SendFrame,
  ReadFrame,
  TypingFrame,
  SyncFrame,
  PingFrame,
]);
export type ClientFrame = z.infer<typeof ClientFrame>;

// ---------------------------------------------------------------------------
// Server -> Client
// ---------------------------------------------------------------------------

export const ReadyFrame = z.object({
  t: z.literal("ready"),
  d: z.object({
    user: PublicUser,
    server_time: z.number().int(),
    chats: z.array(ChatSummary),
  }),
});

/** A message addressed to this client. Also echoed to the sender's OTHER devices. */
export const MessageFrame = z.object({ t: z.literal("message"), d: Message });

/**
 * A chat appeared, or something about it changed.
 *
 * Sent when someone is added to a group or channel, when a title changes, and
 * when a member leaves. Without it, being added to a group is invisible until
 * the client next reconnects — which on a phone that stays connected for hours
 * means the group simply does not exist yet as far as the user can tell.
 *
 * It carries the whole summary rather than a delta: chat summaries are small,
 * they change rarely, and a client applying a patch it cannot fully order is a
 * bug generator. The client upserts by id.
 */
export const ChatFrame = z.object({ t: z.literal("chat"), d: ChatSummary });

/** A chat is gone for this user — they left, or were removed. */
export const ChatRemovedFrame = z.object({
  t: z.literal("chat_removed"),
  d: z.object({ chat_id: Uuid }),
});

/** Ack of the sender's own `send`. Carries the server-assigned seq — the client
 *  swaps its optimistic local row for this and flips state to `sent`. */
export const SentFrame = z.object({
  t: z.literal("sent"),
  d: z.object({
    client_id: Uuid,
    chat_id: Uuid,
    id: Uuid,
    seq: z.number().int().positive(),
    created_at: z.number().int(),
  }),
});

export const ReadReceiptFrame = z.object({
  t: z.literal("read"),
  d: z.object({ chat_id: Uuid, user_id: Uuid, up_to_seq: z.number().int().nonnegative() }),
});

export const TypingNoticeFrame = z.object({
  t: z.literal("typing"),
  d: z.object({ chat_id: Uuid, user_id: Uuid }),
});

export const SyncResultFrame = z.object({
  t: z.literal("sync"),
  d: z.object({
    chat_id: Uuid,
    messages: z.array(Message),
    /** True when the client is too far behind to catch up on the socket and
     *  should backfill over HTTP instead. */
    has_more: z.boolean(),
  }),
});

export const ErrorCode = z.enum([
  "bad_frame",
  "unauthorized",
  "forbidden",
  "not_found",
  "rate_limited",
  "payload_too_large",
  "internal",
]);
export type ErrorCode = z.infer<typeof ErrorCode>;

export const ErrorFrame = z.object({
  t: z.literal("error"),
  d: z.object({
    code: ErrorCode,
    message: z.string(),
    /** Echoes the client_id of the frame that failed, when there was one. */
    ref: z.string().optional(),
  }),
});

export const PongFrame = z.object({ t: z.literal("pong"), d: z.object({}).default({}) });

export const ServerFrame = z.discriminatedUnion("t", [
  ChatFrame,
  ChatRemovedFrame,
  ReadyFrame,
  MessageFrame,
  SentFrame,
  ReadReceiptFrame,
  TypingNoticeFrame,
  SyncResultFrame,
  ErrorFrame,
  PongFrame,
]);
export type ServerFrame = z.infer<typeof ServerFrame>;

export function encodeFrame(frame: ServerFrame): string {
  return JSON.stringify(frame);
}

export function decodeClientFrame(raw: string): ClientFrame | null {
  try {
    const parsed = ClientFrame.safeParse(JSON.parse(raw));
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}
