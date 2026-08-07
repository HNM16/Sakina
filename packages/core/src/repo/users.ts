import { and, eq, isNull } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { devices, users } from "@sakina/db";
import type { Platform, PublicUser } from "@sakina/protocol";

export function toPublicUser(row: typeof users.$inferSelect): PublicUser {
  return {
    id: row.id,
    username: row.username,
    display_name: row.displayName,
    avatar_key: row.avatarKey,
    kind: row.kind,
  };
}

export async function findByPhone(db: Database, phone: string) {
  const rows = await db.select().from(users).where(eq(users.phone, phone)).limit(1);
  return rows[0] ?? null;
}

export async function findById(db: Database, id: string) {
  const rows = await db.select().from(users).where(eq(users.id, id)).limit(1);
  return rows[0] ?? null;
}

/**
 * Registration is implicit: a verified phone number that we have not seen
 * before becomes an account. The display name is a placeholder the user edits
 * later — asking for it before the first message is friction we do not need.
 */
export async function findOrCreateByPhone(db: Database, phone: string) {
  const existing = await findByPhone(db, phone);
  if (existing) return existing;

  const created = await db
    .insert(users)
    .values({ phone, displayName: phone })
    .onConflictDoNothing({ target: users.phone })
    .returning();

  return created[0] ?? (await findByPhone(db, phone))!;
}

export interface UpsertDeviceInput {
  deviceId: string;
  userId: string;
  platform: Platform;
  name: string;
  pushToken?: string | undefined;
}

export async function upsertDevice(db: Database, input: UpsertDeviceInput) {
  const created = await db
    .insert(devices)
    .values({
      id: input.deviceId,
      userId: input.userId,
      platform: input.platform,
      name: input.name,
      pushToken: input.pushToken ?? null,
      lastSeenAt: new Date(),
    })
    .onConflictDoUpdate({
      target: devices.id,
      set: {
        userId: input.userId,
        platform: input.platform,
        name: input.name,
        pushToken: input.pushToken ?? null,
        lastSeenAt: new Date(),
        revokedAt: null,
      },
    })
    .returning();

  return created[0]!;
}

export async function listDevices(db: Database, userId: string) {
  return db
    .select()
    .from(devices)
    .where(and(eq(devices.userId, userId), isNull(devices.revokedAt)));
}

export async function touchDevice(db: Database, deviceId: string): Promise<void> {
  await db.update(devices).set({ lastSeenAt: new Date() }).where(eq(devices.id, deviceId));
}
