import { and, eq, inArray, isNotNull, isNull, ne, sql } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { devices, identities, users } from "@sakina/db";
import type { Platform, PublicUser } from "@sakina/protocol";
import { DomainError } from "../errors.js";
import type { IdentityKind } from "../otp.js";

export function toPublicUser(row: typeof users.$inferSelect): PublicUser {
  return {
    id: row.id,
    username: row.username,
    display_name: row.displayName,
    avatar_key: row.avatarKey,
    kind: row.kind,
  };
}

export async function findById(db: Database, id: string) {
  const rows = await db.select().from(users).where(eq(users.id, id)).limit(1);
  return rows[0] ?? null;
}

/** Lookup is always by canonical form — that is the whole point of storing it. */
export async function findByIdentity(db: Database, kind: IdentityKind, canonical: string) {
  const rows = await db
    .select({ user: users })
    .from(identities)
    .innerJoin(users, eq(users.id, identities.userId))
    .where(and(eq(identities.kind, kind), eq(identities.canonical, canonical)))
    .limit(1);

  return rows[0]?.user ?? null;
}

export interface ResolveIdentityInput {
  kind: IdentityKind;
  /** As typed, for display. */
  value: string;
  /** Normalised, for uniqueness. */
  canonical: string;
  /** Placeholder display name for a brand-new account. */
  displayName: string;
}

export interface ResolvedIdentity {
  user: typeof users.$inferSelect;
  /** False when this identity already belonged to someone — a returning user. */
  isNewUser: boolean;
}

/**
 * Resolve a verified identity to an account, creating one if this is the first
 * time we have seen it.
 *
 * The unique index on `(kind, canonical)` is what makes this safe: two requests
 * racing with `john+a@gmail.com` and `j.ohn@gmail.com` both canonicalise to the
 * same string, so exactly one insert wins and the loser reads back the winner's
 * account instead of creating a second one.
 */
export async function resolveIdentity(
  db: Database,
  input: ResolveIdentityInput,
): Promise<ResolvedIdentity> {
  const existing = await findByIdentity(db, input.kind, input.canonical);
  if (existing) return { user: existing, isNewUser: false };

  try {
    return await db.transaction(async (tx) => {
      const created = await tx
        .insert(users)
        .values({ displayName: input.displayName })
        .returning();

      const user = created[0];
      if (!user) throw new DomainError("conflict", "user insert returned no row");

      await tx.insert(identities).values({
        userId: user.id,
        kind: input.kind,
        value: input.value,
        canonical: input.canonical,
        verifiedAt: new Date(),
      });

      return { user, isNewUser: true };
    });
  } catch (err) {
    // Lost the race on the unique index — the other request's account is the
    // real one. The orphaned user row is rolled back with the transaction.
    const raced = await findByIdentity(db, input.kind, input.canonical);
    if (raced) return { user: raced, isNewUser: false };
    throw err;
  }
}

/** Attach an additional identity — how a phone number gets added at launch. */
export async function linkIdentity(
  db: Database,
  userId: string,
  input: Omit<ResolveIdentityInput, "displayName">,
): Promise<void> {
  const owner = await findByIdentity(db, input.kind, input.canonical);
  if (owner && owner.id !== userId) {
    throw new DomainError("conflict", "that address is already linked to another account");
  }
  if (owner) return;

  await db.insert(identities).values({
    userId,
    kind: input.kind,
    value: input.value,
    canonical: input.canonical,
    verifiedAt: new Date(),
  });
}

export async function listIdentities(db: Database, userId: string) {
  return db.select().from(identities).where(eq(identities.userId, userId));
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

// ---------------------------------------------------------------------------
// Push
// ---------------------------------------------------------------------------

export type PushProviderKind = "fcm" | "apns" | "none";

/**
 * Push targets for a set of users: every device that has a live token and has
 * not been retired. The worker then removes the ones currently holding a socket.
 */
export async function pushTargetsForUsers(db: Database, userIds: string[]) {
  if (userIds.length === 0) return [];

  return db
    .select({
      deviceId: devices.id,
      userId: devices.userId,
      platform: devices.platform,
      pushToken: devices.pushToken,
      pushProvider: devices.pushProvider,
    })
    .from(devices)
    .where(
      and(
        inArray(devices.userId, userIds),
        isNull(devices.revokedAt),
        isNull(devices.pushDisabledAt),
        isNotNull(devices.pushToken),
        ne(devices.pushProvider, "none"),
      ),
    );
}

export interface SetPushTokenInput {
  deviceId: string;
  userId: string;
  token: string;
  provider: PushProviderKind;
}

/** Registering a token clears any previous failure state — it is a new token. */
export async function setPushToken(db: Database, input: SetPushTokenInput): Promise<void> {
  await db
    .update(devices)
    .set({
      pushToken: input.token,
      pushProvider: input.provider,
      pushFailures: 0,
      pushDisabledAt: null,
    })
    .where(and(eq(devices.id, input.deviceId), eq(devices.userId, input.userId)));
}

export async function clearPushToken(db: Database, deviceId: string): Promise<void> {
  await db
    .update(devices)
    .set({ pushToken: null, pushProvider: "none", pushFailures: 0, pushDisabledAt: null })
    .where(eq(devices.id, deviceId));
}

/** How many consecutive soft failures before a token is retired. */
export const PUSH_FAILURE_LIMIT = 5;

/**
 * A provider saying "unregistered" is authoritative — retire immediately.
 * Anything else is transient and only counts toward the limit, because a
 * temporary FCM outage must not wipe every token on the platform.
 */
export async function recordPushFailure(
  db: Database,
  deviceId: string,
  permanent: boolean,
): Promise<void> {
  if (permanent) {
    await db
      .update(devices)
      .set({ pushDisabledAt: new Date(), pushToken: null, pushProvider: "none" })
      .where(eq(devices.id, deviceId));
    return;
  }

  const updated = await db
    .update(devices)
    .set({ pushFailures: sql`${devices.pushFailures} + 1` })
    .where(eq(devices.id, deviceId))
    .returning({ failures: devices.pushFailures });

  if ((updated[0]?.failures ?? 0) >= PUSH_FAILURE_LIMIT) {
    await db.update(devices).set({ pushDisabledAt: new Date() }).where(eq(devices.id, deviceId));
  }
}

export async function recordPushSuccess(db: Database, deviceId: string): Promise<void> {
  await db.update(devices).set({ pushFailures: 0 }).where(eq(devices.id, deviceId));
}
