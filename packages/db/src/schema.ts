import {
  bigint,
  bigserial,
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

export const userKind = pgEnum("user_kind", ["human", "bot", "service"]);
export const platform = pgEnum("platform", ["android", "ios", "web"]);
export const pushProvider = pgEnum("push_provider", ["fcm", "apns", "none"]);

/**
 * How an account can be proved. A user has many identities.
 *
 * Email is the identity that works today, because the team is not in
 * Tajikistan and cannot receive +992 SMS. Phone is what the product needs at
 * launch — for contact discovery, for trust, and eventually for the payments
 * layer, where an email-only account is not something a regulator will accept.
 *
 * Modelling both from the start means adding phone later is `INSERT INTO
 * identities`, not a migration of the user table and every auth path that
 * touches it.
 */
export const identityKind = pgEnum("identity_kind", ["email", "phone"]);

export const identities = pgTable(
  "identities",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    kind: identityKind("kind").notNull(),
    /** Exactly as the user typed it. Shown back to them; never used for lookup. */
    value: text("value").notNull(),
    /**
     * The normalised form, and the only thing uniqueness is judged on.
     * `J.Doe+signup@googlemail.com` and `jdoe@gmail.com` both land here as
     * `jdoe@gmail.com`, so the second signup collides with the first instead of
     * quietly creating a second account. See packages/core/src/identity.ts.
     */
    canonical: text("canonical").notNull(),
    verifiedAt: timestamp("verified_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex("identities_canonical_key").on(t.kind, t.canonical),
    index("identities_user_idx").on(t.userId),
  ],
);

export const users = pgTable(
  "users",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    username: text("username"),
    displayName: text("display_name").notNull(),
    avatarKey: text("avatar_key"),
    /**
     * `bot` and `service` are unused in M0. Reserved so that service accounts
     * and mini-apps can be modelled as ordinary chat participants later rather
     * than as a bolted-on parallel system.
     */
    kind: userKind("kind").notNull().default("human"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [uniqueIndex("users_username_key").on(t.username)],
);

/**
 * Sessions belong to devices, not users. Multi-device is a day-one constraint:
 * retrofitting it means redoing auth, push routing and history sync at once.
 */
export const devices = pgTable(
  "devices",
  {
    id: uuid("id").primaryKey(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    platform: platform("platform").notNull(),
    name: text("name").notNull().default("unknown"),
    /** FCM registration token or APNs device token. Null until the OS grants one. */
    pushToken: text("push_token"),
    pushProvider: pushProvider("push_provider").notNull().default("none"),
    /**
     * Consecutive hard failures. Push tokens rot constantly — reinstalls,
     * restores from backup, OS updates — and a provider answering "unregistered"
     * is authoritative. Counting lets a token be retired instead of retried
     * forever against a device that no longer exists.
     */
    pushFailures: integer("push_failures").notNull().default(0),
    pushDisabledAt: timestamp("push_disabled_at", { withTimezone: true }),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
  },
  (t) => [index("devices_user_idx").on(t.userId)],
);

export const sessions = pgTable(
  "sessions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    deviceId: uuid("device_id")
      .notNull()
      .references(() => devices.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    /** Only the hash is stored. A database leak must not yield usable tokens. */
    refreshTokenHash: text("refresh_token_hash").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
  },
  (t) => [
    uniqueIndex("sessions_refresh_hash_key").on(t.refreshTokenHash),
    index("sessions_device_idx").on(t.deviceId),
  ],
);

export const otpCodes = pgTable(
  "otp_codes",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    kind: identityKind("kind").notNull(),
    /** Always the canonical form, so `a.b@gmail.com` cannot get its own code. */
    canonical: text("canonical").notNull(),
    codeHash: text("code_hash").notNull(),
    attempts: integer("attempts").notNull().default(0),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    consumedAt: timestamp("consumed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("otp_identity_idx").on(t.kind, t.canonical, t.createdAt)],
);

/**
 * Signup attempts, for the abuse question email brings that phone did not.
 *
 * Canonicalisation stops the lazy duplicate — the same mailbox typed three
 * ways. It cannot stop a determined person with three genuinely different
 * mailboxes, and no amount of string handling will. What actually limits that
 * is cost per account: how many can come from one device, one network, one
 * afternoon.
 */
export const signupAttempts = pgTable(
  "signup_attempts",
  {
    id: bigserial("id", { mode: "number" }).primaryKey(),
    /** Install identifier — stable across accounts created on one handset. */
    deviceId: uuid("device_id"),
    ipHash: text("ip_hash"),
    canonical: text("canonical").notNull(),
    succeeded: boolean("succeeded").notNull().default(false),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index("signup_attempts_device_idx").on(t.deviceId, t.createdAt),
    index("signup_attempts_ip_idx").on(t.ipHash, t.createdAt),
  ],
);

/**
 * A device that has been seen, identified by something that survives an app
 * reinstall.
 *
 * This is what makes a ban stick when someone re-registers with a new address.
 * The identifier differs by platform and both have hard limits, documented in
 * docs/BANS.md:
 *
 *   Android — Settings.Secure.ANDROID_ID (SSAID). Scoped to our signing key,
 *             survives uninstall/reinstall, cleared by a factory reset.
 *   iOS     — a DeviceCheck bit. Apple prohibits fingerprinting, and IDFV
 *             resets once every app from the vendor is removed; DeviceCheck is
 *             the sanctioned mechanism and survives reinstall. Two bits only.
 *
 * Never the raw value: only a peppered hash is stored. Matching does not need
 * the plaintext, and a leaked table of real device identifiers would be a
 * tracking database we have no business holding.
 */
export const deviceFingerprints = pgTable(
  "device_fingerprints",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    platform: platform("platform").notNull(),
    /** HMAC of the platform identifier. The plaintext never lands here. */
    fingerprintHash: text("fingerprint_hash").notNull(),
    /** How the identifier was obtained, so weak sources can be weighted down. */
    source: text("source").notNull(),
    /** True when the platform vouched for the app being genuine and unmodified. */
    attested: boolean("attested").notNull().default(false),
    firstSeenAt: timestamp("first_seen_at", { withTimezone: true }).notNull().defaultNow(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex("device_fingerprints_key").on(t.platform, t.fingerprintHash)],
);

/** Which accounts have been seen on which hardware. The ban-propagation graph. */
export const deviceFingerprintUsers = pgTable(
  "device_fingerprint_users",
  {
    fingerprintId: uuid("fingerprint_id")
      .notNull()
      .references(() => deviceFingerprints.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    firstSeenAt: timestamp("first_seen_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.fingerprintId, t.userId] }),
    index("device_fingerprint_users_user_idx").on(t.userId),
  ],
);

export const banSubject = pgEnum("ban_subject", ["user", "device"]);

/**
 * Bans, against an account or against hardware.
 *
 * Append-only in spirit: lifting a ban sets `liftedAt` rather than deleting the
 * row, because "was this person banned before" is a question moderation will
 * need to answer and a deleted row cannot.
 */
export const bans = pgTable(
  "bans",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    subject: banSubject("subject").notNull(),
    /** users.id or device_fingerprints.id, per `subject`. */
    subjectId: uuid("subject_id").notNull(),
    reason: text("reason").notNull(),
    /** Null for permanent. */
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    createdBy: uuid("created_by").references(() => users.id, { onDelete: "set null" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    liftedAt: timestamp("lifted_at", { withTimezone: true }),
    liftedReason: text("lifted_reason"),
  },
  (t) => [index("bans_subject_idx").on(t.subject, t.subjectId, t.liftedAt)],
);

/**
 * Invite codes.
 *
 * The strongest anti-abuse tool available at this stage, and the cheapest: an
 * account has to be vouched for by an existing one. It happens to also be the
 * growth mechanism — a closed beta that people ask to be let into spreads
 * better than an open signup nobody is curious about, and the target here is
 * five to ten thousand users, not five million.
 */
export const inviteCodes = pgTable(
  "invite_codes",
  {
    code: text("code").primaryKey(),
    createdBy: uuid("created_by").references(() => users.id, { onDelete: "set null" }),
    /** How many accounts this code may still create. */
    remainingUses: integer("remaining_uses").notNull().default(1),
    note: text("note"),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("invite_codes_creator_idx").on(t.createdBy)],
);

export const inviteRedemptions = pgTable(
  "invite_redemptions",
  {
    id: bigserial("id", { mode: "number" }).primaryKey(),
    code: text("code")
      .notNull()
      .references(() => inviteCodes.code, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex("invite_redemptions_user_key").on(t.userId),
    index("invite_redemptions_code_idx").on(t.code),
  ],
);

// ---------------------------------------------------------------------------
// Chats and messages
// ---------------------------------------------------------------------------

export const chatKind = pgEnum("chat_kind", ["direct", "group", "channel"]);
export const memberRole = pgEnum("member_role", ["owner", "admin", "member"]);
export const messageType = pgEnum("message_type", [
  "text",
  "media",
  "voice",
  "system",
  "payment",
  "service_card",
]);

export const chats = pgTable("chats", {
  id: uuid("id").primaryKey().defaultRandom(),
  kind: chatKind("kind").notNull(),
  title: text("title"),
  avatarKey: text("avatar_key"),
  description: text("description"),
  /**
   * Public handle for a channel, e.g. `dushanbe_news`. Lowercase, Latin only,
   * unique across chats — and it will eventually have to be unique across
   * users too, since @name has to resolve to one thing. Null for everything
   * that is not a public channel.
   */
  username: text("username"),
  /**
   * The per-chat sequence allocator. Sequence numbers are handed out with
   *   UPDATE chats SET last_seq = last_seq + 1 WHERE id = $1 RETURNING last_seq
   * inside the same transaction as the message insert. The row lock serialises
   * concurrent senders, which is what makes seq gapless and monotonic.
   */
  lastSeq: bigint("last_seq", { mode: "number" }).notNull().default(0),
  createdBy: uuid("created_by").references(() => users.id),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  uniqueIndex("chats_username_key").on(t.username),
]);

export const chatMembers = pgTable(
  "chat_members",
  {
    chatId: uuid("chat_id")
      .notNull()
      .references(() => chats.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    role: memberRole("role").notNull().default("member"),
    /** Read state is a cursor, not per-message flags — O(1) per member. */
    readUpToSeq: bigint("read_up_to_seq", { mode: "number" }).notNull().default(0),
    mutedUntil: timestamp("muted_until", { withTimezone: true }),
    joinedAt: timestamp("joined_at", { withTimezone: true }).notNull().defaultNow(),
    leftAt: timestamp("left_at", { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.chatId, t.userId] }),
    index("chat_members_user_idx").on(t.userId),
  ],
);

export const messages = pgTable(
  "messages",
  {
    chatId: uuid("chat_id")
      .notNull()
      .references(() => chats.id, { onDelete: "cascade" }),
    seq: bigint("seq", { mode: "number" }).notNull(),
    id: uuid("id").notNull().defaultRandom(),
    /** Device-generated. The unique index below is what makes retries idempotent. */
    clientId: uuid("client_id").notNull(),
    senderId: uuid("sender_id")
      .notNull()
      .references(() => users.id),
    type: messageType("type").notNull(),
    payload: jsonb("payload").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    editedAt: timestamp("edited_at", { withTimezone: true }),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    // (chat_id, seq) is both the primary key and the sync-scan order. Every
    // history read is a range scan on this index.
    primaryKey({ columns: [t.chatId, t.seq] }),
    uniqueIndex("messages_chat_client_key").on(t.chatId, t.clientId),
    uniqueIndex("messages_id_key").on(t.id),
  ],
);

// ---------------------------------------------------------------------------
// Ledger — shipped empty in M0, on purpose.
//
// Double-entry, append-only: no UPDATE, no DELETE, and every transaction's
// entries must sum to zero (enforced by a deferred constraint trigger, see
// drizzle/0001_ledger_guards.sql). Amounts are integer minor units (diram,
// 1/100 TJS) — never floating point.
//
// Sakina will not hold funds until it is licensed by the NBT; until then a
// partner bank is the ledger of record and these tables mirror it. The schema
// exists now anyway because reshaping a money model after it holds real
// balances is the single most expensive migration a fintech can face.
// ---------------------------------------------------------------------------

export const accountOwnerType = pgEnum("account_owner_type", ["user", "merchant", "system"]);
export const accountKind = pgEnum("account_kind", ["asset", "liability", "revenue", "expense"]);
export const entryDirection = pgEnum("entry_direction", ["debit", "credit"]);
export const txStatus = pgEnum("tx_status", ["pending", "completed", "failed", "reversed"]);

export const ledgerAccounts = pgTable(
  "ledger_accounts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerType: accountOwnerType("owner_type").notNull(),
    ownerId: uuid("owner_id"),
    kind: accountKind("kind").notNull(),
    currency: text("currency").notNull().default("TJS"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex("ledger_accounts_owner_key").on(t.ownerType, t.ownerId, t.currency, t.kind)],
);

export const ledgerTransactions = pgTable(
  "ledger_transactions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    /** Every money-moving call carries one. Replays return the original result. */
    idempotencyKey: text("idempotency_key").notNull(),
    kind: text("kind").notNull(), // p2p_transfer | bill_payment | topup | payout | fee ...
    status: txStatus("status").notNull().default("pending"),
    /** Provider-side identifier: Korti Milli / Alif / DC / operator wallet. */
    externalRef: text("external_ref"),
    provider: text("provider"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex("ledger_tx_idempotency_key").on(t.idempotencyKey)],
);

export const ledgerEntries = pgTable(
  "ledger_entries",
  {
    id: bigserial("id", { mode: "number" }).primaryKey(),
    transactionId: uuid("transaction_id")
      .notNull()
      .references(() => ledgerTransactions.id),
    accountId: uuid("account_id")
      .notNull()
      .references(() => ledgerAccounts.id),
    direction: entryDirection("direction").notNull(),
    /** Minor units (diram). Always positive; `direction` carries the sign. */
    amountMinor: bigint("amount_minor", { mode: "number" }).notNull(),
    currency: text("currency").notNull().default("TJS"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index("ledger_entries_tx_idx").on(t.transactionId),
    index("ledger_entries_account_idx").on(t.accountId, t.createdAt),
  ],
);

export const schema = {
  users,
  identities,
  deviceFingerprints,
  deviceFingerprintUsers,
  bans,
  signupAttempts,
  inviteCodes,
  inviteRedemptions,
  devices,
  sessions,
  otpCodes,
  chats,
  chatMembers,
  messages,
  ledgerAccounts,
  ledgerTransactions,
  ledgerEntries,
};
