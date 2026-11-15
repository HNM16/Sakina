import { and, count, eq, gt, isNotNull } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { inviteCodes, inviteRedemptions, signupAttempts } from "@sakina/db";
import { randomBytes } from "node:crypto";
import { DomainError } from "../errors.js";

/**
 * Cost per account.
 *
 * Canonicalising addresses (see identity.ts) removes the free duplicate — the
 * same mailbox typed three ways. It does nothing about someone who simply
 * registers three different mailboxes, which takes about a minute.
 *
 * The only thing that limits that is making each additional account cost
 * something. Three layers, cheapest first:
 *
 *   1. per-device — one handset may create only so many accounts;
 *   2. per-network — one IP may create only so many accounts;
 *   3. invite codes — an account must be vouched for by an existing one.
 *
 * The third is the strong one, and for a five-to-ten-thousand-user beta it is
 * almost free to run: it also happens to be the growth mechanism, since a thing
 * people have to ask to get into spreads better than an open signup form.
 */

export interface SignupLimits {
  maxPerDevice: number;
  maxPerIp: number;
  windowHours: number;
  requireInvite: boolean;
}

export const DEFAULT_SIGNUP_LIMITS: SignupLimits = {
  // Generous enough for a shared family phone, tight enough that farming
  // accounts stops being effortless.
  maxPerDevice: 3,
  // A university lab or an office behind one NAT is a normal case here, so this
  // cannot be too tight. Tajik ISPs also put many subscribers behind CGNAT,
  // which is exactly why this is a backstop and not the primary defence.
  maxPerIp: 20,
  windowHours: 24,
  requireInvite: false,
};

export interface SignupContext {
  deviceId: string;
  ipHash: string | null;
  canonical: string;
}

export async function assertSignupAllowed(
  db: Database,
  ctx: SignupContext,
  limits: SignupLimits = DEFAULT_SIGNUP_LIMITS,
): Promise<void> {
  const since = new Date(Date.now() - limits.windowHours * 60 * 60 * 1000);

  const perDevice = await db
    .select({ n: count() })
    .from(signupAttempts)
    .where(
      and(
        eq(signupAttempts.deviceId, ctx.deviceId),
        eq(signupAttempts.succeeded, true),
        gt(signupAttempts.createdAt, since),
      ),
    );

  if ((perDevice[0]?.n ?? 0) >= limits.maxPerDevice) {
    throw new DomainError(
      "rate_limited",
      "too many accounts created from this device; try again tomorrow",
    );
  }

  if (ctx.ipHash) {
    const perIp = await db
      .select({ n: count() })
      .from(signupAttempts)
      .where(
        and(
          eq(signupAttempts.ipHash, ctx.ipHash),
          eq(signupAttempts.succeeded, true),
          gt(signupAttempts.createdAt, since),
        ),
      );

    if ((perIp[0]?.n ?? 0) >= limits.maxPerIp) {
      throw new DomainError(
        "rate_limited",
        "too many accounts created from this network; try again tomorrow",
      );
    }
  }
}

export async function recordSignup(
  db: Database,
  ctx: SignupContext,
  succeeded: boolean,
): Promise<void> {
  await db.insert(signupAttempts).values({
    deviceId: ctx.deviceId,
    ipHash: ctx.ipHash,
    canonical: ctx.canonical,
    succeeded,
  });
}

// ---------------------------------------------------------------------------
// Invites
// ---------------------------------------------------------------------------

/** No 0/O/1/I/L — these get read aloud and typed from a screenshot. */
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function generateInviteCode(length = 8): string {
  const bytes = randomBytes(length);
  let code = "";
  for (let i = 0; i < length; i += 1) {
    code += CODE_ALPHABET[bytes[i]! % CODE_ALPHABET.length];
  }
  return code;
}

export interface CreateInviteInput {
  createdBy?: string | undefined;
  uses?: number;
  note?: string | undefined;
  expiresAt?: Date | undefined;
}

export async function createInvite(db: Database, input: CreateInviteInput = {}): Promise<string> {
  const code = generateInviteCode();

  await db.insert(inviteCodes).values({
    code,
    createdBy: input.createdBy ?? null,
    remainingUses: input.uses ?? 1,
    note: input.note ?? null,
    expiresAt: input.expiresAt ?? null,
  });

  return code;
}

/**
 * Claim one use of a code. Decrements under a row lock and only when uses
 * remain, so a code shared in a group chat cannot be redeemed past its limit by
 * everyone tapping at once.
 */
export async function redeemInvite(db: Database, rawCode: string, userId: string): Promise<void> {
  const code = rawCode.trim().toUpperCase();

  await db.transaction(async (tx) => {
    const rows = await tx.select().from(inviteCodes).where(eq(inviteCodes.code, code)).limit(1);

    const invite = rows[0];
    if (!invite) throw new DomainError("forbidden", "that invite code is not valid");
    if (invite.expiresAt && invite.expiresAt.getTime() < Date.now()) {
      throw new DomainError("forbidden", "that invite code has expired");
    }

    const claimed = await tx
      .update(inviteCodes)
      .set({ remainingUses: invite.remainingUses - 1 })
      .where(and(eq(inviteCodes.code, code), gt(inviteCodes.remainingUses, 0)))
      .returning({ remainingUses: inviteCodes.remainingUses });

    if (!claimed[0]) throw new DomainError("forbidden", "that invite code has been used up");

    await tx.insert(inviteRedemptions).values({ code, userId });
  });
}

export async function hasRedeemedInvite(db: Database, userId: string): Promise<boolean> {
  const rows = await db
    .select({ id: inviteRedemptions.id })
    .from(inviteRedemptions)
    .where(eq(inviteRedemptions.userId, userId))
    .limit(1);
  return rows.length > 0;
}

export async function listInvitesCreatedBy(db: Database, userId: string) {
  return db
    .select()
    .from(inviteCodes)
    .where(and(eq(inviteCodes.createdBy, userId), isNotNull(inviteCodes.code)));
}
