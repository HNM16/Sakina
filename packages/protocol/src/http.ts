import { z } from "zod";
import {
  ChatKind,
  ChatSummary,
  DEFAULT_LOCALE,
  Locale,
  Message,
  PublicUser,
  Uuid,
} from "./message.js";

/**
 * The HTTP contract. Deliberately small — HTTP handles only what a socket is
 * bad at: auth bootstrap, media transfer, and deep history backfill.
 */

/**
 * E.164. Tajikistan is +992 followed by 9 digits (e.g. +992901234567), but the
 * schema stays general so migrant users with Russian, Uzbek or Kazakh numbers
 * can register — a large share of the target audience works abroad.
 */
export const PhoneNumber = z
  .string()
  .regex(/^\+[1-9]\d{7,14}$/, "phone must be E.164, e.g. +992901234567");

export const Platform = z.enum(["android", "ios", "web"]);
export type Platform = z.infer<typeof Platform>;

export const EmailAddress = z.string().email().max(254);

/**
 * Sign-in identity. Email is what works today — the team is not in Tajikistan
 * and cannot receive +992 SMS. Phone stays in the union because it is what the
 * product needs at launch, and because an account may hold both.
 */
export const IdentityInput = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("email"), value: EmailAddress }),
  z.object({ kind: z.literal("phone"), value: PhoneNumber }),
]);
export type IdentityInput = z.infer<typeof IdentityInput>;

export const OtpRequestBody = z.object({
  identity: IdentityInput,
  /** Sent so the code email arrives in the right language. */
  locale: Locale.default(DEFAULT_LOCALE),
});
export const OtpRequestResponse = z.object({
  expires_in: z.number().int().positive(),
  /** Present only when the API runs with a stub SMS provider. Never set in production. */
  dev_code: z.string().optional(),
});

/**
 * Something that survives an app reinstall, so a ban is not undone by deleting
 * and re-downloading the app.
 *
 * Optional on purpose: the web client has nothing to offer, an old Android may
 * fail to read SSAID, and a missing attestation must degrade to "less trusted",
 * never to "cannot sign in". See docs/BANS.md for what each source is worth.
 */
export const DeviceAttestation = z.object({
  source: z.enum(["android_id", "devicecheck", "ios_vendor_id", "web_none"]),
  /** Raw platform identifier. The server hashes it; it is never stored plainly. */
  value: z.string().min(1).max(512),
  /** Play Integrity or App Attest verdict, when the client obtained one. */
  integrity_token: z.string().max(8192).optional(),
});
export type DeviceAttestation = z.infer<typeof DeviceAttestation>;

export const DeviceInfo = z.object({
  /** Stable per install. The client generates it once and persists it. */
  device_id: Uuid,
  platform: Platform,
  name: z.string().max(128).default("unknown"),
  push_token: z.string().max(512).optional(),
  attestation: DeviceAttestation.optional(),
});

export const OtpVerifyBody = z.object({
  identity: IdentityInput,
  code: z.string().regex(/^\d{6}$/),
  device: DeviceInfo,
  /** Required only when the server runs invite-only. */
  invite_code: z.string().min(4).max(32).optional(),
});

export const AuthTokens = z.object({
  access_token: z.string(),
  refresh_token: z.string(),
  /** Seconds until access_token expires. Refresh happens ahead of this. */
  expires_in: z.number().int().positive(),
});

export const OtpVerifyResponse = z.object({
  user: PublicUser,
  tokens: AuthTokens,
  /** True when this call created the account rather than signing one back in. */
  is_new_user: z.boolean(),
});

export const RefreshBody = z.object({ refresh_token: z.string().min(1) });

export const DeviceSummary = z.object({
  id: Uuid,
  platform: Platform,
  name: z.string(),
  last_seen_at: z.number().int().nullable(),
  created_at: z.number().int(),
});

export const IdentitySummary = z.object({
  kind: z.enum(["email", "phone"]),
  value: z.string(),
  verified: z.boolean(),
});

export const MeResponse = z.object({
  user: PublicUser,
  devices: z.array(DeviceSummary),
  identities: z.array(IdentitySummary),
});

/**
 * A channel handle, e.g. `dushanbe_news`. Stored and compared lowercase.
 *
 * Latin-only on purpose, and this one is worth defending: a handle is something
 * people type from a poster, read out on the radio, and send in an SMS. Cyrillic
 * handles would look right and be unreachable from half the keyboards in the
 * country — and a handle that mixes scripts is a homograph attack waiting to
 * impersonate a news channel.
 */
export const ChatUsername = z
  .string()
  .min(5)
  .max(32)
  .regex(/^[a-z][a-z0-9_]{4,31}$/, "5-32 characters: a-z, 0-9 and _, starting with a letter");

