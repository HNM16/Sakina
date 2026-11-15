import { createServer, type Server } from "node:http";
import { Redis } from "ioredis";
import { createDb } from "@sakina/db";
import {
  ApnsPushProvider,
  ConsolePushProvider,
  dequeuePush,
  FcmPushProvider,
  onlineDevices,
  pushCopy,
  queueDepth,
  usersRepo,
  type PushJob,
  type PushMessage,
  type PushProvider,
} from "@sakina/core";
import type { Env } from "./env.js";

/**
 * Turns "a message was stored" into "a phone buzzes".
 *
 * Sits behind a Redis queue rather than in the gateway's send path, because
 * calling FCM or APNs is an HTTP round trip to a third party that can be slow
 * or down, and the person watching the send spinner must not wait for it.
 */

export interface WorkerStats {
  processed: number;
  sent: number;
  skippedOnline: number;
  retired: number;
  failed: number;
}

export async function startWorker(env: Env) {
  const { db, sql } = createDb(env.DATABASE_URL);
  const redis = new Redis(env.REDIS_URL, { maxRetriesPerRequest: null });

  const consoleProvider = new ConsolePushProvider();
  const providers = buildProviders(env, consoleProvider);

  const stats: WorkerStats = {
    processed: 0,
    sent: 0,
    skippedOnline: 0,
    retired: 0,
    failed: 0,
  };

  let running = true;

  async function handle(job: PushJob): Promise<void> {
    stats.processed += 1;

    const targets = await usersRepo.pushTargetsForUsers(db, job.recipient_ids);
    if (targets.length === 0) return;

    // The whole point of presence: a device with the app open already has the
    // message on screen. Notifying it would be noise.
    const live = await onlineDevices(
      redis,
      targets.map((t) => t.deviceId),
    );

    const copy = pushCopy("tg", job.is_group);

    for (const target of targets) {
      if (target.deviceId === job.exclude_device_id) continue;
      if (live.has(target.deviceId)) {
        stats.skippedOnline += 1;
        continue;
      }
      if (!target.pushToken || target.pushProvider === "none") continue;

      const message: PushMessage = {
        token: target.pushToken,
        title: copy.title,
        body: copy.body,
        // No message text, ever. The client wakes, syncs by seq, and renders
        // the real content locally. See packages/core/src/push.ts.
        data: {
          chat_id: job.chat_id,
          seq: String(job.seq),
          message_id: job.message_id,
          sender_id: job.sender_id,
        },
        // Ten unread messages in one chat should be one notification, not ten.
        collapseKey: job.chat_id,
      };

      const provider = providers[target.pushProvider];
      if (!provider) continue;

      const outcome = await provider.send(message);

      switch (outcome.status) {
        case "sent":
          stats.sent += 1;
          await usersRepo.recordPushSuccess(db, target.deviceId);
          break;
        case "unregistered":
          // Authoritative — the app is gone from that device. Retire the token
          // rather than retrying it forever.
          stats.retired += 1;
          await usersRepo.recordPushFailure(db, target.deviceId, true);
          break;
        case "failed":
          stats.failed += 1;
          await usersRepo.recordPushFailure(db, target.deviceId, false);
          break;
      }
    }
  }

  async function loop(): Promise<void> {
    while (running) {
      try {
        const job = await dequeuePush(redis, 5);
        if (job) await handle(job);
      } catch (err) {
        // A bad job must not take the worker down with it.
        console.error("push job failed:", err);
        await new Promise((r) => setTimeout(r, 500));
      }
    }
  }

  const httpServer: Server = createServer(async (req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(
        JSON.stringify({
          ok: true,
          service: "worker",
          push_provider: env.PUSH_PROVIDER,
          queue_depth: await queueDepth(redis),
          ...stats,
        }),
      );
      return;
    }

    // Lets a test assert what was actually sent, without a handset or a
    // Firebase project. Off in production by construction — loadEnv refuses.
    if (req.url === "/dev/pushes" && env.PUSH_DEV_INSPECT) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ pushes: consoleProvider.sent }));
      return;
    }

    res.writeHead(404).end();
  });

  await new Promise<void>((resolve) => {
    httpServer.listen(env.WORKER_PORT, env.WORKER_HOST, resolve);
  });

  console.log(`worker listening on :${env.WORKER_PORT} (push: ${env.PUSH_PROVIDER})`);
  void loop();

  return {
    stats,
    async close() {
      running = false;
      await new Promise<void>((resolve) => httpServer.close(() => resolve()));
      await Promise.allSettled(Object.values(providers).map((p) => p?.close?.()));
      redis.disconnect();
      await sql.end();
    },
  };
}

function buildProviders(
  env: Env,
  consoleProvider: ConsolePushProvider,
): Partial<Record<"fcm" | "apns", PushProvider>> {
  if (env.PUSH_PROVIDER === "console") {
    return { fcm: consoleProvider, apns: consoleProvider };
  }

  const providers: Partial<Record<"fcm" | "apns", PushProvider>> = {};

  if (env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY) {
    providers.fcm = new FcmPushProvider({
      projectId: env.FCM_PROJECT_ID,
      clientEmail: env.FCM_CLIENT_EMAIL,
      privateKey: env.FCM_PRIVATE_KEY,
    });
  }

  if (env.APNS_TEAM_ID && env.APNS_KEY_ID && env.APNS_PRIVATE_KEY) {
    providers.apns = new ApnsPushProvider({
      teamId: env.APNS_TEAM_ID,
      keyId: env.APNS_KEY_ID,
      privateKey: env.APNS_PRIVATE_KEY,
      bundleId: env.APNS_BUNDLE_ID,
      environment: env.APNS_ENVIRONMENT,
    });
  }

  return providers;
}
