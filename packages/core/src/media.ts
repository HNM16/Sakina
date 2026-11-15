import type { MediaKind } from "@sakina/protocol";

import { DomainError } from "./errors.js";

/**
 * What may be sent, how big, and what it counts as.
 *
 * The limits below are set against Tajik mobile data, not against what a server
 * can store. A 100MB video is technically easy and practically hostile: on a
 * metered connection it is real money, and on the uplink most users have it is
 * a four-minute upload that will not survive being backgrounded. Telegram's own
 * 2GB limit is a desktop feature that happens to exist on mobile.
 */
export const MEDIA_LIMITS: Record<MediaKind, number> = {
  image: 12 * 1024 * 1024, // 12MB — a modern phone photo, uncompressed, with room
  video: 64 * 1024 * 1024, // 64MB — about a minute at 1080p, or five at 480p
  file: 100 * 1024 * 1024, // 100MB — documents, archives, an APK
};

/** A poster frame has no business being large; this cap is what makes it a thumbnail. */
export const THUMBNAIL_LIMIT = 512 * 1024;

/**
 * Mime types we will hand out an upload ticket for.
 *
 * An allowlist rather than a blocklist. The blocklist version of this decision
 * is how you end up hosting phishing pages: someone uploads text/html, the
 * download URL renders it in a browser, and it is on your domain.
 */
const IMAGE = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/heic",
  "image/heif",
  "image/avif",
]);

const VIDEO = new Set([
  "video/mp4",
  "video/quicktime",
  "video/webm",
  "video/3gpp", // still common on the cheap Android half of this market
  "video/x-matroska",
]);

/**
 * Types that must never be served inline, whatever they claim to be.
 *
 * Anything here is refused outright rather than downgraded to `file`, because a
 * "document" that a browser will execute is not a document.
 */
const REFUSED = new Set([
  "text/html",
  "application/xhtml+xml",
  "image/svg+xml", // SVG is a script container wearing an image's clothes
  "application/x-msdownload",
  "application/x-sh",
  "text/javascript",
  "application/javascript",
]);

export function mediaKindFor(mime: string): MediaKind {
  const normalized = mime.split(";")[0]!.trim().toLowerCase();
  if (REFUSED.has(normalized)) {
    throw new DomainError("bad_request", `${normalized} cannot be sent as an attachment`);
  }
  if (IMAGE.has(normalized)) return "image";
  if (VIDEO.has(normalized)) return "video";
  return "file";
}

/**
 * The extension to store the object under.
 *
 * Taken from the filename but validated hard: it ends up in a URL path, and a
 * key like `x.php` on a misconfigured static host is somebody else's incident
 * report.
 */
export function extensionFor(name: string, mime: string): string {
  const fromName = name.includes(".") ? name.split(".").pop()! : "";
  if (/^[A-Za-z0-9]{1,8}$/.test(fromName)) return fromName.toLowerCase();

  const fallback: Record<string, string> = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
    "image/heic": "heic",
    "video/mp4": "mp4",
    "video/quicktime": "mov",
    "video/webm": "webm",
    "video/3gpp": "3gp",
  };
  return fallback[mime.split(";")[0]!.trim().toLowerCase()] ?? "bin";
}

export function assertWithinLimit(kind: MediaKind, size: number, isThumbnail: boolean): void {
  const limit = isThumbnail ? THUMBNAIL_LIMIT : MEDIA_LIMITS[kind];
  if (size > limit) {
    const mb = (limit / (1024 * 1024)).toFixed(limit < 1024 * 1024 ? 2 : 0);
    throw new DomainError(
      "bad_request",
      isThumbnail
        ? `a preview image may not exceed ${mb}MB`
        : `${kind} attachments may not exceed ${mb}MB`,
    );
  }
}

/**
 * A filename safe to put in a Content-Disposition header and to write to a
 * phone's downloads folder.
 *
 * Strips directory separators and control characters, keeps Cyrillic — a Tajik
 * or Russian filename is the normal case here, not an edge case, and mangling
 * it into transliterated ASCII is the kind of small insult that makes software
 * feel foreign.
 */
export function safeFilename(name: string): string {
  const cleaned = name
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .replace(/[/\\]/g, "_")
    .replace(/^\.+/, "")
    .trim();
  return cleaned.slice(0, 200) || "file";
}
