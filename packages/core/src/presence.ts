import type { Redis } from "ioredis";

/**
 * Who is currently connected, shared across gateway processes.
 *
 * The gateway's in-process registry only knows about its own sockets. Deciding
 * whether to send a push is a question about *every* node — "is this device
 * connected anywhere?" — so it has to live somewhere shared.
 *
 * Keyed per device, not per user, because the decision is per device. If
 * someone has the web client open on a laptop and their phone in a pocket, the
 * phone still needs the notification.
 *
 * Every key carries a TTL and is refreshed by the gateway's heartbeat. A
 * gateway that is killed uncleanly leaves keys behind; they expire on their own
 * within one TTL. The failure mode is a suppressed push for up to that long,
 * which is why the TTL is short.
 */

const PREFIX = "sakina:presence:";

/** Comfortably longer than the gateway's 30s heartbeat, short enough to self-heal. */
export const PRESENCE_TTL_SECONDS = 90;

export function presenceKey(deviceId: string): string {
  return PREFIX + deviceId;
}

export async function markOnline(
  redis: Redis,
  deviceId: string,
  ttlSeconds = PRESENCE_TTL_SECONDS,
): Promise<void> {
  await redis.set(presenceKey(deviceId), "1", "EX", ttlSeconds);
}

export async function markOffline(redis: Redis, deviceId: string): Promise<void> {
  await redis.del(presenceKey(deviceId));
}

export async function isOnline(redis: Redis, deviceId: string): Promise<boolean> {
  return (await redis.exists(presenceKey(deviceId))) === 1;
}

/**
 * Which of these devices are connected right now. One round trip regardless of
 * how many devices are being asked about — a group message may need to check a
 * few hundred.
 */
export async function onlineDevices(redis: Redis, deviceIds: string[]): Promise<Set<string>> {
  if (deviceIds.length === 0) return new Set();

  const pipeline = redis.pipeline();
  for (const id of deviceIds) pipeline.exists(presenceKey(id));
  const results = await pipeline.exec();

  const online = new Set<string>();
  results?.forEach((entry, index) => {
    const [err, value] = entry as [Error | null, unknown];
    if (!err && value === 1) online.add(deviceIds[index]!);
  });

  return online;
}
