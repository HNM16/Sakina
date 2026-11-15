/**
 * Does a ban survive someone coming back with a new address?
 *
 * The scenario this exists to prove:
 *   1. someone signs up and behaves badly
 *   2. they are banned
 *   3. they delete the app, reinstall it, and register a brand-new email
 *   4. the server recognises the hardware and refuses
 *
 * Run with the API up:
 *   pnpm --filter=@sakina/api exec tsx scripts/ban-smoke.ts
 */
import { bansRepo } from "@sakina/core";
import { createDb } from "@sakina/db";
import { randomUUID } from "node:crypto";

const API = process.env.API_URL ?? "http://127.0.0.1:4000";
const DATABASE_URL = process.env.DATABASE_URL ?? "postgres://sakina@127.0.0.1:5432/sakina";
const PEPPER = process.env.OTP_PEPPER ?? "dev-only-pepper-change-me-please";

const { db, sql } = createDb(DATABASE_URL);

let failures = 0;

function check(label: string, condition: boolean, detail = ""): void {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

async function post(path: string, body: unknown) {
  const res = await fetch(`${API}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

/**
 * One sign-in. `androidId` stands in for Settings.Secure.ANDROID_ID — the value
 * that stays put across an uninstall/reinstall. `deviceId` is the per-install
 * UUID, so a fresh one models a reinstall.
 */
async function signIn(email: string, androidId: string | null) {
  const identity = { kind: "email", value: email };
  const requested = await post("/v1/auth/otp/request", { identity, locale: "tg" });
  if (requested.status !== 200) return { status: requested.status, error: requested.body?.error };

  const verified = await post("/v1/auth/otp/verify", {
    identity,
    code: requested.body.dev_code,
    device: {
      device_id: randomUUID(),
      platform: "android",
      name: "Test handset",
      ...(androidId
        ? { attestation: { source: "android_id", value: androidId } }
        : {}),
    },
  });

  if (verified.status !== 200) return { status: verified.status, error: verified.body?.error };
  return { status: 200, userId: verified.body.user.id as string };
}

const stamp = Date.now().toString().slice(-8);
// One physical phone, three different accounts attempted from it.
const handset = `ssaid-${randomUUID()}`;

console.log("\nSakina ban-evasion test\n");

console.log("setup");
const original = await signIn(`troll${stamp}@example.com`, handset);
check("account created on the handset", original.status === 200, original.error?.message);

console.log("\nban");
const banned = await bansRepo.banUserAndDevices(db, original.userId!, {
  reason: "spam (test)",
});
check("the account was banned", banned.users.includes(original.userId!));
check("the handset was banned with it", banned.devices.length === 1, `${banned.devices.length} device(s)`);

console.log("\nevasion attempts");

const sameAccount = await signIn(`troll${stamp}@example.com`, handset);
check(
  "the banned account cannot sign back in",
  sameAccount.status === 403,
  `status ${sameAccount.status}`,
);

// The actual question: brand-new email, app reinstalled (new device_id), same
// physical phone.
const newEmail = await signIn(`brandnew${stamp}@example.com`, handset);
check(
  "a NEW email on the SAME handset is refused",
  newEmail.status === 403,
  newEmail.error?.message ?? `status ${newEmail.status}`,
);

const secondNewEmail = await signIn(`another${stamp}@example.com`, handset);
check(
  "and again, with a third address",
  secondNewEmail.status === 403,
  `status ${secondNewEmail.status}`,
);

console.log("\nlimits, stated honestly");

// A factory reset issues a new SSAID. Nothing can prevent this, and pretending
// otherwise would be the wrong thing to write down.
const afterFactoryReset = await signIn(`reset${stamp}@example.com`, `ssaid-${randomUUID()}`);
check(
  "a factory reset (new SSAID) DOES get through — expected",
  afterFactoryReset.status === 200,
  "the ceiling for everyone, Snapchat included",
);

// The web client has no such identifier at all. Missing attestation must not
// block sign-in, only leave the device untracked.
const noAttestation = await signIn(`webuser${stamp}@example.com`, null);
check(
  "a client with no attestation can still sign in",
  noAttestation.status === 200,
  `status ${noAttestation.status}`,
);

console.log("\ncollateral");

const innocent = await signIn(`innocent${stamp}@example.com`, `ssaid-${randomUUID()}`);
check(
  "an unrelated device is unaffected",
  innocent.status === 200,
  `status ${innocent.status}`,
);

console.log("\nlifting");
await bansRepo.liftBans(db, "device", banned.devices[0]!, "appeal upheld (test)");
await bansRepo.liftBans(db, "user", original.userId!, "appeal upheld (test)");

const afterLift = await signIn(`troll${stamp}@example.com`, handset);
check("lifting the ban restores access", afterLift.status === 200, `status ${afterLift.status}`);

console.log(failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) FAILED.\n`);
await sql.end();
process.exit(failures === 0 ? 0 : 1);
