import type { FastifyInstance } from "fastify";
import { z } from "zod";
import {
  assertWithinLimit,
  chatsRepo,
  DomainError,
  extensionFor,
  LocalStorage,
  mediaKey,
  mediaKindFor,
  MEDIA_LIMITS,
  isValidKey,
  safeFilename,
  THUMBNAIL_LIMIT,
} from "@sakina/core";
import { UploadRequestBody } from "@sakina/protocol";
import { requireAuth, type AppContext } from "../app.js";

/**
 * Media transfer.
 *
 * Three endpoints and a deliberate asymmetry: uploading and downloading are
 * authorised here, but the bytes themselves go straight to object storage.
 * With STORAGE_PROVIDER=local "object storage" happens to be this same process,
 * which is what lets the whole path be tested with no infrastructure — but the
 * shape of the flow is identical either way, so the test exercises the real
 * sequence rather than a shortcut around it.
 */
export function registerMediaRoutes(app: FastifyInstance, ctx: AppContext): void {
  /**
   * Step 1: ask where to put it.
   *
   * Authorisation happens here, before a single byte moves. Checking after the
   * upload would mean anyone with an account could use the bucket as free
   * storage by uploading and never sending.
   */
  app.post("/media/upload", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const body = UploadRequestBody.parse(req.body);

    // Not just membership: posting rights. Someone who can read a channel must
    // not be able to upload into its bucket.
    await chatsRepo.assertCanPost(ctx.db, body.chat_id, userId);

    // The kind comes from the mime type, decided by the server. A client that
    // labels an executable as an image gets `file`, and one that sends
    // text/html gets refused outright — see packages/core/src/media.ts.
    const kind = mediaKindFor(body.mime);
    if (body.thumbnail && kind !== "image") {
      throw new DomainError("bad_request", "a thumbnail must be an image");
    }
    assertWithinLimit(kind, body.size, body.thumbnail);

    const key = mediaKey(
      body.chat_id,
      body.thumbnail ? "image" : kind,
      extensionFor(body.name, body.mime),
    );
    const ticket = await ctx.storage.createUpload({ key, mime: body.mime, size: body.size });

    return reply.status(201).send({
      key: ticket.key,
      url: ticket.url,
      method: ticket.method,
      headers: ticket.headers,
      expires_in: ticket.expiresIn,
      max_size: body.thumbnail ? THUMBNAIL_LIMIT : MEDIA_LIMITS[kind],
      // What the client should put in the message payload, so it does not have
      // to re-derive the server's classification and disagree with it.
      kind,
    });
  });

  /**
   * Step 3 (step 2 being the upload itself): get a URL to read it back.
   *
   * Membership is re-checked on every call rather than trusted from the message
   * the key arrived in. Leaving a group has to actually stop working.
   */
  app.get("/media/url", async (req, reply) => {
    const { userId } = await requireAuth(ctx, req);
    const query = z
      .object({ key: z.string().min(1), chat_id: z.string().uuid() })
      .parse(req.query);

    if (!isValidKey(query.key)) {
      throw new DomainError("bad_request", "malformed media key");
    }
    // The key embeds its chat. Without this check, a member of chat A could ask
    // for a signed URL to a key belonging to chat B.
    if (!query.key.startsWith(`chat/${query.chat_id}/`)) {
      throw new DomainError("forbidden", "that key does not belong to this chat");
    }
    if (!(await chatsRepo.isMember(ctx.db, query.chat_id, userId))) {
      throw new DomainError("forbidden", "not a member of this chat");
    }

    const url = await ctx.storage.createDownloadUrl(query.key, 3600);
    return reply.send({ key: query.key, url, expires_in: 3600 });
  });

  // -------------------------------------------------------------------------
  // The local-disk transport.
  //
  // Only mounted for STORAGE_PROVIDER=local. With s3 these paths do not exist
  // and the presigned URLs point at MinIO instead.
  // -------------------------------------------------------------------------
  const storage = ctx.storage;
  if (!(storage instanceof LocalStorage)) return;

  const SignedQuery = z.object({ exp: z.coerce.number().int(), sig: z.string().min(1) });

  // Media arrives as raw bytes, not JSON. Registered on this plugin instance
  // only, so the rest of the API keeps its strict JSON parsing and its 256KB
  // body limit — a 64MB ceiling applied globally would turn every endpoint
  // into a memory-exhaustion target.
  app.addContentTypeParser("*", { parseAs: "buffer" }, (_req, body, done) => {
    done(null, body);
  });

  app.put("/media/*", { bodyLimit: MEDIA_LIMITS.file + 4096 }, async (req, reply) => {
    const key = decodeURIComponent((req.params as Record<string, string>)["*"] ?? "");
    const { exp, sig } = SignedQuery.parse(req.query);

    // The signature IS the authorisation. There is no bearer token on this
    // request, exactly as there would not be on a presigned S3 PUT.
    if (!isValidKey(key) || !storage.verify(key, exp, sig)) {
      throw new DomainError("forbidden", "invalid or expired upload URL");
    }

    const body = req.body;
    if (!Buffer.isBuffer(body)) {
      throw new DomainError("bad_request", "expected a binary body");
    }

    const kind = key.split("/")[2] as "image" | "video" | "file";
    assertWithinLimit(kind, body.length, false);

    await storage.put(key, body);
    return reply.status(204).send();
  });

  app.get("/media/*", async (req, reply) => {
    const key = decodeURIComponent((req.params as Record<string, string>)["*"] ?? "");
    const { exp, sig } = SignedQuery.parse(req.query);

    if (!isValidKey(key) || !storage.verify(key, exp, sig)) {
      throw new DomainError("forbidden", "invalid or expired media URL");
    }
    if (!(await storage.exists(key))) {
      throw new DomainError("not_found", "media not found");
    }

    const name = z
      .object({ name: z.string().max(255).optional() })
      .parse(req.query).name;

    // attachment, always. Serving user-uploaded bytes inline is how a media
    // host becomes a phishing host — the mime allowlist in core/media.ts is the
    // first line of that defence and this is the second.
    return reply
      .header("content-type", "application/octet-stream")
      .header(
        "content-disposition",
        `attachment; filename*=UTF-8''${encodeURIComponent(safeFilename(name ?? "file"))}`,
      )
      .header("cache-control", "private, max-age=3600")
      .header("x-content-type-options", "nosniff")
      .send(await storage.get(key));
  });
}
