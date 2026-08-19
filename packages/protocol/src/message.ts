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

/**
 * The languages Sakina speaks, in priority order. The order is the policy and
 * is relied on by the clients: Flutter's locale resolution falls through to the
 * first entry, so a phone set to Uzbek or Kazakh lands on Russian.
 *
 * Russian first because it is the language every part of the audience can read
 * — in Dushanbe, in the generations schooled in it, and among the migrant
 * workers in Russia who are a large share of who this is for. Tajik second
 * because it is the country's language and the reason the font is not
 * negotiable (ғ ӣ қ ӯ ҳ ҷ). English third, for the diaspora.
 */
export const Locale = z.enum(["ru", "tg", "en"]);
export type Locale = z.infer<typeof Locale>;

export const DEFAULT_LOCALE: Locale = "ru";

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

/**
 * The message this one answers, by `seq`.
 *
 * `seq` rather than `id`: it is per-chat, gapless, and already the key the
 * client indexes history by, so resolving a quote is a lookup rather than a
 * search. It is also four bytes instead of a uuid, which matters on a bus that
 * carries every message in the product.
 *
 * A quote whose target has been deleted, or which arrived before the client
 * synced that far, renders as "message unavailable" rather than failing — the
 * reply is still a real message and losing it because its parent is missing
 * would be worse than showing it without context.
 */
const ReplyTo = z.number().int().positive().optional();

export const TextPayload = z.object({
  type: z.literal("text"),
  text: z.string().min(1).max(4096),
  reply_to_seq: ReplyTo,
});

/**
 * What kind of thing an attachment is, from the reader's point of view rather
 * than the encoder's. A .webm is a video whether or not the recipient's phone
 * can decode it, and the renderer needs to know which shape to draw before it
 * has fetched a byte.
 *
 * Derived from the mime type on the server (see mediaKindFor) so that a client
 * cannot claim an executable is an image.
 */
export const MediaKind = z.enum(["image", "video", "file"]);
export type MediaKind = z.infer<typeof MediaKind>;

export const MediaPayload = z.object({
  type: z.literal("media"),
  kind: MediaKind,
  key: z.string().min(1), // object-storage key, not a signed URL — URLs expire, keys don't
  mime: z.string().min(1),
  size: z.number().int().nonnegative(),
  width: z.number().int().positive().optional(),
  height: z.number().int().positive().optional(),
  /** Videos only. Rendered before playback so the row does not resize on load. */
  duration_ms: z.number().int().positive().optional(),
  /**
   * Poster frame for a video, or a downscaled preview for a large image.
   *
   * This is the field that decides whether the app is usable on Tajik mobile
   * data: without it, opening a chat downloads every full-size photo in it.
   */
  thumb_key: z.string().min(1).optional(),
  /** Original filename. Meaningless for photos, essential for documents. */
  name: z.string().min(1).max(255).optional(),
  caption: z.string().max(1024).optional(),
  reply_to_seq: ReplyTo,
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

export const MemberRole = z.enum(["owner", "admin", "member"]);
export type MemberRole = z.infer<typeof MemberRole>;

export const ChatSummary = z.object({
  id: Uuid,
  kind: ChatKind,
  title: z.string().nullable(),
  avatar_key: z.string().nullable(),
  last_seq: z.number().int().nonnegative(),
  read_up_to_seq: z.number().int().nonnegative(),
  /**
   * For a direct chat and a small group this is everyone. For a channel it is
   * capped — a broadcast with 40,000 subscribers must not put 40,000 rows in a
   * chat list response. Use member_count for the number.
   */
  members: z.array(PublicUser),
  member_count: z.number().int().nonnegative(),
  /** The viewer's own role, so the client knows what to offer without asking. */
  role: MemberRole,
  /**
   * Whether the viewer may post. Always true in a direct chat or a group; in a
   * channel only for owners and admins.
   *
   * The server sends this so the composer can be hidden rather than shown and
   * then rejected — but it is a hint for the UI, never the enforcement. The
   * gateway and the HTTP path both re-check on every send.
   */
  can_post: z.boolean(),
  /** Public handle for a channel, e.g. @dushanbe_news. Null for private chats. */
  username: z.string().nullable(),
  description: z.string().nullable(),
  last_message: Message.nullable(),
});
export type ChatSummary = z.infer<typeof ChatSummary>;
