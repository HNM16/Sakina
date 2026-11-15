import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join, normalize, resolve, sep } from "node:path";

import type { MediaKind } from "@sakina/protocol";

/**
 * Object storage for photos, videos and files.
 *
 * The one architectural decision here: **the bytes never pass through the API.**
 * The client asks for a ticket, uploads straight to storage, then sends a
 * message referencing the key. A 40MB video on a slow uplink would otherwise
 * occupy a Node request for two minutes, and media is the largest thing this
 * product will ever move.
 *
 * Two providers, for the same reason push has two: `local` needs no infra and
 * makes the whole path testable on a laptop, `s3` is what runs in production
 * against MinIO. The interface is small enough that a third (a CDN, a Tajik
 * hosting provider) is an afternoon.
 */
export interface UploadTicket {
  key: string;
  url: string;
  method: "PUT" | "POST";
  headers: Record<string, string>;
  expiresIn: number;
}

export interface StorageProvider {
  readonly name: string;
  /** Where the client should PUT the bytes. */
  createUpload(input: { key: string; mime: string; size: number }): Promise<UploadTicket>;
  /** A short-lived URL the client can GET. */
  createDownloadUrl(key: string, ttlSeconds?: number): Promise<string>;
  /** Used when a message is deleted, and by the orphan sweep. */
  remove(key: string): Promise<void>;
  close?(): Promise<void>;
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/**
 * Storage keys are opaque and unguessable.
 *
 * They are namespaced by chat so that a future "delete this chat's media" is a
 * prefix scan, and they carry a random component so that knowing a chat id does
 * not let you enumerate its photos. The original filename never appears in the
 * key — it goes in the message payload, where it is not part of a URL that gets
 * logged by every proxy in between.
 */
export function mediaKey(chatId: string, kind: MediaKind, ext: string): string {
  const clean = ext.replace(/[^a-z0-9]/gi, "").slice(0, 8).toLowerCase();
  return `chat/${chatId}/${kind}/${randomUUID()}${clean ? `.${clean}` : ""}`;
}

const KEY_SHAPE = /^chat\/[0-9a-f-]{36}\/(image|video|file)\/[0-9a-f-]{36}(\.[a-z0-9]{1,8})?$/;

/** Rejects traversal, absolute paths and anything not minted by [mediaKey]. */
export function isValidKey(key: string): boolean {
  return KEY_SHAPE.test(key);
}

// ---------------------------------------------------------------------------
// Local disk — development, tests, and a single-box deployment
// ---------------------------------------------------------------------------

/**
 * Files on disk, served back through the API with a signed token.
 *
 * The signature is what makes this a real test of the production path rather
 * than a shortcut: the client still has to request a ticket, still gets a URL
 * that expires, and still cannot read a key it was not given. Only the transport
 * differs.
 */
export class LocalStorage implements StorageProvider {
  readonly name = "local";

  constructor(
    private readonly root: string,
    private readonly publicBase: string,
    private readonly secret: string,
  ) {}

  private path(key: string): string {
    // Belt and braces: the key shape is validated, and the resolved path is
    // then confirmed to still be inside the root. Path traversal in a media
    // store is how you read /etc/passwd.
    const full = resolve(join(this.root, normalize(key)));
    const base = resolve(this.root);
    if (full !== base && !full.startsWith(base + sep)) {
      throw new Error("key escapes the storage root");
    }
    return full;
  }

  sign(key: string, expiresAt: number): string {
    return createHmac("sha256", this.secret).update(`${key}\n${expiresAt}`).digest("hex");
  }

  /** Constant-time, because this is an auth check on every media fetch. */
  verify(key: string, expiresAt: number, token: string): boolean {
    if (!Number.isFinite(expiresAt) || expiresAt * 1000 < Date.now()) return false;
    const want = Buffer.from(this.sign(key, expiresAt));
    const got = Buffer.from(token);
    return want.length === got.length && timingSafeEqual(want, got);
  }

  async createUpload(input: { key: string; mime: string }): Promise<UploadTicket> {
    const expiresIn = 900;
    const expiresAt = Math.floor(Date.now() / 1000) + expiresIn;
    const token = this.sign(input.key, expiresAt);
    const url = `${this.publicBase}/v1/media/${encodeURIComponent(input.key)}?exp=${expiresAt}&sig=${token}`;
    return {
      key: input.key,
      url,
      method: "PUT",
      headers: { "content-type": input.mime },
      expiresIn,
    };
  }

  async createDownloadUrl(key: string, ttlSeconds = 3600): Promise<string> {
    const expiresAt = Math.floor(Date.now() / 1000) + ttlSeconds;
    const token = this.sign(key, expiresAt);
    return `${this.publicBase}/v1/media/${encodeURIComponent(key)}?exp=${expiresAt}&sig=${token}`;
  }

  async put(key: string, body: Buffer): Promise<void> {
    const full = this.path(key);
    await mkdir(dirname(full), { recursive: true });
    await writeFile(full, body);
  }

  async get(key: string): Promise<Buffer> {
    return readFile(this.path(key));
  }

