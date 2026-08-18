import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { chatMembers, chats, messages, users } from "@sakina/db";
import type {
  ChatSummary,
  MemberRole,
  Message,
  MessagePayload,
  PublicUser,
} from "@sakina/protocol";
import { DomainError } from "../errors.js";
import { toWireMessage } from "./messages.js";

export async function isMember(db: Database, chatId: string, userId: string): Promise<boolean> {
  const rows = await db
    .select({ userId: chatMembers.userId })
    .from(chatMembers)
    .where(
      and(
        eq(chatMembers.chatId, chatId),
        eq(chatMembers.userId, userId),
        isNull(chatMembers.leftAt),
      ),
    )
    .limit(1);
  return rows.length > 0;
}

/**
 * How many members a chat list response will carry per chat.
 *
 * A group tops out at 200 and fits. A channel does not: a broadcast with
 * 40,000 subscribers would put 40,000 user rows into every chat-list response
 * for every subscriber. The list carries a sample and the true count; the full
 * member list is its own paginated endpoint when someone actually asks.
 */
export const MEMBER_PREVIEW_LIMIT = 64;

/**
 * Who may post.
 *
 * In a direct chat and a group, everyone who is still a member. In a channel,
 * only owners and admins — that restriction IS the difference between a channel
 * and a group, so it lives here rather than in a route, and both the HTTP path
 * and the gateway call it.
 */
export function canPost(kind: "direct" | "group" | "channel", role: MemberRole): boolean {
  if (kind !== "channel") return true;
  return role === "owner" || role === "admin";
}

/**
 * The membership row, or null. One query, used by every permission check.
 *
 * Returns the role too, because every caller that needs to know "is this person
 * in this chat" also needs to know "and may they do this", and asking twice is
 * two round trips for one decision.
 */
export async function getMembership(
  db: Database,
  chatId: string,
  userId: string,
): Promise<{ role: MemberRole; kind: "direct" | "group" | "channel" } | null> {
  const rows = await db
    .select({ role: chatMembers.role, kind: chats.kind })
    .from(chatMembers)
    .innerJoin(chats, eq(chats.id, chatMembers.chatId))
    .where(
      and(
        eq(chatMembers.chatId, chatId),
        eq(chatMembers.userId, userId),
        isNull(chatMembers.leftAt),
      ),
    )
    .limit(1);
  const row = rows[0];
  return row ? { role: row.role, kind: row.kind } : null;
}

/** Throws unless the user is a member AND allowed to post. */
export async function assertCanPost(
  db: Database,
  chatId: string,
  userId: string,
): Promise<void> {
  const membership = await getMembership(db, chatId, userId);
  if (!membership) {
    throw new DomainError("forbidden", "sender is not a member of this chat");
  }
  if (!canPost(membership.kind, membership.role)) {
    throw new DomainError("forbidden", "only admins can post in this channel");
  }
}

/** Fan-out list for the gateway: who should receive a message posted to this chat. */
export async function getMemberIds(db: Database, chatId: string): Promise<string[]> {
  const rows = await db
    .select({ userId: chatMembers.userId })
    .from(chatMembers)
    .where(and(eq(chatMembers.chatId, chatId), isNull(chatMembers.leftAt)));
  return rows.map((r) => r.userId);
}

export async function createDirectChat(
  db: Database,
  userId: string,
  peerId: string,
): Promise<string> {
  if (userId === peerId) throw new DomainError("bad_request", "cannot open a direct chat with yourself");

  const peer = await db.select({ id: users.id }).from(users).where(eq(users.id, peerId)).limit(1);
  if (!peer[0]) throw new DomainError("not_found", "peer not found");

  // Direct chats are unique per pair — reopening one must return the existing
  // thread, not fork the history.
  const existing = await findDirectChat(db, userId, peerId);
  if (existing) return existing;

  return db.transaction(async (tx) => {
    const created = await tx
      .insert(chats)
      .values({ kind: "direct", createdBy: userId })
      .returning({ id: chats.id });

    const chatId = created[0]?.id;
    if (!chatId) throw new DomainError("conflict", "chat insert returned no row");

    await tx.insert(chatMembers).values([
      { chatId, userId, role: "member" },
      { chatId, userId: peerId, role: "member" },
    ]);

    return chatId;
  });
}

