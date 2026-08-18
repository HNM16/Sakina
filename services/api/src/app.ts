import Fastify, {
  type FastifyError,
  type FastifyInstance,
  type FastifyRequest,
} from "fastify";
import { ZodError } from "zod";
import cors from "@fastify/cors";
import { createDb, type Database } from "@sakina/db";
import {
  ConsoleEmailProvider,
  createTokenSigner,
  DomainError,
  HttpEmailProvider,
  LocalStorage,
  S3Storage,
  HttpSmsProvider,
  HTTP_STATUS,
  parseTestIdentities,
  ResendEmailProvider,
  signupRepo,
  StubSmsProvider,
  TelegramGatewaySmsProvider,
  type EmailProvider,
  type SmsProvider,
  type StorageProvider,
  type TokenSigner,
} from "@sakina/core";
import { Redis } from "ioredis";
import type { Env } from "./env.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerMeRoutes } from "./routes/me.js";
import { registerChatRoutes } from "./routes/chats.js";
import { registerDeviceRoutes } from "./routes/devices.js";
import { registerMediaRoutes } from "./routes/media.js";

export interface AppContext {
  env: Env;
  db: Database;
  signer: TokenSigner;
  sms: SmsProvider;
  email: EmailProvider;
  storage: StorageProvider;
  /** Publish-only. See packages/core/src/fanout.ts. */
  redis: Redis;
  /** Reserved identity/code pairs that skip delivery. Empty unless configured. */
  testIdentities: Map<string, string>;
  disposableDomains: Set<string> | undefined;
  allowedEmailDomains: Set<string> | undefined;
  signupLimits: signupRepo.SignupLimits;
}

function parseDomains(raw: string): Set<string> | undefined {
  const domains = raw
    .split(",")
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean);
  return domains.length > 0 ? new Set(domains) : undefined;
}

function buildStorageProvider(env: Env): StorageProvider {
  if (env.STORAGE_PROVIDER === "s3") {
    if (!env.S3_ACCESS_KEY_ID || !env.S3_SECRET_ACCESS_KEY) {
      throw new Error("S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY are required when STORAGE_PROVIDER=s3");
    }
    return new S3Storage({
      endpoint: env.S3_ENDPOINT,
      region: env.S3_REGION,
      bucket: env.S3_BUCKET,
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
      forcePathStyle: env.S3_FORCE_PATH_STYLE,
    });
  }
  // The signing secret is JWT_SECRET rather than its own: a separate secret
  // that nobody remembers to set in production is worse than a shared one that
  // is already required to be strong.
  return new LocalStorage(env.STORAGE_LOCAL_DIR, env.STORAGE_PUBLIC_BASE, env.JWT_SECRET);
}

function buildEmailProvider(env: Env): EmailProvider {
  switch (env.EMAIL_PROVIDER) {
    case "resend":
      return new ResendEmailProvider({ apiKey: env.RESEND_API_KEY!, from: env.EMAIL_FROM });
    case "http":
      return new HttpEmailProvider({
        url: env.EMAIL_HTTP_URL!,
        authorization: env.EMAIL_HTTP_AUTHORIZATION,
        from: env.EMAIL_FROM,
      });
    case "console":
      return new ConsoleEmailProvider();
  }
}

function buildSmsProvider(env: Env): SmsProvider {
  switch (env.SMS_PROVIDER) {
    case "telegram":
      return new TelegramGatewaySmsProvider({
        token: env.TELEGRAM_GATEWAY_TOKEN!,
        senderUsername: env.TELEGRAM_GATEWAY_SENDER,
      });
    case "http":
      return new HttpSmsProvider({
        url: env.SMS_HTTP_URL!,
        authorization: env.SMS_HTTP_AUTHORIZATION,
        senderId: env.SMS_HTTP_SENDER_ID,
      });
    case "stub":
      return new StubSmsProvider();
  }
}

declare module "fastify" {
  interface FastifyRequest {
    userId?: string;
    deviceId?: string;
  }
}