  async size(key: string): Promise<number> {
    return (await stat(this.path(key))).size;
  }

  async exists(key: string): Promise<boolean> {
    try {
      await stat(this.path(key));
      return true;
    } catch {
      return false;
    }
  }

  async remove(key: string): Promise<void> {
    await rm(this.path(key), { force: true });
  }
}

// ---------------------------------------------------------------------------
// S3 / MinIO
// ---------------------------------------------------------------------------

export interface S3Options {
  endpoint: string; // http://127.0.0.1:9000 in dev, https://s3.example.tj in production
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  /** MinIO serves path-style (host/bucket/key); real S3 prefers virtual-host. */
  forcePathStyle?: boolean;
}

const UNSIGNED = "UNSIGNED-PAYLOAD";

function sha256Hex(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function hmac(key: Buffer | string, value: string): Buffer {
  return createHmac("sha256", key).update(value, "utf8").digest();
}

/**
 * RFC 3986, which is stricter than encodeURIComponent: S3 wants `!*'()` encoded
 * too, and a signature that disagrees with the server by one character fails
 * with an error that says nothing useful.
 */
function uriEncode(value: string, encodeSlash: boolean): string {
  let out = "";
  for (const ch of value) {
    if (/[A-Za-z0-9\-._~]/.test(ch)) {
      out += ch;
    } else if (ch === "/") {
      out += encodeSlash ? "%2F" : "/";
    } else {
      out += [...Buffer.from(ch, "utf8")]
        .map((b) => `%${b.toString(16).toUpperCase().padStart(2, "0")}`)
        .join("");
    }
  }
  return out;
}

/**
 * SigV4 query-string presigning, by hand.
 *
 * The AWS SDK is roughly 15MB for the one function used here, and the signing
 * algorithm has not changed since 2012. Written out rather than depended on,
 * consistent with the rest of this codebase's dependency budget.
 */
export class S3Storage implements StorageProvider {
  readonly name = "s3";

  constructor(private readonly opts: S3Options) {}

  private objectUrl(key: string): { url: URL; canonicalPath: string } {
    const base = new URL(this.opts.endpoint);
    const encodedKey = uriEncode(key, false);
    if (this.opts.forcePathStyle ?? true) {
      const path = `/${this.opts.bucket}/${encodedKey}`;
      return { url: new URL(path, base), canonicalPath: path };
    }
    base.hostname = `${this.opts.bucket}.${base.hostname}`;
    const path = `/${encodedKey}`;
    return { url: new URL(path, base), canonicalPath: path };
  }

  private presign(method: "PUT" | "GET" | "DELETE", key: string, expiresIn: number): string {
    const { url, canonicalPath } = this.objectUrl(key);
    const now = new Date();
    const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
    const dateStamp = amzDate.slice(0, 8);
    const scope = `${dateStamp}/${this.opts.region}/s3/aws4_request`;

    const query: Record<string, string> = {
      "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
      "X-Amz-Credential": `${this.opts.accessKeyId}/${scope}`,
      "X-Amz-Date": amzDate,
      "X-Amz-Expires": String(expiresIn),
      "X-Amz-SignedHeaders": "host",
    };

    const canonicalQuery = Object.keys(query)
      .sort()
      .map((k) => `${uriEncode(k, true)}=${uriEncode(query[k]!, true)}`)
      .join("&");

    const host = url.port ? `${url.hostname}:${url.port}` : url.hostname;
    const canonicalRequest = [
      method,
      canonicalPath,
      canonicalQuery,
      `host:${host}\n`,
      "host",
      UNSIGNED,
    ].join("\n");

    const stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      scope,
      sha256Hex(canonicalRequest),
    ].join("\n");

    const signingKey = hmac(
      hmac(hmac(hmac(`AWS4${this.opts.secretAccessKey}`, dateStamp), this.opts.region), "s3"),
      "aws4_request",
    );
    const signature = createHmac("sha256", signingKey).update(stringToSign, "utf8").digest("hex");

    return `${url.origin}${canonicalPath}?${canonicalQuery}&X-Amz-Signature=${signature}`;
  }

  async createUpload(input: { key: string; mime: string }): Promise<UploadTicket> {
    const expiresIn = 900;
    return {
      key: input.key,
      url: this.presign("PUT", input.key, expiresIn),
      method: "PUT",
      // content-type is deliberately NOT signed. Signing it means a client that
      // sends a charset parameter the server did not expect gets an opaque 403.
      headers: { "content-type": input.mime },
      expiresIn,
    };
  }

  async createDownloadUrl(key: string, ttlSeconds = 3600): Promise<string> {
    return this.presign("GET", key, ttlSeconds);
  }

  async remove(key: string): Promise<void> {
    const res = await fetch(this.presign("DELETE", key, 300), { method: "DELETE" });
    // 404 is success for our purposes: the orphan sweep runs over keys that may
    // already be gone, and failing there would stall the whole sweep.
    if (!res.ok && res.status !== 404) {
      throw new Error(`storage delete failed: ${res.status}`);
    }
  }
}