async function findDirectChat(
  db: Database,
  userId: string,
  peerId: string,
): Promise<string | null> {
  const mine = await db
    .select({ chatId: chatMembers.chatId })
    .from(chatMembers)
    .innerJoin(chats, eq(chats.id, chatMembers.chatId))
    .where(and(eq(chatMembers.userId, userId), eq(chats.kind, "direct")));

  if (mine.length === 0) return null;

  const theirs = await db
    .select({ chatId: chatMembers.chatId })
    .from(chatMembers)
    .where(
      and(
        eq(chatMembers.userId, peerId),
        inArray(
          chatMembers.chatId,
          mine.map((m) => m.chatId),
        ),
      ),
    )
    .limit(1);

  return theirs[0]?.chatId ?? null;
}

export async function createGroupChat(
  db: Database,
  creatorId: string,
  title: string,
  memberIds: string[],
  description?: string,
): Promise<string> {
  return createMultiChat(db, {
    kind: "group",
    creatorId,
    title,
    memberIds,
    description,
  });
}

/**
 * A channel: one-to-many, where only owners and admins post.
 *
 * Structurally a chat like any other — same seq allocator, same fan-out, same
 * sync — because the whole point of the design in docs/PROTOCOL.md is that new
 * chat shapes are not new subsystems. What makes it a channel is one predicate,
 * [canPost], and the fact that joining does not require an invitation when it
 * has a public username.
 */
export async function createChannel(
  db: Database,
  creatorId: string,
  input: { title: string; username?: string; description?: string; memberIds?: string[] },
): Promise<string> {
  return createMultiChat(db, {
    kind: "channel",
    creatorId,
    title: input.title,
    memberIds: input.memberIds ?? [],
    description: input.description,
    username: input.username,
  });
}

async function createMultiChat(
  db: Database,
  input: {
    kind: "group" | "channel";
    creatorId: string;
    title: string;
    memberIds: string[];
    description?: string;
    username?: string;
  },
): Promise<string> {
  const unique = [...new Set([input.creatorId, ...input.memberIds])];

  // Every id has to be a real user. Without this an invented uuid becomes a
  // silent foreign-key error halfway through the transaction, and the caller
  // sees "conflict" instead of "that person does not exist".
  const known = await db
    .select({ id: users.id })
    .from(users)
    .where(inArray(users.id, unique));
  if (known.length !== unique.length) {
    const found = new Set(known.map((u) => u.id));
    const missing = unique.filter((id) => !found.has(id));
    throw new DomainError("bad_request", `unknown user: ${missing[0]}`);
  }

  if (input.username) {
    const taken = await db
      .select({ id: chats.id })
      .from(chats)
      .where(eq(chats.username, input.username))
      .limit(1);
    if (taken.length > 0) {
      throw new DomainError("conflict", `@${input.username} is already taken`);
    }
  }

  return db.transaction(async (tx) => {
    const created = await tx
      .insert(chats)
      .values({
        kind: input.kind,
        title: input.title,
        description: input.description ?? null,
        username: input.username ?? null,
        createdBy: input.creatorId,
      })
      .returning({ id: chats.id });

    const chatId = created[0]?.id;
    if (!chatId) throw new DomainError("conflict", "chat insert returned no row");

    await tx.insert(chatMembers).values(
      unique.map((userId) => ({
        chatId,
        userId,
        role: userId === input.creatorId ? ("owner" as const) : ("member" as const),
      })),
    );

    return chatId;
  });
}

/**
 * Add people to a group or channel.
 *
 * Rejoining is an update, not an insert: someone who left and comes back has a
 * row already, and the primary key is (chat_id, user_id). Their read cursor is
 * deliberately left where it was — coming back to a group should not mark two
 * months of messages unread.
 */
