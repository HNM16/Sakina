import { Redis } from "ioredis";
import { z } from "zod";
import type { ServerFrame } from "@sakina/protocol";

/**
 * Cross-node fan-out.
 *
 * Every gateway process publishes onto one Redis channel and every process
 * receives everything, delivering only to the users it currently holds. That is
 * O(nodes) chatter per message — fine for a single node and fine for a handful,
 * and deliberately the simplest thing that is correct.
 *
 * It stops being fine somewhere in the tens of nodes. The fix then is to shard
 * the channel by a hash of user_id so a node subscribes only to the shards it
 * serves. The envelope below already carries everything that needs; nothing on
 * the client side changes.
 */

export const FANOUT_CHANNEL = "sakina:fanout";

const Envelope = z.object({
  user_ids: z.array(z.string().uuid()),
  frame: z.unknown(),
  exclude_device_id: z.string().uuid().optional(),
});

export interface FanoutEnvelope {
  user_ids: string[];
  frame: ServerFrame;
  exclude_device_id?: string | undefined;
}

export interface Bus {
  publish(envelope: FanoutEnvelope): Promise<void>;
  /** Shared connection for presence and the push queue. */
  readonly redis: Redis;
  close(): Promise<void>;
}

export function createBus(
  redisUrl: string,
  onEnvelope: (envelope: FanoutEnvelope) => void,
): Bus {
  const publisher = new Redis(redisUrl, { maxRetriesPerRequest: null });
  const subscriber = new Redis(redisUrl, { maxRetriesPerRequest: null });

  void subscriber.subscribe(FANOUT_CHANNEL);

  subscriber.on("message", (channel: string, raw: string) => {
    if (channel !== FANOUT_CHANNEL) return;
    try {
      const parsed = Envelope.safeParse(JSON.parse(raw));
      if (!parsed.success) return;
      onEnvelope({
        user_ids: parsed.data.user_ids,
        frame: parsed.data.frame as ServerFrame,
        exclude_device_id: parsed.data.exclude_device_id,
      });
    } catch {
      // A malformed envelope is a bug in a peer, not a reason to drop this node.
    }
  });

  return {
    redis: publisher,
    async publish(envelope) {
      await publisher.publish(FANOUT_CHANNEL, JSON.stringify(envelope));
    },
    async close() {
      await Promise.allSettled([publisher.quit(), subscriber.quit()]);
    },
  };
}
