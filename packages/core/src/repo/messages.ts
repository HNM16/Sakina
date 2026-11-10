import { and, asc, desc, eq, gt, isNull, lt, sql } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { chatMembers, chats, messages } from "@sakina/db";
import type { Message, MessagePayload } from "@sakina/protocol";
import { DomainError } from "../errors.js";

type MessageRow = typeof messages.$inferSelect;

export function toWireMessage(row: MessageRow): Message {
  return {
    id: row.id,
    client_id: row.clientId,
    chat_id: row.chatId,
    sender_id: row.senderId,
    seq: Number(row.seq),
    payload: row.payload as MessagePayload,
    created_at: row.createdAt.getTime(),
    edited_at: row.editedAt?.getTime() ?? null,
    deleted_at: row.deletedAt?.getTime() ?? null,
  };
}

const UNIQUE_VIOLATION = "23505";

function isUniqueViolation(err: unknown): boolean {
  return typeof err === "object" && err !== null && (err as { code?: string }).code === UNIQUE_VIOLATION;
}

export interface InsertMessageInput {
  chatId: string;
  senderId: string;
  clientId: string;
  payload: MessagePayload;
}

export interface InsertMessageResult {
  message: Message;
  /** True when this exact client_id had already been stored — a retry, not a new message. */
  deduped: boolean;
}

/**
 * The write path.
 *
 * Three things happen in one transaction, and the order matters:
 *   1. membership is checked (a non-member must not be able to allocate a seq),
 *   2. the chat row is locked and its seq counter incremented — this row lock is
 *      what serialises concurrent senders and keeps seq gapless,
 *   3. the message is inserted with that seq.
 *
 * Idempotency comes from the unique index on (chat_id, client_id). A client
 * retrying over a flaky link sends the same client_id; we either find the
 * earlier row up front, or lose the race and catch the unique violation. Both
 * paths return the original message, so the retry is invisible to the user.
 */
export async function insertMessage(
  db: Database,
  input: InsertMessageInput,
): Promise<InsertMessageResult> {
  const existing = await findByClientId(db, input.chatId, input.clientId);
  if (existing) return { message: existing, deduped: true };

  try {
    return await db.transaction(async (tx) => {
      // Membership is folded into the UPDATE rather than checked by a separate
      // SELECT. This is a hot path — every message pays for it — and the round
      // trip saved is one of the handful the send path makes. The row lock and
      // the authorisation now happen in a single statement.
      const bumped = await tx
        .update(chats)
        .set({ lastSeq: sql`${chats.lastSeq} + 1` })
        .where(
          and(
            eq(chats.id, input.chatId),
            // Membership AND the right to post, in one predicate. In a channel
            // only owners and admins may write; that restriction is what makes
            // a channel a channel, so it is enforced in the same atomic
            // statement that allocates the seq rather than in a route that
            // something else could bypass.
            sql`EXISTS (SELECT 1 FROM ${chatMembers}
                        WHERE ${chatMembers.chatId} = ${input.chatId}
                          AND ${chatMembers.userId} = ${input.senderId}
                          AND ${chatMembers.leftAt} IS NULL
                          AND (${chats.kind} <> 'channel'
                               OR ${chatMembers.role} IN ('owner', 'admin')))`,
          ),
        )
        .returning({ lastSeq: chats.lastSeq });

      const seq = bumped[0]?.lastSeq;
      if (seq === undefined) {
        // No row means one of three things: no such chat, not a member, or a
        // member of a channel without the right to post. Telling them apart
        // costs a query, which is fine here because this is the error path and
        // it runs rarely — and "only admins can post in this channel" is a
        // message someone can act on, where "forbidden" is not.
        const chatRow = await tx
          .select({ id: chats.id, kind: chats.kind })
          .from(chats)
          .where(eq(chats.id, input.chatId))
          .limit(1);

        if (!chatRow[0]) throw new DomainError("not_found", "chat not found");

        const membership = await tx
          .select({ role: chatMembers.role })
          .from(chatMembers)
          .where(
            and(
              eq(chatMembers.chatId, input.chatId),
              eq(chatMembers.userId, input.senderId),
              isNull(chatMembers.leftAt),
            ),
          )
          .limit(1);

        throw membership[0]
          ? new DomainError("forbidden", "only admins can post in this channel")
          : new DomainError("forbidden", "sender is not a member of this chat");
      }

      const inserted = await tx
        .insert(messages)
        .values({
          chatId: input.chatId,
          seq: Number(seq),
          clientId: input.clientId,
          senderId: input.senderId,
          type: input.payload.type,
          payload: input.payload,
        })
        .returning();

      const row = inserted[0];
      if (!row) throw new DomainError("conflict", "message insert returned no row");

      return { message: toWireMessage(row), deduped: false };
    });
  } catch (err) {
    // Lost the idempotency race: a concurrent retry inserted first. Its row is
    // the canonical one — the seq we burned is simply skipped.
    if (isUniqueViolation(err)) {
      const raced = await findByClientId(db, input.chatId, input.clientId);
      if (raced) return { message: raced, deduped: true };
    }
    throw err;
  }
}

export async function findByClientId(
  db: Database,
  chatId: string,
  clientId: string,
): Promise<Message | null> {
  const rows = await db
    .select()
    .from(messages)
    .where(and(eq(messages.chatId, chatId), eq(messages.clientId, clientId)))
    .limit(1);
  return rows[0] ? toWireMessage(rows[0]) : null;
}

export interface HistoryQuery {
  chatId: string;
  afterSeq?: number;
  beforeSeq?: number;
  limit: number;
}

/**
 * `after_seq` is the sync path (catch up forward, ascending). `before_seq` is
 * the scroll-back path (older history, descending then reversed). Both are
 * range scans on the (chat_id, seq) primary key.
 */
export async function getHistory(
  db: Database,
  query: HistoryQuery,
): Promise<{ messages: Message[]; hasMore: boolean }> {
  const limit = Math.min(query.limit, 200);

  if (query.afterSeq !== undefined) {
    const rows = await db
      .select()
      .from(messages)
      .where(and(eq(messages.chatId, query.chatId), gt(messages.seq, query.afterSeq)))
      .orderBy(asc(messages.seq))
      .limit(limit + 1);
    return { messages: rows.slice(0, limit).map(toWireMessage), hasMore: rows.length > limit };
  }

  const before = query.beforeSeq ?? Number.MAX_SAFE_INTEGER;
  const rows = await db
    .select()
    .from(messages)
    .where(and(eq(messages.chatId, query.chatId), lt(messages.seq, before)))
    .orderBy(desc(messages.seq))
    .limit(limit + 1);

  const page = rows.slice(0, limit).map(toWireMessage).reverse();
  return { messages: page, hasMore: rows.length > limit };
}
