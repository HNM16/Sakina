# Sakina

A messenger for Tajikistan, built so it can become a super-app without being
rebuilt.

Telegram-shaped to begin with — fast, reliable on a bad connection, Tajik first.
Structured from the first commit so that payments, utility bills and mini-apps
arrive as message types on the same bus rather than as a second product bolted
alongside.

## Running it

Requires Node 22+, pnpm 10+, and Docker.

```bash
pnpm install
pnpm infra:up          # postgres + redis + minio
pnpm build
pnpm db:migrate
pnpm dev               # api on :4000, gateway on :4001
```

Verify the whole thing works:

```bash
node services/gateway/scripts/e2e-smoke.mjs   # messaging: 24 checks
node services/api/scripts/auth-smoke.mjs      # sign-in and duplicate accounts: 15 checks
```

The first registers two users, opens a chat, exchanges a Tajik-language message,
and then checks the cases that actually matter on Tajik mobile data: a retried
send whose ack was lost, and a client coming back after being offline. The second
checks that the ways around SMS did not become ways around having an account.

## Signing in without a Tajik SIM

Sign-in is by **email** for now — +992 SMS cannot be received from outside the
country. Phone is still in the model and comes back at launch.

Locally, `OTP_DEV_MODE=true` returns the verification code in the response, so
nothing needs configuring. For anything shared, set `TEST_IDENTITIES` — fixed
identity/code pairs that skip delivery in every environment. Those are also what
App Store and Play reviewers use, since they cannot receive a Tajik SMS either.

Email being a weak identity is a real problem, not a footnote: one Gmail mailbox
can be written a dozen ways and each one would otherwise be a free extra account.
Addresses are canonicalised per provider, disposable domains are refused, signups
are capped per device and per network, and the beta can run invite-only.
See [`docs/ANTI-ABUSE.md`](docs/ANTI-ABUSE.md).

The mobile app needs a one-time setup — see [`apps/mobile/README.md`](apps/mobile/README.md).

## Layout

```
apps/mobile      Flutter client — the product
apps/web         Next.js — web client and landing
services/api     Fastify: auth, chats, history
services/gateway WebSocket: realtime delivery
packages/protocol  The wire contract (zod schemas + types)
packages/core      Domain logic and repositories
packages/db        Drizzle schema and migrations
infra            Postgres, Redis, MinIO, coturn
```

## Design

Read them in this order:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the decisions that are
  expensive to reverse, and why
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — the wire contract, authoritative for
  both TypeScript and Dart
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — what is built, what is next, and what is
  deliberately deferred
- [`docs/COMPETITIVE-ANALYSIS.md`](docs/COMPETITIVE-ANALYSIS.md) — seven
  messengers, what to take from each, and three market findings that change the
  plan
- [`docs/GROWTH.md`](docs/GROWTH.md) — the plan to 10,000 users
- [`docs/UX.md`](docs/UX.md) — Telegram-shaped, checked against Nielsen's heuristics
- [`docs/ANTI-ABUSE.md`](docs/ANTI-ABUSE.md) — one person, one account

The short version: the network is the enemy, so the client's local database is
what the UI reads from and every write is idempotent. Money will be handled by a
licensed partner for years, so the ledger schema exists now and stays empty. A
super-app is a chat app with extensible message types, so the message type enum
and `users.kind` are open from the first commit.

## Status

M0 is complete and verified: two people can exchange messages, and it holds up
across retries, reconnects and restarts. Sign-in works from anywhere via email,
with duplicate-account detection. The Flutter client is written but has not been
compiled — see its README.

The nearest thing to a deadline: WhatsApp — the most-used messenger in
Tajikistan — has been blocked in Russia since February 2026, where a large share
of the country's families have someone working. That conversation is broken right
now. See [`docs/COMPETITIVE-ANALYSIS.md`](docs/COMPETITIVE-ANALYSIS.md).
