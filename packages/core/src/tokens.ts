import { SignJWT, jwtVerify } from "jose";
import { createHash, randomBytes } from "node:crypto";

/**
 * Access tokens are short-lived JWTs; refresh tokens are opaque random strings
 * stored only as SHA-256 hashes. A database leak must not hand an attacker a
 * working session.
 */

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const REFRESH_TOKEN_TTL_DAYS = 90;

export interface AccessClaims {
  /** user id */
  sub: string;
  /** device id — every token is bound to one device so sessions revoke individually */
  did: string;
}

export function createTokenSigner(secret: string) {
  const key = new TextEncoder().encode(secret);

  return {
    async signAccessToken(claims: AccessClaims): Promise<string> {
      return new SignJWT({ did: claims.did })
        .setProtectedHeader({ alg: "HS256" })
        .setSubject(claims.sub)
        .setIssuedAt()
        .setIssuer("sakina")
        .setAudience("sakina-client")
        .setExpirationTime(`${ACCESS_TOKEN_TTL_SECONDS}s`)
        .sign(key);
    },

    async verifyAccessToken(token: string): Promise<AccessClaims | null> {
      try {
        const { payload } = await jwtVerify(token, key, {
          issuer: "sakina",
          audience: "sakina-client",
        });
        if (typeof payload.sub !== "string" || typeof payload.did !== "string") return null;
        return { sub: payload.sub, did: payload.did };
      } catch {
        return null;
      }
    },
  };
}

export type TokenSigner = ReturnType<typeof createTokenSigner>;

export function generateRefreshToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function refreshTokenExpiry(now: Date = new Date()): Date {
  return new Date(now.getTime() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
}
