import type { FastifyInstance } from "fastify";
import { z } from "zod";
import {
  chatsRepo,
  DomainError,
  messagesRepo,
  publishFanout,
  type FanoutEnvelope,
} from "@sakina/core";
import {
  AddMembersBody,
  ChatUsername,
  CreateChatBody,
  HistoryQuery,
  SetRoleBody,
  UpdateChatBody,
  type ChatSummary,
  type MemberRole,
} from "@sakina/protocol";
import { requireAuth, type AppContext } from "../app.js";

const ChatIdParams = z.object({ id: z.string().uuid() });

export function registerChatRoutes(app: FastifyInstance, ctx: AppContext): void {
  /**
   * Tell everyone who can see this chat that it changed.
   *
   * Called after every membership and title change. Without it, being added to
   * a group is invisible on a phone that is already connected — the chat list
   * only arrives in the `ready` frame at connect time, and a phone stays
   * connected for hours.
   *
   * Each recipient needs their own summary, because `role`, `can_post` and
   * `read_up_to_seq` differ per viewer. That is one query per member, which is
   * fine for a group of 200 and is why channels are excluded below.
   */
  async function announce(chatId: string, userIds: string[]): Promise<void> {
    // A channel broadcast to 40,000 subscribers is not worth 40,000 queries for
    // a title change. They will pick it up on their next sync, which for a
    // channel is exactly as timely as it needs to be.
    const recipients = userIds.slice(0, chatsRepo.MEMBER_PREVIEW_LIMIT);
    const envelopes: FanoutEnvelope[] = [];

    for (const userId of recipients) {
      const summary = (await chatsRepo.listChatsForUser(ctx.db, userId)).find(
        (c) => c.id === chatId,
      );
      if (summary) envelopes.push({ user_ids: [userId], frame: { t: "chat", d: summary } });
    }

    await Promise.all(envelopes.map((e) => publishFanout(ctx.redis, e)));
  }

  async function announceRemoval(chatId: string, userIds: string[]): Promise<void> {
    await publishFanout(ctx.redis, {
      user_ids: userIds,
      frame: { t: "chat_removed", d: { chat_id: chatId } },
    });
  }

  /**
   * A service message in the thread — "X added Y", "X changed the title".
   *
   * Attributed to the person who did it, the same way Telegram does, because an
   * unattributed "someone was removed" is the kind of ambiguity that starts
   * arguments in a family group. Posted through the normal message path so it
   * gets a seq, syncs, and appears in history like anything else.
   */
  async function postSystemMessage(
    chatId: string,
    actorId: string,
    event: "chat_created" | "member_added" | "member_removed" | "title_changed",
    meta: Record<string, string>,
  ): Promise<void> {
    try {
      const { message } = await messagesRepo.insertMessage(ctx.db, {
        chatId,
        senderId: actorId,
        clientId: crypto.randomUUID(),
        payload: { type: "system", event, meta },
      });
      const memberIds = await chatsRepo.getMemberIds(ctx.db, chatId);
      await publishFanout(ctx.redis, {
        user_ids: memberIds,
        frame: { t: "message", d: message },
      });
    } catch (err) {
      // A service message is a nicety. Failing to write "X joined" must never
      // fail the join itself.
      app.log.warn({ err, chatId, event }, "system message failed");
    }
  }

  /** Throws unless the caller may administer this chat. */
  async function requireAdmin(
    chatId: string,
    userId: string,
  ): Promise<{ role: MemberRole; kind: "direct" | "group" | "channel" }> {
    const membership = await chatsRepo.getMembership(ctx.db, chatId, userId);
    if (!membership) throw new DomainError("forbidden", "not a member of this chat");
    if (membership.role === "member") {
      throw new DomainError("forbidden", "only admins can do that");
    }
    return membership;
  }

  app.get("/chats", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const chats = await chatsRepo.listChatsForUser(ctx.db, userId);
    return reply.send({ chats });
  });

  app.post("/chats", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const body = CreateChatBody.parse(req.body);

    let chatId: string;
    switch (body.kind) {
      case "direct":
        chatId = await chatsRepo.createDirectChat(ctx.db, userId, body.peer_id);
        break;
      case "group":
        chatId = await chatsRepo.createGroupChat(
          ctx.db,
          userId,
          body.title,
          body.member_ids,
          body.description,
        );
        break;
      case "channel":
        chatId = await chatsRepo.createChannel(ctx.db, userId, {
          title: body.title,
          username: body.username?.toLowerCase(),
          description: body.description,
          memberIds: body.member_ids,
        });
        break;
    }

    const chat = (await chatsRepo.listChatsForUser(ctx.db, userId)).find((c) => c.id === chatId);
    if (!chat) throw new DomainError("not_found", "chat not found after creation");

    if (body.kind !== "direct") {
      await postSystemMessage(chatId, userId, "chat_created", { title: body.title });
    }
    await announce(
      chatId,
      (await chatsRepo.getMemberIds(ctx.db, chatId)).filter((id) => id !== userId),
    );

    return reply.status(201).send(chat);
  });

  /**
   * Join a public channel by its handle.
   *
   * The one place membership is self-service. A group needs an invitation; a
   * channel with a public username is, by definition, meant to be walked into.
   */
  app.post("/chats/join", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { username } = z.object({ username: ChatUsername }).parse(req.body);

    const found = await chatsRepo.findByUsername(ctx.db, username);
    if (!found) throw new DomainError("not_found", `no channel called @${username}`);
    if (found.kind !== "channel") {
      throw new DomainError("forbidden", "only channels can be joined by link");
    }

    await chatsRepo.addMembers(ctx.db, found.id, [userId]);

    const chat = (await chatsRepo.listChatsForUser(ctx.db, userId)).find((c) => c.id === found.id);
    if (!chat) throw new DomainError("not_found", "chat not found after joining");
    return reply.status(200).send(chat);
  });

  app.patch("/chats/:id", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { id: chatId } = ChatIdParams.parse(req.params);
    const patch = UpdateChatBody.parse(req.body);

    const membership = await requireAdmin(chatId, userId);
    if (membership.kind === "direct") {
      throw new DomainError("bad_request", "a direct chat has no title to change");
    }
    if (patch.username !== undefined && membership.kind !== "channel") {
      throw new DomainError("bad_request", "only a channel can have a public handle");
    }

    await chatsRepo.updateChat(ctx.db, chatId, {
      title: patch.title,
      description: patch.description,
      username: patch.username === undefined ? undefined : patch.username?.toLowerCase() ?? null,
    });

    if (patch.title) {
      await postSystemMessage(chatId, userId, "title_changed", { title: patch.title });
    }
    const memberIds = await chatsRepo.getMemberIds(ctx.db, chatId);
    await announce(chatId, memberIds);

    const chat = (await chatsRepo.listChatsForUser(ctx.db, userId)).find((c) => c.id === chatId);
    return reply.send(chat);
  });

  app.get("/chats/:id/members", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { id: chatId } = ChatIdParams.parse(req.params);
    if (!(await chatsRepo.isMember(ctx.db, chatId, userId))) {
      throw new DomainError("forbidden", "not a member of this chat");
    }
    const query = z
      .object({
        limit: z.coerce.number().int().positive().max(200).default(100),
        offset: z.coerce.number().int().nonnegative().default(0),
      })
      .parse(req.query);

    const result = await chatsRepo.listMembers(ctx.db, chatId, query.limit, query.offset);
    return reply.send(result);
  });

  app.post("/chats/:id/members", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { id: chatId } = ChatIdParams.parse(req.params);
    const body = AddMembersBody.parse(req.body);

    const membership = await chatsRepo.getMembership(ctx.db, chatId, userId);
    if (!membership) throw new DomainError("forbidden", "not a member of this chat");
    if (membership.kind === "direct") {
      throw new DomainError("bad_request", "a direct chat has exactly two people");
    }
    // Any group member may add someone; a channel is an announcement surface and
    // its audience is the admins' business.
    if (membership.kind === "channel" && membership.role === "member") {
      throw new DomainError("forbidden", "only admins can add subscribers to a channel");
    }

    const added = await chatsRepo.addMembers(ctx.db, chatId, body.user_ids);
    if (added.length > 0) {
      await postSystemMessage(chatId, userId, "member_added", {
        count: String(added.length),
        first: added[0]!,
      });
      await announce(chatId, await chatsRepo.getMemberIds(ctx.db, chatId));
    }
    return reply.status(200).send({ added });
  });

  app.delete("/chats/:id/members/:userId", async (req, reply) => {
    const { userId: actorId } = await requireAuth(ctx, req);
    const params = z
      .object({ id: z.string().uuid(), userId: z.string().uuid() })
      .parse(req.params);

    const leaving = params.userId === actorId;
    const membership = leaving
      ? await chatsRepo.getMembership(ctx.db, params.id, actorId)
      : await requireAdmin(params.id, actorId);
    if (!membership) throw new DomainError("forbidden", "not a member of this chat");
    if (membership.kind === "direct") {
      throw new DomainError("bad_request", "a direct chat cannot be left");
    }
    if (!leaving) {
      const target = await chatsRepo.getMembership(ctx.db, params.id, params.userId);
      if (target?.role === "owner") {
        throw new DomainError("forbidden", "the owner cannot be removed");
      }
    }

    // The service message goes first, while they are still a member and the
    // fan-out list still includes them: "you were removed" is information they
    // are entitled to see.
    await postSystemMessage(params.id, actorId, "member_removed", { user_id: params.userId });
    await chatsRepo.removeMember(ctx.db, params.id, params.userId);

    await announceRemoval(params.id, [params.userId]);
    await announce(params.id, await chatsRepo.getMemberIds(ctx.db, params.id));

    return reply.status(204).send();
  });

  app.post("/chats/:id/role", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const { id: chatId } = ChatIdParams.parse(req.params);
    const body = SetRoleBody.parse(req.body);

    const membership = await chatsRepo.getMembership(ctx.db, chatId, userId);
    // Promoting admins is the owner's call alone. An admin who can mint admins
    // can lock the owner out of their own channel.
    if (membership?.role !== "owner") {
      throw new DomainError("forbidden", "only the owner can change roles");
    }

    await chatsRepo.setMemberRole(ctx.db, chatId, body.user_id, body.role);
    await announce(chatId, [body.user_id]);
    return reply.status(204).send();
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

export type { ChatSummary };
