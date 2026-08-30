import type { FastifyInstance, FastifyRequest } from "fastify";
import {
  ACCESS_TOKEN_TTL_SECONDS,
  canonicalizeEmail,
  canonicalizePhone,
  DomainError,
  hashIp,
  issueOtp,
  bansRepo,
  sessionsRepo,
  signupRepo,
  usersRepo,
  verifyOtp,
  type IdentityKind,
} from "@sakina/core";
import { OtpRequestBody, OtpVerifyBody, RefreshBody, type IdentityInput } from "@sakina/protocol";
import { requireAuth, type AppContext } from "../app.js";

/**
 * Codes issued in this process, newest last, for the dev inbox below.
 * In-memory and capped — it must never become a durable record of live codes.
 */
const devInbox: Array<{ identity: string; code: string; issued_at: number }> = [];
const DEV_INBOX_LIMIT = 20;

function canonicalize(ctx: AppContext, identity: IdentityInput) {
  return identity.kind === "email"
    ? canonicalizeEmail(identity.value, {
        extraDisposableDomains: ctx.disposableDomains,
        allowedDomains: ctx.allowedEmailDomains,
      })
    : canonicalizePhone(identity.value);
}

function clientIpHash(ctx: AppContext, req: FastifyRequest): string | null {
  const ip = req.ip;
  return ip ? hashIp(ip, ctx.env.OTP_PEPPER) : null;
}

/** A brand-new account is named after the local part, not the whole address. */
function placeholderName(kind: IdentityKind, value: string): string {
  if (kind === "phone") return value;
  const local = value.slice(0, value.lastIndexOf("@"));
  return local.length > 0 ? local : value;
}

