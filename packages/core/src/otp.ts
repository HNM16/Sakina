import { and, desc, eq, gt, isNull, sql } from "drizzle-orm";
import { createHmac, randomInt, timingSafeEqual } from "node:crypto";
import type { Database } from "@sakina/db";
import { otpCodes } from "@sakina/db";
import { DomainError } from "./errors.js";

export const OTP_TTL_SECONDS = 300;
export const OTP_MAX_ATTEMPTS = 5;
/** Cooldown between code requests for the same number. SMS to +992 costs real money. */
export const OTP_RESEND_COOLDOWN_SECONDS = 60;

function hashCode(phone: string, code: string, pepper: string): string {
  // Peppered HMAC, not a bare hash: a leaked otp_codes table must not be
  // brute-forceable offline against a 6-digit space.
  return createHmac("sha256", pepper).update(`${phone}:${code}`).digest("hex");
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

export async function issueOtp(
  db: Database,
  phone: string,
  pepper: string,
): Promise<{ code: string; expiresAt: Date }> {
  const cooldownStart = new Date(Date.now() - OTP_RESEND_COOLDOWN_SECONDS * 1000);
  const recent = await db
    .select({ id: otpCodes.id })
    .from(otpCodes)
    .where(and(eq(otpCodes.phone, phone), gt(otpCodes.createdAt, cooldownStart)))
    .limit(1);

  if (recent[0]) {
    throw new DomainError("rate_limited", "a code was already sent; wait before requesting another");
  }

  const code = generateOtpCode();
  const expiresAt = new Date(Date.now() + OTP_TTL_SECONDS * 1000);

  await db.insert(otpCodes).values({
    phone,
    codeHash: hashCode(phone, code, pepper),
    expiresAt,
  });

  return { code, expiresAt };
}

export async function verifyOtp(
  db: Database,
  phone: string,
  code: string,
  pepper: string,
): Promise<void> {
  const rows = await db
    .select()
    .from(otpCodes)
    .where(and(eq(otpCodes.phone, phone), isNull(otpCodes.consumedAt)))
    .orderBy(desc(otpCodes.createdAt))
    .limit(1);

  const row = rows[0];
  if (!row) throw new DomainError("unauthorized", "no pending code for this number");
  if (row.expiresAt.getTime() < Date.now()) throw new DomainError("unauthorized", "code expired");
  if (row.attempts >= OTP_MAX_ATTEMPTS) {
    throw new DomainError("rate_limited", "too many attempts; request a new code");
  }

  if (!constantTimeEqual(row.codeHash, hashCode(phone, code, pepper))) {
    await db
      .update(otpCodes)
      .set({ attempts: sql`${otpCodes.attempts} + 1` })
      .where(eq(otpCodes.id, row.id));
    throw new DomainError("unauthorized", "invalid code");
  }

  await db.update(otpCodes).set({ consumedAt: new Date() }).where(eq(otpCodes.id, row.id));
}
