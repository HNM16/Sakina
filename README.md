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
node services/gateway/scripts/e2e-smoke.mjs
```

That registers two users, opens a chat, exchanges a Tajik-language message, and
then checks the cases that actually matter on Tajik mobile data: a retried send
whose ack was lost, and a client coming back after being offline.

The mobile app needs a one-time setup — see [`apps/mobile/README.md`](apps/mobile/README.md).

While `OTP_DEV_MODE=true`, the API returns the verification code in the response
instead of sending an SMS, so you can sign in without an SMS provider. The API
refuses to start with it enabled when `NODE_ENV=production`.

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

Three documents, in the order worth reading them:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the decisions that are
  expensive to reverse, and why
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — the wire contract, authoritative for
  both TypeScript and Dart
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — what is built, what is next, and what is
  deliberately deferred

The short version: the network is the enemy, so the client's local database is
what the UI reads from and every write is idempotent. Money will be handled by a
licensed partner for years, so the ledger schema exists now and stays empty. A
super-app is a chat app with extensible message types, so the message type enum
and `users.kind` are open from the first commit.

## Status

M0 is complete and verified: two people can exchange messages, and it holds up
across retries, reconnects and restarts. The Flutter client is written but has
not been compiled — see its README.
