#!/usr/bin/env node
/**
 * The sign-in paths, and — the reason this file exists — proof that the ways
 * around SMS do not quietly become ways around having an account at all.
 *
 * Email is a far weaker identity than a phone number. One Gmail mailbox can be
 * written an unbounded number of ways, and every variant reaches the same
 * inbox. If each variant got its own account, "10,000 users" would mean
 * nothing. So the checks below are mostly about one question: does the server
 * recognise the same person?
 *
 *   node services/api/scripts/auth-smoke.mjs
 *
 * Expects the API running with:
 *   TEST_IDENTITIES="qa@sakina.tj:000000"
 */
import { randomUUID } from "node:crypto";

const API = process.env.API_URL ?? "http://127.0.0.1:4000";

let failures = 0;

function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

async function post(path, body) {
  const res = await fetch(`${API}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

function device(name = "Test device") {
  return { device_id: randomUUID(), platform: "android", name };
}

/** Full signup/sign-in round trip. Returns the user id, or the error. */
async function signIn(email, { deviceId, invite } = {}) {
  const identity = { kind: "email", value: email };
  const requested = await post("/v1/auth/otp/request", { identity, locale: "tg" });
  if (requested.status !== 200) return { error: requested.body?.error, status: requested.status };

  const code = requested.body.dev_code;
  const verified = await post("/v1/auth/otp/verify", {
    identity,
    code,
    device: deviceId ? { ...device(), device_id: deviceId } : device(),
    ...(invite ? { invite_code: invite } : {}),
  });

  if (verified.status !== 200) return { error: verified.body?.error, status: verified.status };
  return {
    userId: verified.body.user.id,
    isNew: verified.body.is_new_user,
    tokens: verified.body.tokens,
  };
}

const health = await (await fetch(`${API}/health`)).json();
console.log(`\nSakina auth smoke test`);
console.log(
  `  email=${health.email_provider}  dev_mode=${health.otp_dev_mode}  invite_only=${health.invite_only}\n`,
);

// --- the core requirement -------------------------------------------------
console.log("one person, one account");

const stamp = Date.now().toString().slice(-8);
const base = `nekruztest${stamp}`;
// A realistic dotted variant. Note: consecutive dots are not a valid address at
// all, so the interesting case is single dots in plausible places.
const dottedVariant = `ne.kruz.test${stamp}`;

const first = await signIn(`${base}@gmail.com`);
check("a new address creates an account", first.isNew === true, first.error?.message);

// Gmail ignores dots entirely. Without canonicalisation this is a free
// second account.
const dotted = await signIn(`${dottedVariant}@gmail.com`);
check(
  "Gmail dot variants resolve to the SAME account",
  dotted.userId === first.userId && dotted.isNew === false,
  dotted.userId === first.userId ? "" : "created a duplicate",
);

const plusTagged = await signIn(`${base}+sakina@gmail.com`);
check(
  "plus-tagged addresses resolve to the SAME account",
  plusTagged.userId === first.userId && plusTagged.isNew === false,
);

const googlemail = await signIn(`${base}@googlemail.com`);
check(
  "googlemail.com resolves to the SAME account as gmail.com",
  googlemail.userId === first.userId && googlemail.isNew === false,
);

const shouty = await signIn(`${base.toUpperCase()}@GMAIL.COM`);
check("case is ignored", shouty.userId === first.userId && shouty.isNew === false);

const combined = await signIn(`${dottedVariant.toUpperCase()}+beta@GoogleMail.com`);
check(
  "all tricks combined still resolve to the SAME account",
  combined.userId === first.userId && combined.isNew === false,
);

// Yandex and Mail.ru matter more than Gmail for this audience.
const yandexBase = `farrukh.test${stamp}`;
const yandex = await signIn(`${yandexBase}@yandex.ru`);
const yandexAlias = await signIn(`${yandexBase.replace(".", "-")}+tag@ya.ru`);
check(
  "ya.ru and yandex.ru with dot/hyphen swap are the SAME account",
  yandexAlias.userId === yandex.userId && yandexAlias.isNew === false,
);

// --- and it must not over-merge -------------------------------------------
console.log("\ndistinct people stay distinct");

const other = await signIn(`someone.else${stamp}@gmail.com`);
check("a genuinely different address gets its own account", other.userId !== first.userId);

// Dots are meaningless at Gmail but MEANINGFUL almost everywhere else.
// Stripping them globally would merge two strangers and lock one out.
const corpA = await signIn(`a.b${stamp}@example.com`);
const corpB = await signIn(`ab${stamp}@example.com`);
check(
  "dots are NOT stripped on non-Gmail domains",
  // Both must exist AND differ. Without the first clause, two signups blocked
  // by a rate limit would both be `undefined` and read as a pass.
  !!corpA.userId && !!corpB.userId && corpA.userId !== corpB.userId,
  !corpA.userId || !corpB.userId
    ? `signup blocked (${corpA.error?.code ?? corpA.status}/${corpB.error?.code ?? corpB.status})`
    : corpA.userId === corpB.userId
      ? "merged two different people"
      : "",
);

// --- disposable addresses -------------------------------------------------
console.log("\nthrowaway addresses");

const disposable = await signIn(`whoever${stamp}@mailinator.com`);
check(
  "known disposable domains are refused",
  disposable.status === 403,
  disposable.error?.message ?? `status ${disposable.status}`,
);

// --- reserved test identities ---------------------------------------------
console.log("\nreserved test identity (App Store review, and building abroad)");

const reserved = await post("/v1/auth/otp/verify", {
  identity: { kind: "email", value: "qa@sakina.tj" },
  code: "000000",
  device: device("Reviewer"),
});
check(
  "reserved identity + correct code signs in with nothing sent",
  reserved.status === 200,
  `status ${reserved.status}`,
);

const reservedWrong = await post("/v1/auth/otp/verify", {
  identity: { kind: "email", value: "qa@sakina.tj" },
  code: "999999",
  device: device("Reviewer"),
});
check(
  "reserved identity + WRONG code is refused",
  reservedWrong.status === 401,
  `status ${reservedWrong.status}`,
);

const guessing = await post("/v1/auth/otp/verify", {
  identity: { kind: "email", value: `stranger${stamp}@gmail.com` },
  code: "000000",
  device: device("Attacker"),
});
check(
  "a reserved code does NOT work on any other address",
  guessing.status === 401,
  `status ${guessing.status}`,
);

// --- per-device signup ceiling --------------------------------------------
console.log("\ncost per account");

const sharedDevice = randomUUID();
const results = [];
for (let i = 0; i < 5; i += 1) {
  results.push(await signIn(`farm${stamp}n${i}@gmail.com`, { deviceId: sharedDevice }));
}
const created = results.filter((r) => r.isNew).length;
const blocked = results.filter((r) => r.status === 429).length;
check(
  "one device cannot farm unlimited accounts",
  // Must have created some and then been stopped — "0 created, 5 blocked" would
  // mean a different limit fired first and this one was never exercised.
  created > 0 && created <= 3 && blocked > 0,
  `${created} created, ${blocked} blocked`,
);

console.log(failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) FAILED.\n`);
process.exit(failures === 0 ? 0 : 1);
