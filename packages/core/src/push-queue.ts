import type { Redis } from "ioredis";
import { z } from "zod";

/**
 * The hand-off from "message stored" to "phone buzzes".
 *
 * The gateway does not call FCM or APNs itself. Sending is an HTTP round trip
 * to a third party that can be slow or down, and the send path — which a user
 * is watching a spinner on — must not wait for it. So the gateway pushes a job
 * onto a Redis list and returns; a worker drains it.
 *
 * Reliability, stated plainly: this is a list with BRPOP, which is at-most-once.
 * A worker killed between popping a job and sending it loses that job. That is
 * an accepted trade for now, because the *message* is already durably stored —
 * the cost of a lost job is a delayed notification, not a lost message, and the
 * client syncs everything when it next opens.
 *
 * When push reliability starts to matter more than simplicity, the upgrade is a
 * Redis Stream with a consumer group, which gives acknowledgement and redelivery
 * for roughly twenty more lines. The job shape below does not change.
 */

export const PUSH_QUEUE_KEY = "sakina:push:queue";

/** Keeps a burst from consuming unbounded memory if the worker is down. */
export const PUSH_QUEUE_MAX = 10_000;

export const PushJob = z.object({
  chat_id: z.string().uuid(),
  seq: z.number().int().positive(),
  message_id: z.string().uuid(),
  sender_id: z.string().uuid(),
  /** Everyone who should be considered. The worker filters out live devices. */
  recipient_ids: z.array(z.string().uuid()),
  /** The sending device never gets a push for its own message. */
  exclude_device_id: z.string().uuid().optional(),
  is_group: z.boolean().default(false),
  queued_at: z.number().int(),
});
export type PushJob = z.infer<typeof PushJob>;

export async function enqueuePush(redis: Redis, job: PushJob): Promise<void> {
  // LPUSH then LTRIM: if the worker is down, old jobs are dropped rather than
  // the queue growing until Redis falls over. A stale notification is worthless
  // anyway.
  await redis
    .pipeline()
    .lpush(PUSH_QUEUE_KEY, JSON.stringify(job))
    .ltrim(PUSH_QUEUE_KEY, 0, PUSH_QUEUE_MAX - 1)
    .exec();
}

/** Blocks until a job arrives or `timeoutSeconds` elapses. */
export async function dequeuePush(redis: Redis, timeoutSeconds = 5): Promise<PushJob | null> {
  const popped = await redis.brpop(PUSH_QUEUE_KEY, timeoutSeconds);
  if (!popped) return null;

  const parsed = PushJob.safeParse(JSON.parse(popped[1]));
  // A malformed job is a bug in a peer, not a reason to stop the worker.
  return parsed.success ? parsed.data : null;
}

export async function queueDepth(redis: Redis): Promise<number> {
  return redis.llen(PUSH_QUEUE_KEY);
}