export async function buildApp(env: Env, overrides: Partial<AppContext> = {}) {
  const { db, sql } = createDb(env.DATABASE_URL);

  const testIdentities = overrides.testIdentities ?? parseTestIdentities(env.TEST_IDENTITIES);

  const ctx: AppContext = {
    env,
    db: overrides.db ?? db,
    signer: overrides.signer ?? createTokenSigner(env.JWT_SECRET),
    sms: overrides.sms ?? buildSmsProvider(env),
    email: overrides.email ?? buildEmailProvider(env),
    storage: overrides.storage ?? buildStorageProvider(env),
    redis: overrides.redis ?? new Redis(env.REDIS_URL, { maxRetriesPerRequest: null }),
    testIdentities,
    disposableDomains: overrides.disposableDomains ?? parseDomains(env.DISPOSABLE_EMAIL_DOMAINS),
    allowedEmailDomains: overrides.allowedEmailDomains ?? parseDomains(env.ALLOWED_EMAIL_DOMAINS),
    signupLimits: overrides.signupLimits ?? {
      maxPerDevice: env.MAX_SIGNUPS_PER_DEVICE,
      maxPerIp: env.MAX_SIGNUPS_PER_IP,
      windowHours: env.SIGNUP_WINDOW_HOURS,
      requireInvite: env.REQUIRE_INVITE,
    },
  };

  const app: FastifyInstance = Fastify({
    logger: { level: env.NODE_ENV === "production" ? "info" : "debug" },
    // Tight, because the write path is the socket, not HTTP. Media uploads go
    // straight to object storage with a presigned URL and never touch this.
    bodyLimit: 256 * 1024,
  });

  await app.register(cors, { origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN.split(",") });

  app.setErrorHandler((err: unknown, _req, reply) => {
    if (err instanceof DomainError) {
      return reply.status(HTTP_STATUS[err.code]).send({
        error: { code: err.code, message: err.message },
      });
    }
    // Routes validate with zod's `.parse()`, so a malformed body surfaces here
    // as a ZodError. Without this branch it would be reported as a 500.
    if (err instanceof ZodError) {
      const detail = err.issues
        .map((issue) => `${issue.path.join(".") || "body"}: ${issue.message}`)
        .join("; ");
      return reply.status(400).send({ error: { code: "bad_request", message: detail } });
    }
    if ((err as FastifyError).validation) {
      return reply
        .status(400)
        .send({ error: { code: "bad_request", message: (err as FastifyError).message } });
    }
    app.log.error(err);
    return reply.status(500).send({ error: { code: "internal", message: "internal error" } });
  });

  // Reserved numbers bypass verification, so their existence is logged loudly
  // rather than left to be discovered in a config file.
  if (testIdentities.size > 0) {
    app.log.warn(
      { count: testIdentities.size, identities: [...testIdentities.keys()] },
      "reserved test identities are active and bypass code delivery",
    );
  }

  app.get("/health", async () => ({
    ok: true,
    service: "api",
    email_provider: ctx.email.name,
    sms_provider: ctx.sms.name,
    otp_dev_mode: env.OTP_DEV_MODE,
    invite_only: ctx.signupLimits.requireInvite,
  }));

  await app.register(async (instance) => registerAuthRoutes(instance, ctx), { prefix: "/v1/auth" });
  await app.register(async (instance) => registerMeRoutes(instance, ctx), { prefix: "/v1" });
  await app.register(async (instance) => registerChatRoutes(instance, ctx), { prefix: "/v1" });
  await app.register(async (instance) => registerDeviceRoutes(instance, ctx), { prefix: "/v1" });
  await app.register(async (instance) => registerMediaRoutes(instance, ctx), { prefix: "/v1" });

  app.addHook("onClose", async () => {
    if (!overrides.db) await sql.end();
    if (!overrides.redis) await ctx.redis.quit().catch(() => {});
  });

  return app;
}

/**
 * Attaches the caller's identity to the request, or throws. Every token is
 * bound to a device, so downstream code always knows which install it is
 * talking to — that is what makes per-device revocation possible.
 */
export async function requireAuth(ctx: AppContext, req: FastifyRequest): Promise<{
  userId: string;
  deviceId: string;
}> {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    throw new DomainError("unauthorized", "missing bearer token");
  }

  const claims = await ctx.signer.verifyAccessToken(header.slice("Bearer ".length));
  if (!claims) throw new DomainError("unauthorized", "invalid or expired token");

  req.userId = claims.sub;
  req.deviceId = claims.did;
  return { userId: claims.sub, deviceId: claims.did };
}
