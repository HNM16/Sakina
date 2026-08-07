import {
  bigint,
  bigserial,
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

export const users = pgTable(
  "users",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    phone: text("phone").notNull(),
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
  (t) => [
    uniqueIndex("users_phone_key").on(t.phone),
    uniqueIndex("users_username_key").on(t.username),
  ],
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
    pushToken: text("push_token"),
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
    phone: text("phone").notNull(),
    codeHash: text("code_hash").notNull(),
    attempts: integer("attempts").notNull().default(0),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    consumedAt: timestamp("consumed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("otp_phone_idx").on(t.phone, t.createdAt)],
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
  /**
   * The per-chat sequence allocator. Sequence numbers are handed out with
   *   UPDATE chats SET last_seq = last_seq + 1 WHERE id = $1 RETURNING last_seq
   * inside the same transaction as the message insert. The row lock serialises
   * concurrent senders, which is what makes seq gapless and monotonic.
   */
  lastSeq: bigint("last_seq", { mode: "number" }).notNull().default(0),
  createdBy: uuid("created_by").references(() => users.id),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

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
