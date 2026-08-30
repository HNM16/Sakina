import { and, desc, eq, gt, isNull, sql } from "drizzle-orm";
import { createHmac, randomInt, timingSafeEqual } from "node:crypto";
import type { Database } from "@sakina/db";
import { otpCodes } from "@sakina/db";
import { DomainError } from "./errors.js";

export type IdentityKind = "email" | "phone";

export const OTP_TTL_SECONDS = 600;
export const OTP_MAX_ATTEMPTS = 5;
/** Cooldown between code requests for one identity. */
export const OTP_RESEND_COOLDOWN_SECONDS = 60;

function hashCode(canonical: string, code: string, pepper: string): string {
  // Peppered HMAC, not a bare hash: a leaked otp_codes table must not be
  // brute-forceable offline against a 6-digit space.
  return createHmac("sha256", pepper).update(`${canonical}:${code}`).digest("hex");
}

function constantTimeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export function generateOtpCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, "0");
}

/**
 * Reserved test identities: fixed value/code pairs that skip delivery entirely.
 *
 * Not a development shortcut to strip before launch — a permanent production
 * requirement. Apple's and Google's reviewers cannot receive a Tajik SMS, and
 * an app they cannot sign into is an app they reject. Firebase Auth ships the
 * same mechanism for the same reason. It also happens to be how you sign in
 * while building from another country.
 *
 * Format: "qa@sakina.tj:000000,+992000000001:111111"
 *
 * Safety properties, since this does bypass delivery:
 *  - an explicit allowlist, never a pattern or prefix rule;
 *  - the code is still checked in constant time, so a reserved identity with
 *    the wrong code is rejected exactly like any other;
 *  - values are compared canonically, so a reserved address cannot be reached
 *    by a dotted or plus-tagged variant that skipped normalisation.
 */
export function parseTestIdentities(raw: string): Map<string, string> {
  const entries = new Map<string, string>();

  for (const pair of raw.split(",")) {
    const trimmed = pair.trim();
    if (!trimmed) continue;

    const separator = trimmed.lastIndexOf(":");
    if (separator === -1) continue;

    const value = trimmed.slice(0, separator).trim().toLowerCase();
    const code = trimmed.slice(separator + 1).trim();

    if (!value || !/^\d{6}$/.test(code)) continue;
    entries.set(value, code);
  }

  return entries;
}

export interface OtpOptions {
  testIdentities?: Map<string, string> | undefined;
  /** Overrides OTP_RESEND_COOLDOWN_SECONDS. Set to 0 in tests. */
  resendCooldownSeconds?: number | undefined;
}

export interface IssuedOtp {
  code: string;
  expiresAt: Date;
  isTestIdentity: boolean;
}

export async function issueOtp(
  db: Database,
  kind: IdentityKind,
  canonical: string,
  pepper: string,
  options: OtpOptions = {},
): Promise<IssuedOtp> {
  const testCode = options.testIdentities?.get(canonical);
  if (testCode) {
    // No row and no cooldown: a reviewer or a developer re-requesting in a loop
    // must never lock themselves out of the only identity they have.
    return {
      code: testCode,
      expiresAt: new Date(Date.now() + OTP_TTL_SECONDS * 1000),
      isTestIdentity: true,
    };
  }

  const cooldown = options.resendCooldownSeconds ?? OTP_RESEND_COOLDOWN_SECONDS;
  const cooldownStart = new Date(Date.now() - cooldown * 1000);
  const recent = cooldown <= 0 ? [] : await db
    .select({ id: otpCodes.id })
    .from(otpCodes)
    .where(
      and(
        eq(otpCodes.kind, kind),
        eq(otpCodes.canonical, canonical),
        gt(otpCodes.createdAt, cooldownStart),
      ),
    )
    .limit(1);

  if (recent[0]) {
    throw new DomainError("rate_limited", "a code was already sent; wait before requesting another");
  }

  const code = generateOtpCode();
  const expiresAt = new Date(Date.now() + OTP_TTL_SECONDS * 1000);

  await db.insert(otpCodes).values({
    kind,
    canonical,
    codeHash: hashCode(canonical, code, pepper),
    expiresAt,
  });

  return { code, expiresAt, isTestIdentity: false };
}

export async function verifyOtp(
  db: Database,
  kind: IdentityKind,
  canonical: string,
  code: string,
  pepper: string,
  options: OtpOptions = {},
): Promise<void> {
  const testCode = options.testIdentities?.get(canonical);
  if (testCode) {
    // Still a real check, still constant time. A reserved identity skips
    // delivery; it does not skip verification.
    if (!constantTimeEqual(testCode, code)) {
      throw new DomainError("unauthorized", "invalid code");
    }
    return;
  }

  const rows = await db
    .select()
    .from(otpCodes)
    .where(
      and(eq(otpCodes.kind, kind), eq(otpCodes.canonical, canonical), isNull(otpCodes.consumedAt)),
    )
    .orderBy(desc(otpCodes.createdAt))
    .limit(1);

  const row = rows[0];
  if (!row) throw new DomainError("unauthorized", "no pending code for this address");
  if (row.expiresAt.getTime() < Date.now()) throw new DomainError("unauthorized", "code expired");
  if (row.attempts >= OTP_MAX_ATTEMPTS) {
    throw new DomainError("rate_limited", "too many attempts; request a new code");
  }

  if (!constantTimeEqual(row.codeHash, hashCode(canonical, code, pepper))) {
    await db
      .update(otpCodes)
      .set({ attempts: sql`${otpCodes.attempts} + 1` })
      .where(eq(otpCodes.id, row.id));
    throw new DomainError("unauthorized", "invalid code");
  }

  await db.update(otpCodes).set({ consumedAt: new Date() }).where(eq(otpCodes.id, row.id));
}
