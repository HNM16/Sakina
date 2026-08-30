import { createHmac } from "node:crypto";
import { DomainError } from "./errors.js";

/**
 * Turning what someone typed into the thing we judge uniqueness on.
 *
 * The problem: email is a far weaker identity than a phone number. One Gmail
 * mailbox can be written an unbounded number of ways — `j.o.h.n@gmail.com`,
 * `john+beta@gmail.com`, `John@GoogleMail.com` — and every one of them reaches
 * the same inbox. Store the raw string and each variant becomes a separate
 * account for free.
 *
 * The fix is to reduce every address to one canonical form and put a unique
 * index on that. It is only worth doing per-provider, because the rules differ
 * and over-normalising is worse than under-normalising: dots are meaningless at
 * Gmail but meaningful nearly everywhere else, so stripping them globally would
 * merge two real strangers into one account and lock one of them out.
 *
 * What this does NOT solve, stated plainly so it is not mistaken for more than
 * it is: someone with a Gmail account and a Yandex account has two genuinely
 * different mailboxes, and no string handling will ever tell you they are one
 * person. That is what invite codes, per-device signup limits, and eventually
 * phone verification are for. See docs/ANTI-ABUSE.md.
 */

/** Providers where `+tag` suffixes route to the same mailbox. */
const PLUS_ADDRESSING_DOMAINS = new Set([
  "gmail.com",
  "googlemail.com",
  "outlook.com",
  "hotmail.com",
  "live.com",
  "msn.com",
  "yahoo.com",
  "proton.me",
  "protonmail.com",
  "pm.me",
  "icloud.com",
  "me.com",
  "fastmail.com",
  "zoho.com",
  "yandex.ru",
  "yandex.com",
  "ya.ru",
  "mail.ru",
  "bk.ru",
  "inbox.ru",
  "list.ru",
]);

/**
 * Domains that are the same mailbox under different names.
 *
 * Yandex and Mail.ru matter more here than they would elsewhere: across Central
 * Asia and among Tajik migrants in Russia they are far more common than Gmail,
 * and Yandex in particular serves one mailbox under half a dozen country
 * domains.
 */
const DOMAIN_ALIASES: Record<string, string> = {
  "googlemail.com": "gmail.com",
  "ya.ru": "yandex.ru",
  "yandex.com": "yandex.ru",
  "yandex.by": "yandex.ru",
  "yandex.kz": "yandex.ru",
  "yandex.ua": "yandex.ru",
  "yandex.uz": "yandex.ru",
  "yandex.com.tr": "yandex.ru",
  "pm.me": "proton.me",
  "protonmail.com": "proton.me",
  "protonmail.ch": "proton.me",
  "me.com": "icloud.com",
  "mac.com": "icloud.com",
  "hotmail.com": "outlook.com",
  "live.com": "outlook.com",
  "msn.com": "outlook.com",
};

/** Providers that ignore dots in the local part. Gmail is famously one. */
const DOT_INSENSITIVE_DOMAINS = new Set(["gmail.com"]);

/**
 * Disposable-mailbox domains. A starter list, not a solution — these services
 * add domains faster than any hard-coded list can track. Treat this as the
 * floor and put a maintained blocklist behind `DISPOSABLE_EMAIL_DOMAINS` in
 * production.
 */
const DISPOSABLE_DOMAINS = new Set([
  "mailinator.com",
  "guerrillamail.com",
  "guerrillamail.info",
  "10minutemail.com",
  "tempmail.com",
  "temp-mail.org",
  "throwawaymail.com",
  "yopmail.com",
  "trashmail.com",
  "sharklasers.com",
  "getnada.com",
  "dispostable.com",
  "maildrop.cc",
  "fakeinbox.com",
  "mailnesia.com",
  "mytemp.email",
  "moakt.com",
  "tempr.email",
  "emailondeck.com",
  "spam4.me",
  "grr.la",
  "mohmal.com",
  "burnermail.io",
  "mailsac.com",
  "inboxkitten.com",
]);

export interface EmailPolicy {
  /** Extra disposable domains, typically loaded from a maintained list. */
  extraDisposableDomains?: Set<string> | undefined;
  /** When set, ONLY these domains may register. Useful for a university pilot. */
  allowedDomains?: Set<string> | undefined;
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;

export interface CanonicalEmail {
  /** As typed, trimmed. Shown back to the user. */
  value: string;
  /** Normalised. The uniqueness key. */
  canonical: string;
  domain: string;
}

export function canonicalizeEmail(raw: string, policy: EmailPolicy = {}): CanonicalEmail {
  const value = raw.trim();

  if (!EMAIL_PATTERN.test(value)) {
    throw new DomainError("bad_request", "that does not look like an email address");
  }

  const lowered = value.toLowerCase();
  const at = lowered.lastIndexOf("@");
  let local = lowered.slice(0, at);
  let domain = lowered.slice(at + 1);

  domain = DOMAIN_ALIASES[domain] ?? domain;

  if (policy.allowedDomains && !policy.allowedDomains.has(domain)) {
    throw new DomainError("forbidden", "that email domain is not accepted right now");
  }

  if (DISPOSABLE_DOMAINS.has(domain) || policy.extraDisposableDomains?.has(domain)) {
    throw new DomainError("forbidden", "disposable email addresses are not accepted");
  }

  // Order matters: strip the tag before stripping dots, or a tag containing a
  // dot leaves debris behind.
  if (PLUS_ADDRESSING_DOMAINS.has(domain)) {
    const plus = local.indexOf("+");
    if (plus !== -1) local = local.slice(0, plus);
  }

  if (DOT_INSENSITIVE_DOMAINS.has(domain)) {
    local = local.replaceAll(".", "");
  }

  // Yandex treats '.' and '-' as the same character in the local part.
  if (domain === "yandex.ru") {
    local = local.replaceAll(".", "-");
  }

  if (local.length === 0) {
    throw new DomainError("bad_request", "that does not look like an email address");
  }

  return { value, canonical: `${local}@${domain}`, domain };
}

/** E.164, kept for when phone signup comes back at launch. */
export function canonicalizePhone(raw: string): CanonicalEmail {
  const value = raw.trim().replace(/[\s()-]/g, "");

  if (!/^\+[1-9]\d{7,14}$/.test(value)) {
    throw new DomainError("bad_request", "phone must be E.164, e.g. +992901234567");
  }

  return { value, canonical: value, domain: "" };
}

/**
 * IP addresses are hashed before storage. Signup abuse counters need to compare
 * addresses, not read them — keeping the plaintext would be collecting personal
 * data we have no use for.
 */
export function hashIp(ip: string, pepper: string): string {
  return createHmac("sha256", pepper).update(ip).digest("hex");
}
