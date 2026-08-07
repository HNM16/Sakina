import { z } from "zod";

/**
 * The message model.
 *
 * Two fields carry most of the design weight and must not be changed casually:
 *
 *   client_id — generated on the DEVICE before the message leaves it. It is the
 *               idempotency key. A client on a dying 3G connection retries the
 *               same send until it gets an ack; the server dedups on
 *               (chat_id, client_id) so the user never sees a double-send.
 *
 *   seq       — assigned by the SERVER, monotonic PER CHAT, gapless. It is the
 *               ordering key, the sync cursor, and the read-receipt cursor.
 *               Reconnect is "give me everything in chat X after seq N".
 *
 * `type` is an open enum on purpose. The whole super-app roadmap — payments in
 * a thread, utility-bill cards, mini-app results — arrives as new message types
 * on this same bus, not as a parallel system. Adding a type must never require
 * touching delivery, sync, or storage.
 */

export const Uuid = z.string().uuid();

/** Tajikistani somoni. Money is ALWAYS integer minor units (diram, 1/100 TJS). Never a float. */
export const Currency = z.literal("TJS");

export const MessageType = z.enum([
  "text",
  "media",
  "voice",
  "system",
  // Reserved. Not implemented in M0 — present so that storage, sync and the
  // client renderer are built against an open set from the first commit.
  "payment",
  "service_card",
]);
export type MessageType = z.infer<typeof MessageType>;

export const TextPayload = z.object({
  type: z.literal("text"),
  text: z.string().min(1).max(4096),
});

export const MediaPayload = z.object({
  type: z.literal("media"),
  key: z.string().min(1), // object-storage key, not a signed URL — URLs expire, keys don't
  mime: z.string().min(1),
  size: z.number().int().nonnegative(),
  width: z.number().int().positive().optional(),
  height: z.number().int().positive().optional(),
  caption: z.string().max(1024).optional(),
});

export const VoicePayload = z.object({
  type: z.literal("voice"),
  key: z.string().min(1),
  duration_ms: z.number().int().positive(),
  /** Coarse amplitude buckets for the waveform UI. Kept tiny — this ships over 3G. */
  waveform: z.array(z.number().int().min(0).max(31)).max(128).optional(),
});

export const SystemPayload = z.object({
  type: z.literal("system"),
  event: z.enum(["chat_created", "member_added", "member_removed", "title_changed"]),
  meta: z.record(z.string()).default({}),
});

/** Reserved for M4. Shaped now so the ledger and the chat agree on units from day one. */
export const PaymentPayload = z.object({
  type: z.literal("payment"),
  transaction_id: Uuid,
  amount_minor: z.number().int().positive(),
  currency: Currency,
  status: z.enum(["pending", "completed", "failed", "refunded"]),
  comment: z.string().max(256).optional(),
});

/** Reserved for M3. A bill, a receipt, a mini-app result — rendered as a card in the thread. */
export const ServiceCardPayload = z.object({
  type: z.literal("service_card"),
  service_id: z.string().min(1),
  title: z.string().min(1).max(128),
  body: z.string().max(2048).optional(),
  actions: z
    .array(z.object({ id: z.string(), label: z.string(), url: z.string().url().optional() }))
    .max(8)
    .default([]),
});

export const MessagePayload = z.discriminatedUnion("type", [
  TextPayload,
  MediaPayload,
  VoicePayload,
  SystemPayload,
  PaymentPayload,
  ServiceCardPayload,
]);
export type MessagePayload = z.infer<typeof MessagePayload>;

export const Message = z.object({
  id: Uuid,
  client_id: Uuid,
  chat_id: Uuid,
  sender_id: Uuid,
  seq: z.number().int().positive(),
  payload: MessagePayload,
  created_at: z.number().int(), // epoch ms, server clock — the client's clock is not trusted
  edited_at: z.number().int().nullable().default(null),
  deleted_at: z.number().int().nullable().default(null),
});
export type Message = z.infer<typeof Message>;

export const ChatKind = z.enum(["direct", "group", "channel"]);
export type ChatKind = z.infer<typeof ChatKind>;

/** `kind` is the super-app on-ramp: a bot is a user with a webhook. One column, reserved now. */
export const UserKind = z.enum(["human", "bot", "service"]);
export type UserKind = z.infer<typeof UserKind>;

export const PublicUser = z.object({
  id: Uuid,
  username: z.string().nullable(),
  display_name: z.string(),
  avatar_key: z.string().nullable(),
  kind: UserKind,
});
export type PublicUser = z.infer<typeof PublicUser>;

export const ChatSummary = z.object({
  id: Uuid,
  kind: ChatKind,
  title: z.string().nullable(),
  avatar_key: z.string().nullable(),
  last_seq: z.number().int().nonnegative(),
  read_up_to_seq: z.number().int().nonnegative(),
  members: z.array(PublicUser),
  last_message: Message.nullable(),
});
export type ChatSummary = z.infer<typeof ChatSummary>;