export async function addMembers(
  db: Database,
  chatId: string,
  userIds: string[],
): Promise<string[]> {
  const unique = [...new Set(userIds)];
  if (unique.length === 0) return [];

  const known = await db.select({ id: users.id }).from(users).where(inArray(users.id, unique));
  if (known.length !== unique.length) {
    const found = new Set(known.map((u) => u.id));
    throw new DomainError("bad_request", `unknown user: ${unique.find((id) => !found.has(id))}`);
  }

  const added = await db
    .insert(chatMembers)
    .values(unique.map((userId) => ({ chatId, userId, role: "member" as const })))
    .onConflictDoUpdate({
      target: [chatMembers.chatId, chatMembers.userId],
      set: { leftAt: null },
      // Only resurrect rows that are actually gone; re-adding a current member
      // must not quietly reset anything about them.
      setWhere: sql`${chatMembers.leftAt} IS NOT NULL`,
    })
    .returning({ userId: chatMembers.userId });

  invalidateMemberCache(chatId);
  return added.map((r) => r.userId);
}

/**
 * Remove someone, or leave.
 *
 * A tombstone rather than a delete: history stays attributable, the read cursor
 * survives a rejoin, and "X left" remains true afterwards. Deleting the row
 * would orphan every message they sent.
 */
export async function removeMember(
  db: Database,
  chatId: string,
  userId: string,
): Promise<void> {
  await db
    .update(chatMembers)
    .set({ leftAt: new Date() })
    .where(
      and(
        eq(chatMembers.chatId, chatId),
        eq(chatMembers.userId, userId),
        isNull(chatMembers.leftAt),
      ),
    );
  invalidateMemberCache(chatId);
}

export async function setMemberRole(
  db: Database,
  chatId: string,
  userId: string,
  role: "admin" | "member",
): Promise<void> {
  const rows = await db
    .update(chatMembers)
    .set({ role })
    .where(
      and(
        eq(chatMembers.chatId, chatId),
        eq(chatMembers.userId, userId),
        isNull(chatMembers.leftAt),
        // The owner is not demotable by this path. Handing over a channel is a
        // separate, deliberate act, not a side effect of tidying up admins.
        sql`${chatMembers.role} <> 'owner'`,
      ),
    )
    .returning({ userId: chatMembers.userId });

  if (rows.length === 0) {
    throw new DomainError("bad_request", "that person is not a member, or is the owner");
  }
}

export async function updateChat(
  db: Database,
  chatId: string,
  patch: { title?: string; description?: string | null; username?: string | null },
): Promise<void> {
  if (patch.username) {
    const taken = await db
      .select({ id: chats.id })
      .from(chats)
      .where(and(eq(chats.username, patch.username), sql`${chats.id} <> ${chatId}`))
      .limit(1);
    if (taken.length > 0) {
      throw new DomainError("conflict", `@${patch.username} is already taken`);
    }
  }

  const values: Record<string, unknown> = {};
  if (patch.title !== undefined) values.title = patch.title;
  if (patch.description !== undefined) values.description = patch.description;
  if (patch.username !== undefined) values.username = patch.username;
  if (Object.keys(values).length === 0) return;

  await db.update(chats).set(values).where(eq(chats.id, chatId));
}

/** Look a channel up by its public handle, for joining from a link. */
export async function findByUsername(
  db: Database,
  username: string,
): Promise<{ id: string; kind: "direct" | "group" | "channel" } | null> {
  const rows = await db
    .select({ id: chats.id, kind: chats.kind })
    .from(chats)
    .where(eq(chats.username, username.toLowerCase()))
    .limit(1);
  return rows[0] ?? null;
}

export async function setReadCursor(
  db: Database,
  chatId: string,
  userId: string,
  upToSeq: number,
): Promise<void> {
  // GREATEST keeps the cursor monotonic: an out-of-order receipt from a slow
  // device must never walk the read position backwards.
  await db
    .update(chatMembers)
    .set({ readUpToSeq: sql`GREATEST(${chatMembers.readUpToSeq}, ${upToSeq})` })
    .where(and(eq(chatMembers.chatId, chatId), eq(chatMembers.userId, userId)));
}

