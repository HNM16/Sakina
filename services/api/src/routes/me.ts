import type { FastifyInstance } from "fastify";
import { DomainError, usersRepo } from "@sakina/core";
import { requireAuth, type AppContext } from "../app.js";

export function registerMeRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.get("/me", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);

    const user = await usersRepo.findById(ctx.db, userId);
    if (!user) throw new DomainError("not_found", "user not found");

    const devices = await usersRepo.listDevices(ctx.db, userId);

    return reply.send({
      user: usersRepo.toPublicUser(user),
      devices: devices.map((d) => ({
        id: d.id,
        platform: d.platform,
        name: d.name,
        last_seen_at: d.lastSeenAt?.getTime() ?? null,
        created_at: d.createdAt.getTime(),
      })),
    });
  });
}
