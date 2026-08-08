import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { chatMembers, chats, messages, users } from "@sakina/db";
import type { ChatSummary, Message, MessagePayload, PublicUser } from "@sakina/protocol";
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
): Promise<string> {
  const unique = [...new Set([creatorId, ...memberIds])];

  return db.transaction(async (tx) => {
    const created = await tx
      .insert(chats)
      .values({ kind: "group", title, createdBy: creatorId })
      .returning({ id: chats.id });

    const chatId = created[0]?.id;
    if (!chatId) throw new DomainError("conflict", "chat insert returned no row");

    await tx.insert(chatMembers).values(
      unique.map((userId) => ({
        chatId,
        userId,
        role: userId === creatorId ? ("owner" as const) : ("member" as const),
      })),
    );

    return chatId;
  });
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
    .select({ chatId: chatMembers.chatId, readUpToSeq: chatMembers.readUpToSeq })
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
  for (const row of memberRows) {
    const list = membersByChat.get(row.chatId) ?? [];
    list.push(toPublicUser(row.user));
    membersByChat.set(row.chatId, list);
  }

  const readByChat = new Map(memberships.map((m) => [m.chatId, Number(m.readUpToSeq)]));

  return chatRows.map((chat) => ({
    id: chat.id,
    kind: chat.kind,
    title: chat.title,
    avatar_key: chat.avatarKey,
    last_seq: Number(chat.lastSeq),
    read_up_to_seq: readByChat.get(chat.id) ?? 0,
    members: membersByChat.get(chat.id) ?? [],
    last_message: lastMessages.get(chat.id) ?? null,
  }));
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