function toPublicUser(row: typeof users.$inferSelect): PublicUser {
  return {
    id: row.id,
    username: row.username,
    display_name: row.displayName,
    avatar_key: row.avatarKey,
    kind: row.kind,
  };
}

export async function listChatsForUser(db: Database, userId: string): Promise<ChatSummary[]> {
  const memberships = await db
    .select({
      chatId: chatMembers.chatId,
      readUpToSeq: chatMembers.readUpToSeq,
      role: chatMembers.role,
    })
    .from(chatMembers)
    .where(and(eq(chatMembers.userId, userId), isNull(chatMembers.leftAt)));

  if (memberships.length === 0) return [];
  const chatIds = memberships.map((m) => m.chatId);

  const [chatRows, memberRows, lastMessages] = await Promise.all([
    db.select().from(chats).where(inArray(chats.id, chatIds)),
    db
      .select({ chatId: chatMembers.chatId, user: users })
      .from(chatMembers)
      .innerJoin(users, eq(users.id, chatMembers.userId))
      .where(and(inArray(chatMembers.chatId, chatIds), isNull(chatMembers.leftAt))),
    lastMessagePerChat(db, chatIds),
  ]);

  const membersByChat = new Map<string, PublicUser[]>();
  const countByChat = new Map<string, number>();
  for (const row of memberRows) {
    countByChat.set(row.chatId, (countByChat.get(row.chatId) ?? 0) + 1);
    const list = membersByChat.get(row.chatId) ?? [];
    // The count is exact; the list is a preview. A channel with 40,000
    // subscribers must not put 40,000 user rows in every chat-list response.
    if (list.length < MEMBER_PREVIEW_LIMIT) list.push(toPublicUser(row.user));
    membersByChat.set(row.chatId, list);
  }

  const readByChat = new Map(memberships.map((m) => [m.chatId, Number(m.readUpToSeq)]));
  const roleByChat = new Map(memberships.map((m) => [m.chatId, m.role]));

  return chatRows.map((chat) => {
    const role = roleByChat.get(chat.id) ?? "member";
    return {
      id: chat.id,
      kind: chat.kind,
      title: chat.title,
      avatar_key: chat.avatarKey,
      description: chat.description,
      username: chat.username,
      last_seq: Number(chat.lastSeq),
      read_up_to_seq: readByChat.get(chat.id) ?? 0,
      members: membersByChat.get(chat.id) ?? [],
      member_count: countByChat.get(chat.id) ?? 0,
      role,
      can_post: canPost(chat.kind, role),
      last_message: lastMessages.get(chat.id) ?? null,
    };
  });
}

/**
 * One DISTINCT ON query instead of one query per chat. Reads the newest row of
 * each chat straight off the (chat_id, seq) primary key.
 */
async function lastMessagePerChat(
  db: Database,
  chatIds: string[],
): Promise<Map<string, Message>> {
  const rows = (await db.execute(sql`
    SELECT DISTINCT ON (chat_id)
      chat_id, seq, id, client_id, sender_id, type, payload, created_at, edited_at, deleted_at
    FROM ${messages}
    WHERE ${inArray(messages.chatId, chatIds)}
    ORDER BY chat_id, seq DESC
  `)) as unknown as RawMessageRow[];

  return new Map(rows.map((row) => [row.chat_id, fromRawMessage(row)]));
}

/**
 * Raw rows come back from `db.execute` untouched by the drizzle column mappers,
 * so nothing here can be assumed to already be the right JS type: timestamps may
 * arrive as strings, bigints as strings, jsonb as either an object or its text.
 * Everything is coerced explicitly rather than cast and hoped for.
 */
interface RawMessageRow {
  chat_id: string;
  seq: string | number;
  id: string;
  client_id: string;
  sender_id: string;
  payload: MessagePayload | string;
  created_at: Date | string;
  edited_at: Date | string | null;
  deleted_at: Date | string | null;
}

function toDate(value: Date | string): Date {
  return value instanceof Date ? value : new Date(value);
}

