import type { FastifyInstance } from "fastify";
import { usersRepo } from "@sakina/core";
import { PushTokenBody } from "@sakina/protocol";
import { requireAuth, type AppContext } from "../app.js";

export function registerDeviceRoutes(app: FastifyInstance, ctx: AppContext): void {
  /**
   * Called once the OS hands the app a push token — after the user grants
   * notification permission, and again whenever the platform rotates it.
   * Tokens rotate more often than people expect: reinstalls, restores from
   * backup, some OS updates.
   */
  app.post("/devices/push-token", async (req, reply) => {
    const { userId, deviceId } = await requireAuth(ctx, req);
    const body = PushTokenBody.parse(req.body);

    // Scoped to the caller's own device — a token can only ever be attached to
    // the device the access token was issued for.
    if (body.device_id !== deviceId) {
      return reply
        .status(403)
        .send({ error: { code: "forbidden", message: "token must be for the calling device" } });
    }

    await usersRepo.setPushToken(ctx.db, {
      deviceId,
      userId,
      token: body.token,
      provider: body.provider,
    });

    return reply.status(204).send();
  });

  /** Turning notifications off, and what sign-out should call. */
  app.delete("/devices/push-token", async (req, reply) => {
    const { deviceId } = await requireAuth(ctx, req);
    await usersRepo.clearPushToken(ctx.db, deviceId);
    return reply.status(204).send();
  });
}
