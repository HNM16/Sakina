import { and, eq, gt, isNull, or } from "drizzle-orm";
import { createHmac } from "node:crypto";
import type { Database } from "@sakina/db";
import { bans, deviceFingerprints, deviceFingerprintUsers } from "@sakina/db";
import type { Platform } from "@sakina/protocol";
import { DomainError } from "../errors.js";

/**
 * Making a ban stick when someone comes back with a new address.
 *
 * The honest version of what is achievable, because the folklore here is a
 * decade out of date. IMEI, serial number and MAC address are **not** available
 * to an ordinary app on any current Android or iOS — `getImei()` needs a
 * privileged permission no store app is granted, and the MAC has read back as
 * 02:00:00:00:00:00 since Android 6. Anyone promising hardware-level
 * identification from a normal app is describing 2015.
 *
 * What is actually available, per platform:
 *
 *   Android — `Settings.Secure.ANDROID_ID`. Scoped to our signing key and the
 *             user profile, stable across uninstall and reinstall, cleared by a
 *             factory reset. This is the good one.
 *   iOS     — a DeviceCheck bit. Apple forbids fingerprinting outright, and
 *             `identifierForVendor` resets once every app from the vendor is
 *             removed. DeviceCheck is Apple's sanctioned answer: two bits per
 *             device per developer, surviving uninstall and reinstall, cleared
 *             only by a factory reset. Two bits is enough for "this device is
 *             banned" and not much else — which is exactly the question here.
 *
 * So a ban survives: new email, new phone number, app deleted and reinstalled,
 * OS update. It does not survive: a factory reset, or a different phone. That
 * is the ceiling for everyone, Snapchat included — the goal is to make evasion
 * cost a factory reset or new hardware, not to make it impossible.
 *
 * The stronger signal for a small invite-only network is not hardware at all.
 * It is the invite graph: see `banUserAndDevices`, which walks the accounts a
 * banned device has touched.
 */

export type FingerprintSource =
  | "android_id"
  | "devicecheck"
  | "ios_vendor_id"
  | "web_none";

export interface DeviceFingerprintInput {
  platform: Platform;
  /** Raw platform identifier. Hashed here and never stored in the clear. */
  value: string;
  source: FingerprintSource;
  /** Play Integrity / App Attest said the app is genuine and unmodified. */
  attested: boolean;
}

/**
 * Weak sources still get recorded, but should not carry a ban on their own —
 * `ios_vendor_id` resets when the user removes every app from the vendor, so
 * banning on it alone would eventually punish an innocent device that inherited
 * the identifier space.
 */
export function isStrongSource(source: FingerprintSource): boolean {
  return source === "android_id" || source === "devicecheck";
}

export function hashFingerprint(value: string, pepper: string): string {
  return createHmac("sha256", pepper).update(value).digest("hex");
}

export async function recordFingerprint(
  db: Database,
  input: DeviceFingerprintInput,
  userId: string,
  pepper: string,
): Promise<string> {
  const fingerprintHash = hashFingerprint(input.value, pepper);

  const upserted = await db
    .insert(deviceFingerprints)
    .values({
      platform: input.platform,
      fingerprintHash,
      source: input.source,
      attested: input.attested,
    })
    .onConflictDoUpdate({
      target: [deviceFingerprints.platform, deviceFingerprints.fingerprintHash],
      set: { lastSeenAt: new Date(), attested: input.attested },
    })
    .returning({ id: deviceFingerprints.id });

  const fingerprintId = upserted[0]?.id;
  if (!fingerprintId) throw new DomainError("conflict", "fingerprint upsert returned no row");

  // The link table is the ban-propagation graph: one row per (device, account)
  // pair ever seen together.
  await db
    .insert(deviceFingerprintUsers)
    .values({ fingerprintId, userId })
    .onConflictDoNothing();

  return fingerprintId;
}

export async function findFingerprint(
  db: Database,
  platform: Platform,
  value: string,
  pepper: string,
): Promise<string | null> {
  const rows = await db
    .select({ id: deviceFingerprints.id })
    .from(deviceFingerprints)
    .where(
      and(
        eq(deviceFingerprints.platform, platform),
        eq(deviceFingerprints.fingerprintHash, hashFingerprint(value, pepper)),
      ),
    )
    .limit(1);

  return rows[0]?.id ?? null;
}

export interface ActiveBan {
  id: string;
  subject: "user" | "device";
  reason: string;
  expiresAt: Date | null;
}