function toNullableDate(value: Date | string | null): Date | null {
  return value === null ? null : toDate(value);
}

function fromRawMessage(row: RawMessageRow): Message {
  const payload: MessagePayload =
    typeof row.payload === "string" ? (JSON.parse(row.payload) as MessagePayload) : row.payload;

  return toWireMessage({
    chatId: row.chat_id,
    seq: Number(row.seq),
    id: row.id,
    clientId: row.client_id,
    senderId: row.sender_id,
    type: payload.type,
    payload,
    createdAt: toDate(row.created_at),
    editedAt: toNullableDate(row.edited_at),
    deletedAt: toNullableDate(row.deleted_at),
  });
}

// ---------------------------------------------------------------------------
// Membership cache
// ---------------------------------------------------------------------------

/**
 * Chat membership, cached in process for a few seconds.
 *
 * `getMemberIds` runs on every single message, read receipt and typing frame,
 * and it answers a question that almost never changes — a direct chat's two
 * members are fixed for its whole life. Under load it was a meaningful share of
 * the queries the gateway made.
 *
 * A short TTL rather than explicit invalidation, deliberately: correctness here
 * degrades gracefully. The worst case for a stale entry is that someone added
 * to a group waits a few seconds for their first message, or someone just
 * removed receives one more. Both self-heal, and neither is worth the coupling
 * that precise invalidation across processes would cost.
 */
const MEMBER_CACHE_TTL_MS = 5_000;
const MEMBER_CACHE_MAX = 5_000;

const memberCache = new Map<string, { ids: string[]; expiresAt: number }>();

export function invalidateMemberCache(chatId?: string): void {
  if (chatId) memberCache.delete(chatId);
  else memberCache.clear();
}

/** Cached form of [getMemberIds] for the hot fan-out path. */
export async function getMemberIdsCached(db: Database, chatId: string): Promise<string[]> {
  const now = Date.now();
  const hit = memberCache.get(chatId);
  if (hit && hit.expiresAt > now) return hit.ids;

  const ids = await getMemberIds(db, chatId);

  // Crude bound rather than a real LRU: this is a cache of small string arrays
  // and the eviction policy matters far less than not growing without limit.
  if (memberCache.size >= MEMBER_CACHE_MAX) memberCache.clear();
  memberCache.set(chatId, { ids, expiresAt: now + MEMBER_CACHE_TTL_MS });

  return ids;
}

/**
 * A page of members, oldest first.
 *
 * Separate from the chat summary because a channel's audience does not belong
 * in a chat-list response — see [MEMBER_PREVIEW_LIMIT]. Ordered by joinedAt so
 * paging is stable while people are joining.
 */
export async function listMembers(
  db: Database,
  chatId: string,
  limit: number,
  offset: number,
): Promise<{ members: (PublicUser & { role: MemberRole })[]; total: number }> {
  const [rows, counted] = await Promise.all([
    db
      .select({ user: users, role: chatMembers.role })
      .from(chatMembers)
      .innerJoin(users, eq(users.id, chatMembers.userId))
      .where(and(eq(chatMembers.chatId, chatId), isNull(chatMembers.leftAt)))
      // Role first, then join order, then id.
      //
      // The id is not decoration: everyone added when the chat was created
      // shares a joinedAt, because defaultNow() is the TRANSACTION timestamp
      // rather than the statement's. Without a total order, paging a member
      // list can show the same person twice and skip someone else.
      //
      // Role ascending happens to be owner, admin, member — that is the order
      // the enum is declared in, and it is also the order people expect to read
      // them in, so it is worth the coupling.
      .orderBy(asc(chatMembers.role), asc(chatMembers.joinedAt), asc(chatMembers.userId))
      .limit(limit)
      .offset(offset),
    db
      .select({ count: sql<number>`count(*)::int` })
      .from(chatMembers)
      .where(and(eq(chatMembers.chatId, chatId), isNull(chatMembers.leftAt))),
  ]);

  return {
    members: rows.map((r) => ({ ...toPublicUser(r.user), role: r.role })),
    total: counted[0]?.count ?? 0,
  };
}
