import type { Redis } from "ioredis";
import type { ServerFrame } from "@sakina/protocol";

/**
 * The cross-process fan-out channel.
 *
 * Defined here rather than in the gateway because the API publishes onto it
 * too. When someone is added to a group, the API is the process that knows —
 * and the members who need to hear about it are holding sockets on the gateway.
 * Two processes agreeing on a channel name by copying a string literal is how
 * you get a feature that works until someone renames it.
 *
 * The gateway owns the subscribe side; this module is deliberately
 * publish-only, so nothing here needs to know about connection registries.
 */
export const FANOUT_CHANNEL = "sakina:fanout";

export interface FanoutEnvelope {
  user_ids: string[];
  frame: ServerFrame;
  exclude_device_id?: string | undefined;
}

export async function publishFanout(redis: Redis, envelope: FanoutEnvelope): Promise<void> {
  if (envelope.user_ids.length === 0) return;
  await redis.publish(FANOUT_CHANNEL, JSON.stringify(envelope));
}
