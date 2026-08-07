import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { chatsRepo, DomainError, messagesRepo } from "@sakina/core";
import { CreateChatBody, HistoryQuery } from "@sakina/protocol";
import { requireAuth, type AppContext } from "../app.js";

const ChatIdParams = z.object({ id: z.string().uuid() });

export function registerChatRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.get("/chats", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const chats = await chatsRepo.listChatsForUser(ctx.db, userId);
    return reply.send({ chats });
  });

  app.post("/chats", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const body = CreateChatBody.parse(req.body);

    const chatId =
      body.kind === "direct"
        ? await chatsRepo.createDirectChat(ctx.db, userId, body.peer_id)
        : await chatsRepo.createGroupChat(ctx.db, userId, body.title, body.member_ids);

    const chats = await chatsRepo.listChatsForUser(ctx.db, userId);
    const chat = chats.find((c) => c.id === chatId);
    if (!chat) throw new DomainError("not_found", "chat not found after creation");

    return reply.status(201).send(chat);
  });

  /**
   * Deep backfill. The socket handles the recent tail on reconnect; this is for
   * scroll-back and for clients that fell too far behind to catch up inline.
   */
  app.get("/chats/:id/messages", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { id: chatId } = ChatIdParams.parse(req.params);

    if (!(await chatsRepo.isMember(ctx.db, chatId, userId))) {
      throw new DomainError("forbidden", "not a member of this chat");
    }

    const query = HistoryQuery.parse(req.query);
    const result = await messagesRepo.getHistory(ctx.db, {
      chatId,
      afterSeq: query.after_seq,
      beforeSeq: query.before_seq,
      limit: query.limit,
    });

    return reply.send({
      chat_id: chatId,
      messages: result.messages,
      has_more: result.hasMore,
    });
  });

  app.post("/chats/:id/read", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { id: chatId } = ChatIdParams.parse(req.params);
    const body = z.object({ up_to_seq: z.number().int().nonnegative() }).parse(req.body);

    if (!(await chatsRepo.isMember(ctx.db, chatId, userId))) {
      throw new DomainError("forbidden", "not a member of this chat");
    }

    await chatsRepo.setReadCursor(ctx.db, chatId, userId, body.up_to_seq);
    return reply.status(204).send();
  });
}