export const CreateChatBody = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("direct"), peer_id: Uuid }),
  z.object({
    kind: z.literal("group"),
    title: z.string().min(1).max(128),
    member_ids: z.array(Uuid).min(1).max(200),
    description: z.string().max(512).optional(),
  }),
  z.object({
    kind: z.literal("channel"),
    title: z.string().min(1).max(128),
    /** Optional: a channel can stay private and be joined by invite only. */
    username: ChatUsername.optional(),
    description: z.string().max(512).optional(),
    /** Channels usually start empty; the creator is the only member. */
    member_ids: z.array(Uuid).max(200).default([]),
  }),
]);

/** Adding people to a group, or seeding a channel with its first members. */
export const AddMembersBody = z.object({
  user_ids: z.array(Uuid).min(1).max(200),
});

export const UpdateChatBody = z.object({
  title: z.string().min(1).max(128).optional(),
  description: z.string().max(512).nullable().optional(),
  username: ChatUsername.nullable().optional(),
});

export const SetRoleBody = z.object({
  user_id: Uuid,
  /** Cannot be "owner": ownership transfer is a separate, deliberate action. */
  role: z.enum(["admin", "member"]),
});

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

/**
 * Step one of an upload: ask the server where to put the bytes.
 *
 * The bytes never pass through the API. The client uploads straight to object
 * storage with a short-lived presigned URL, which keeps a 40MB video off the
 * Node event loop and means the API can stay small while media is the biggest
 * thing the product moves.
 */
export const UploadRequestBody = z.object({
  /** Where it is going. Checked for membership and post rights before signing. */
  chat_id: Uuid,
  /** Original filename, used for the extension and shown for documents. */
  name: z.string().min(1).max(255),
  mime: z.string().min(1).max(160),
  size: z.number().int().positive(),
  /** True when this is the poster frame for a video or a preview for a photo. */
  thumbnail: z.boolean().default(false),
});

export const UploadTicket = z.object({
  /** The permanent identifier. This is what goes in the message payload. */
  key: z.string().min(1),
  /** Short-lived. Upload here with the given method and headers, then send. */
  url: z.string(),
  method: z.enum(["PUT", "POST"]),
  headers: z.record(z.string()),
  expires_in: z.number().int().positive(),
  max_size: z.number().int().positive(),
});

export const MediaUrlResponse = z.object({
  key: z.string(),
  url: z.string(),
  expires_in: z.number().int().positive(),
});

export const MediaLimits = z.object({
  image: z.number().int().positive(),
  video: z.number().int().positive(),
  file: z.number().int().positive(),
});

export const ChatListResponse = z.object({ chats: z.array(ChatSummary) });

export const HistoryQuery = z.object({
  after_seq: z.coerce.number().int().nonnegative().optional(),
  before_seq: z.coerce.number().int().positive().optional(),
  limit: z.coerce.number().int().positive().max(200).default(50),
});

export const HistoryResponse = z.object({
  chat_id: Uuid,
  messages: z.array(Message),
  has_more: z.boolean(),
});

export const ApiError = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});

/**
 * Registering the OS-issued push token. Separate from sign-in because the
 * token arrives later — after the user grants notification permission, which
 * on both platforms is a prompt they may dismiss and revisit.
 */
export const PushTokenBody = z.object({
  device_id: Uuid,
  token: z.string().min(1).max(4096),
  provider: z.enum(["fcm", "apns"]),
});
export type PushTokenBody = z.infer<typeof PushTokenBody>;

export const InviteSummary = z.object({
  code: z.string(),
  remaining_uses: z.number().int().nonnegative(),
  note: z.string().nullable(),
  created_at: z.number().int(),
});

export const InviteListResponse = z.object({ invites: z.array(InviteSummary) });

export type OtpRequestBody = z.infer<typeof OtpRequestBody>;
export type OtpVerifyBody = z.infer<typeof OtpVerifyBody>;
export type OtpVerifyResponse = z.infer<typeof OtpVerifyResponse>;
export type AuthTokens = z.infer<typeof AuthTokens>;
export type MeResponse = z.infer<typeof MeResponse>;
export type CreateChatBody = z.infer<typeof CreateChatBody>;
export type AddMembersBody = z.infer<typeof AddMembersBody>;
export type UpdateChatBody = z.infer<typeof UpdateChatBody>;
export type SetRoleBody = z.infer<typeof SetRoleBody>;
export type UploadRequestBody = z.infer<typeof UploadRequestBody>;
export type UploadTicket = z.infer<typeof UploadTicket>;
export type HistoryResponse = z.infer<typeof HistoryResponse>;
export type { ChatKind, ChatSummary };
