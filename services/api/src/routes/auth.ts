import type { FastifyInstance } from "fastify";
import {
  ACCESS_TOKEN_TTL_SECONDS,
  DomainError,
  issueOtp,
  sessionsRepo,
  usersRepo,
  verifyOtp,
} from "@sakina/core";
import { OtpRequestBody, OtpVerifyBody, RefreshBody } from "@sakina/protocol";
import type { AppContext } from "../app.js";

export function registerAuthRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post("/otp/request", async (req, reply) => {
    const body = OtpRequestBody.parse(req.body);
    const { code } = await issueOtp(ctx.db, body.phone, ctx.env.OTP_PEPPER);

    await ctx.sms.sendOtp(body.phone, code);

    return reply.send({
      expires_in: 300,
      // Present only with the stub provider. loadEnv() refuses to start in
      // production with OTP_DEV_MODE on.
      ...(ctx.env.OTP_DEV_MODE ? { dev_code: code } : {}),
    });
  });

  app.post("/otp/verify", async (req, reply) => {
    const body = OtpVerifyBody.parse(req.body);

    await verifyOtp(ctx.db, body.phone, body.code, ctx.env.OTP_PEPPER);

    const user = await usersRepo.findOrCreateByPhone(ctx.db, body.phone);
    await usersRepo.upsertDevice(ctx.db, {
      deviceId: body.device.device_id,
      userId: user.id,
      platform: body.device.platform,
      name: body.device.name,
      pushToken: body.device.push_token,
    });

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
}