export function registerAuthRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post("/otp/request", async (req, reply) => {
    const body = OtpRequestBody.parse(req.body);
    const { kind, value } = body.identity;
    const { canonical } = canonicalize(ctx, body.identity);

    const { code, isTestIdentity } = await issueOtp(ctx.db, kind, canonical, ctx.env.OTP_PEPPER, {
      testIdentities: ctx.testIdentities,
      resendCooldownSeconds: ctx.env.OTP_RESEND_COOLDOWN_SECONDS,
    });

    // A reserved identity has a fixed code the caller already knows; delivering
    // it would be a wasted message to an address that may not exist.
    if (!isTestIdentity) {
      try {
        if (kind === "email") {
          await ctx.email.sendOtp(value, code, body.locale);
        } else {
          await ctx.sms.sendOtp(value, code);
        }
      } catch (err) {
        req.log.error({ err, kind }, "otp delivery failed");
        if (!ctx.env.OTP_DEV_MODE) {
          throw new DomainError("internal", "could not deliver verification code");
        }
      }
    }

    if (ctx.env.OTP_DEV_MODE) {
      devInbox.push({ identity: canonical, code, issued_at: Date.now() });
      if (devInbox.length > DEV_INBOX_LIMIT) devInbox.shift();
    }

    // Deliberately the same response whether or not the address is registered:
    // this endpoint must not become a way to enumerate who has an account.
    return reply.send({
      expires_in: 600,
      ...(ctx.env.OTP_DEV_MODE ? { dev_code: code } : {}),
    });
  });

  /**
   * Reads back recently issued codes. Exists for the case the response body
   * cannot cover: testing on a real handset, where the app consumes the JSON
   * and you never see it. Registered only when OTP_DEV_MODE is on, and that
   * cannot be on in production — so in production this route does not exist at
   * all, rather than existing and being guarded.
   */
  if (ctx.env.OTP_DEV_MODE) {
    app.get("/dev/inbox", async (_req, reply) => reply.send({ codes: [...devInbox].reverse() }));
  }

  app.post("/otp/verify", async (req, reply) => {
    const body = OtpVerifyBody.parse(req.body);
    const { kind, value } = body.identity;
    const { canonical } = canonicalize(ctx, body.identity);

    await verifyOtp(ctx.db, kind, canonical, body.code, ctx.env.OTP_PEPPER, {
      testIdentities: ctx.testIdentities,
    });

    const signupCtx = {
      deviceId: body.device.device_id,
      ipHash: clientIpHash(ctx, req),
      canonical,
    };

    const known = await usersRepo.findByIdentity(ctx.db, kind, canonical);

    // Bans are checked before anything else, and the device is checked before
    // the account — the whole point is the case where the address is brand new
    // and only the hardware is recognised.
    await bansRepo.assertNotBanned(ctx.db, {
      userId: known?.id,
      platform: body.device.platform,
      fingerprint: body.device.attestation?.value,
      pepper: ctx.env.OTP_PEPPER,
    });

    // Only a signup is rate-limited. Someone signing back in on a new handset,
    // or a family sharing one, must not be blocked by a limit meant for account
    // farming — so the check happens after we know whether this address is new.
    if (!known) {
      await signupRepo.assertSignupAllowed(ctx.db, signupCtx, ctx.signupLimits);
    }

    const { user, isNewUser } = await usersRepo.resolveIdentity(ctx.db, {
      kind,
      value,
      canonical,
      displayName: placeholderName(kind, value),
    });

    if (isNewUser) {
      if (ctx.signupLimits.requireInvite) {
        if (!body.invite_code) {
          throw new DomainError("forbidden", "Sakina is invite-only right now");
        }
        await signupRepo.redeemInvite(ctx.db, body.invite_code, user.id);
      }
      await signupRepo.recordSignup(ctx.db, signupCtx, true);
    }

    await usersRepo.upsertDevice(ctx.db, {
      deviceId: body.device.device_id,
      userId: user.id,
      platform: body.device.platform,
      name: body.device.name,
      pushToken: body.device.push_token,
    });

    // Recorded after the account resolves, so the (device, account) edge exists
    // for ban propagation later. A device with no attestation simply has no
    // edge — it is not a reason to refuse the sign-in.
    if (body.device.attestation) {
      await bansRepo.recordFingerprint(
        ctx.db,
        {
          platform: body.device.platform,
          value: body.device.attestation.value,
          source: body.device.attestation.source,
          attested: body.device.attestation.integrity_token !== undefined,
        },
        user.id,
        ctx.env.OTP_PEPPER,
      );
    }

    const refreshToken = await sessionsRepo.createSession(ctx.db, user.id, body.device.device_id);
    const accessToken = await ctx.signer.signAccessToken({
      sub: user.id,
      did: body.device.device_id,
    });

    return reply.send({
      user: usersRepo.toPublicUser(user),
      tokens: {
        access_token: accessToken,
        refresh_token: refreshToken,
        expires_in: ACCESS_TOKEN_TTL_SECONDS,
      },
      is_new_user: isNewUser,
    });
  });

  app.post("/refresh", async (req, reply) => {
    const body = RefreshBody.parse(req.body);
    const rotated = await sessionsRepo.rotateSession(ctx.db, body.refresh_token);

    const accessToken = await ctx.signer.signAccessToken({
      sub: rotated.userId,
      did: rotated.deviceId,
    });

    return reply.send({
      access_token: accessToken,
      refresh_token: rotated.refreshToken,
      expires_in: ACCESS_TOKEN_TTL_SECONDS,
    });
  });

  app.post("/logout", async (req, reply) => {
    const body = RefreshBody.safeParse(req.body);
    if (!body.success) throw new DomainError("bad_request", "refresh_token required");

    const rotated = await sessionsRepo.rotateSession(ctx.db, body.data.refresh_token);
    await sessionsRepo.revokeDeviceSessions(ctx.db, rotated.deviceId);

    return reply.status(204).send();
  });

  /**
   * Every member can hand out a few invites. That is the growth loop and the
   * abuse limit at the same time: joining requires someone already inside to
   * spend one of theirs.
   */
  app.post("/invites", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);

    const existing = await signupRepo.listInvitesCreatedBy(ctx.db, userId);
    const unused = existing.filter((invite) => invite.remainingUses > 0).length;

    if (unused >= ctx.env.INVITES_PER_USER) {
      throw new DomainError(
        "rate_limited",
        `you can have ${ctx.env.INVITES_PER_USER} unused invites at a time`,
      );
    }

    const code = await signupRepo.createInvite(ctx.db, { createdBy: userId, uses: 1 });
    return reply.status(201).send({ code, remaining_uses: 1 });
  });

  app.get("/invites", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const invites = await signupRepo.listInvitesCreatedBy(ctx.db, userId);

    return reply.send({
      invites: invites.map((invite) => ({
        code: invite.code,
        remaining_uses: invite.remainingUses,
        note: invite.note,
        created_at: invite.createdAt.getTime(),
      })),
    });
  });
}
