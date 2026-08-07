import { and, eq, gt, isNull } from "drizzle-orm";
import type { Database } from "@sakina/db";
import { sessions } from "@sakina/db";
import { DomainError } from "../errors.js";
import { generateRefreshToken, hashToken, refreshTokenExpiry } from "../tokens.js";

export async function createSession(
  db: Database,
  userId: string,
  deviceId: string,
): Promise<string> {
  const refreshToken = generateRefreshToken();

  await db.insert(sessions).values({
    userId,
    deviceId,
    refreshTokenHash: hashToken(refreshToken),
    expiresAt: refreshTokenExpiry(),
  });

  return refreshToken;
}

/**
 * Refresh tokens rotate on every use: the presented token is revoked and a new
 * one issued. If a stolen token is replayed after the legitimate client has
 * already rotated, the lookup fails and the theft surfaces instead of granting
 * an indefinitely renewable session.
 */
export async function rotateSession(
  db: Database,
  refreshToken: string,
): Promise<{ userId: string; deviceId: string; refreshToken: string }> {
  const hash = hashToken(refreshToken);

  const rows = await db
    .select()
    .from(sessions)
    .where(
      and(
        eq(sessions.refreshTokenHash, hash),
        isNull(sessions.revokedAt),
        gt(sessions.expiresAt, new Date()),
      ),
    )
    .limit(1);

  const session = rows[0];
  if (!session) throw new DomainError("unauthorized", "invalid or expired refresh token");

  const next = generateRefreshToken();

  await db.transaction(async (tx) => {
    await tx.update(sessions).set({ revokedAt: new Date() }).where(eq(sessions.id, session.id));
    await tx.insert(sessions).values({
      userId: session.userId,
      deviceId: session.deviceId,
      refreshTokenHash: hashToken(next),
      expiresAt: refreshTokenExpiry(),
    });
  });

  return { userId: session.userId, deviceId: session.deviceId, refreshToken: next };
}

export async function revokeDeviceSessions(db: Database, deviceId: string): Promise<void> {
  await db
    .update(sessions)
    .set({ revokedAt: new Date() })
    .where(and(eq(sessions.deviceId, deviceId), isNull(sessions.revokedAt)));
}
