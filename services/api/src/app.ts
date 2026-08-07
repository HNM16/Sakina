import Fastify, {
  type FastifyError,
  type FastifyInstance,
  type FastifyRequest,
} from "fastify";
import { ZodError } from "zod";
import cors from "@fastify/cors";
import { createDb, type Database } from "@sakina/db";
import {
  createTokenSigner,
  DomainError,
  HTTP_STATUS,
  StubSmsProvider,
  type SmsProvider,
  type TokenSigner,
} from "@sakina/core";
import type { Env } from "./env.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerMeRoutes } from "./routes/me.js";
import { registerChatRoutes } from "./routes/chats.js";

export interface AppContext {
  env: Env;
  db: Database;
  signer: TokenSigner;
  sms: SmsProvider;
}

declare module "fastify" {
  interface FastifyRequest {
    userId?: string;
    deviceId?: string;
  }
}

export async function buildApp(env: Env, overrides: Partial<AppContext> = {}) {
  const { db, sql } = createDb(env.DATABASE_URL);

  const ctx: AppContext = {
    env,
    db: overrides.db ?? db,
    signer: overrides.signer ?? createTokenSigner(env.JWT_SECRET),
    sms: overrides.sms ?? new StubSmsProvider(),
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

  app.get("/health", async () => ({ ok: true, service: "api" }));

  await app.register(async (instance) => registerAuthRoutes(instance, ctx), { prefix: "/v1/auth" });
  await app.register(async (instance) => registerMeRoutes(instance, ctx), { prefix: "/v1" });
  await app.register(async (instance) => registerChatRoutes(instance, ctx), { prefix: "/v1" });

  app.addHook("onClose", async () => {
    if (!overrides.db) await sql.end();
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