async function activeBanFor(
  db: Database,
  subject: "user" | "device",
  subjectId: string,
): Promise<ActiveBan | null> {
  const rows = await db
    .select()
    .from(bans)
    .where(
      and(
        eq(bans.subject, subject),
        eq(bans.subjectId, subjectId),
        isNull(bans.liftedAt),
        or(isNull(bans.expiresAt), gt(bans.expiresAt, new Date())),
      ),
    )
    .limit(1);

  const ban = rows[0];
  return ban
    ? { id: ban.id, subject: ban.subject, reason: ban.reason, expiresAt: ban.expiresAt }
    : null;
}

export function banOnUser(db: Database, userId: string): Promise<ActiveBan | null> {
  return activeBanFor(db, "user", userId);
}

export function banOnDevice(db: Database, fingerprintId: string): Promise<ActiveBan | null> {
  return activeBanFor(db, "device", fingerprintId);
}

/**
 * The check that runs before a sign-in completes.
 *
 * Deliberately checks the device *before* the account, because the whole point
 * is the case where the account is brand new and only the hardware is known.
 */
export async function assertNotBanned(
  db: Database,
  opts: {
    userId?: string | undefined;
    platform: Platform;
    fingerprint?: string | undefined;
    pepper: string;
  },
): Promise<void> {
  if (opts.fingerprint) {
    const fingerprintId = await findFingerprint(db, opts.platform, opts.fingerprint, opts.pepper);
    if (fingerprintId) {
      const deviceBan = await banOnDevice(db, fingerprintId);
      if (deviceBan) {
        // Says nothing about which account or why in detail — a precise message
        // is a free hint about exactly what to change to evade next time.
        throw new DomainError("forbidden", "this device is not allowed to use Sakina");
      }
    }
  }

  if (opts.userId) {
    const userBan = await banOnUser(db, opts.userId);
    if (userBan) throw new DomainError("forbidden", "this account has been suspended");
  }
}

export interface BanInput {
  reason: string;
  createdBy?: string | undefined;
  expiresAt?: Date | undefined;
}

/**
 * Ban an account and every device it has been seen on, then every *other*
 * account those devices have been seen on.
 *
 * One hop, not transitive. Two accounts sharing a phone is common — a family,
 * a shared handset, a repaired device passed on — so walking further would
 * eventually ban a village. One hop catches the actual pattern (one person,
 * several accounts, one phone) without that.
 */
export async function banUserAndDevices(
  db: Database,
  userId: string,
  input: BanInput,
): Promise<{ users: string[]; devices: string[] }> {
  return db.transaction(async (tx) => {
    const fingerprints = await tx
      .select({ fingerprintId: deviceFingerprintUsers.fingerprintId })
      .from(deviceFingerprintUsers)
      .where(eq(deviceFingerprintUsers.userId, userId));

    const deviceIds = fingerprints.map((f) => f.fingerprintId);
    const userIds = new Set<string>([userId]);

    for (const fingerprintId of deviceIds) {
      const siblings = await tx
        .select({ userId: deviceFingerprintUsers.userId })
        .from(deviceFingerprintUsers)
        .where(eq(deviceFingerprintUsers.fingerprintId, fingerprintId));

      for (const sibling of siblings) userIds.add(sibling.userId);
    }

    const rows = [
      ...[...userIds].map((id) => ({
        subject: "user" as const,
        subjectId: id,
        reason: input.reason,
        createdBy: input.createdBy ?? null,
        expiresAt: input.expiresAt ?? null,
      })),
      ...deviceIds.map((id) => ({
        subject: "device" as const,
        subjectId: id,
        reason: input.reason,
        createdBy: input.createdBy ?? null,
        expiresAt: input.expiresAt ?? null,
      })),
    ];

    if (rows.length > 0) await tx.insert(bans).values(rows);

    return { users: [...userIds], devices: deviceIds };
  });
}

export async function liftBans(
  db: Database,
  subject: "user" | "device",
  subjectId: string,
  reason: string,
): Promise<void> {
  // Lifted, not deleted: "has this person been banned before" is a question
  // moderation will need answered, and a deleted row cannot answer it.
  await db
    .update(bans)
    .set({ liftedAt: new Date(), liftedReason: reason })
    .where(and(eq(bans.subject, subject), eq(bans.subjectId, subjectId), isNull(bans.liftedAt)));
}
