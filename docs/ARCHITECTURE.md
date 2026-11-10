# Architecture

Sakina is a messenger for Tajikistan, built so that it can become a super-app
without being rebuilt. This document records the decisions that are expensive to
reverse and the reasoning behind them.

## Three constraints

Everything below follows from these. A design choice that violates one of them
is wrong regardless of how clean it looks.

**1. The network is the enemy.** Outside Dushanbe, users are on patchy 3G/4G,
expensive per-MB data, and periodic throttling. This is why there is one
persistent socket rather than chatty REST, why the client's SQLite database — not
the server — is what the UI reads from, and why every write is idempotent so a
retry over a dying link is free. This is not a later optimisation; it is the
architecture. Telegram's hold on the region was won largely on working when the
connection did not.

**2. Sakina will not hold money for a long time.** Licensing as an e-money or
payment institution with the National Bank of Tajikistan is a multi-year,
capital-gated process. Until then the product is a user-experience layer over a
licensed partner, and a partner bank is the ledger of record. The ledger schema
still exists today (see below), because the schema is the part that cannot be
retrofitted.

**3. The super-app is a chat app with extensible message types.** WeChat is not
"chat plus payments." It is a message bus on which a payment, a utility bill, a
receipt and a mini-app card are all message types, and merchants are users with a
webhook. Those hooks are reserved on day one because they cost nothing now and
are brutal later.

## Shape

```
apps/
  mobile/     Flutter — the product
  web/        Next.js — web client and landing
services/
  api/        Fastify: auth bootstrap, chat CRUD, history backfill
  gateway/    WebSocket: realtime delivery, presence, fan-out
packages/
  protocol/   Wire types and zod schemas — the contract
  core/       Domain logic and repositories, shared by both services
  db/         Drizzle schema and migrations
infra/        Postgres, Redis, MinIO, coturn
```

`api` and `gateway` are separate processes sharing `core` and `db`. The split is
deliberate: the gateway is connection-heavy and memory-bound in a way the CRUD
API is not, and separating them now means it can be rewritten in Go later
without a single client-side change.

### Why Node and TypeScript

One language across protocol, services and web; the `packages/protocol` schemas
are imported directly by both services rather than reimplemented. Go would handle
the socket layer better and probably will, eventually — for the realtime layer
only, behind the interface that already exists.

### Why Flutter

The target device is a cheap, low-RAM Android phone, where Flutter's own renderer
is more predictable than React Native's bridge. The cost is that the client
cannot import the protocol package and must mirror it by hand
(`apps/mobile/lib/src/models.dart`), which is the main argument for moving the
wire format to protobuf around M2.

## Data

**Postgres is the system of record.** Users, devices, sessions, chats,
membership, messages, ledger. Message storage is a plain table with `(chat_id,
seq)` as the primary key; partitioning by chat is the next step when it is
needed, and it is not needed yet. Reaching for Cassandra or Scylla at this stage
would buy scale the product does not have at the price of operational complexity
it cannot absorb.

**Redis** carries presence, cross-node fan-out, and rate limiting. It holds
nothing that cannot be lost.

**MinIO** holds media, self-hosted rather than S3. Two reasons: bandwidth out of a
distant region is slow and expensive for users paying by the megabyte, and media
residency is a plausible near-term regulatory requirement.

## The message model

Two fields carry the design.

**`client_id`** is generated on the device before a message is sent. It is the
idempotency key. The client retries the same `client_id` until it gets an ack;
the server dedups on `(chat_id, client_id)`. A user on a collapsing connection
never sees their message sent twice.

**`seq`** is assigned by the server, monotonic and gapless per chat, allocated by
`UPDATE chats SET last_seq = last_seq + 1 ... RETURNING` inside the message
insert's transaction. The row lock serialises concurrent senders. From this one
field come ordering, gap detection, sync ("everything after seq N"), and read
receipts as a cursor (`read_up_to_seq`) rather than per-message flags.

Delivery is `sending → sent → delivered → read`. The client writes the message to
SQLite as `pending`, renders it immediately, and moves it to `sent` when the ack
arrives with its seq.

## The reserved hooks

Four things exist in the schema today, unused, because adding them later means
migrating live data:

- `users.kind ∈ {human, bot, service}` — a bot is a user with a webhook, which is
  the entire on-ramp to service accounts and mini-apps.
- `messages.type` as an open enum, already including `payment` and
  `service_card`. New capabilities arrive as message types on the existing bus,
  never as a parallel system.
- The **double-entry ledger** — `ledger_accounts`, `ledger_transactions`,
  `ledger_entries`. Append-only, balanced per transaction, integer minor units
  (diram), idempotency key on every transaction. Enforced by database triggers
  (`packages/db/drizzle/0001_ledger_guards.sql`) rather than application code, so
  no future service can quietly violate them. It holds no money and will not
  until there is a licence or a partner. Reshaping a money model after it holds
  real balances is the most expensive migration a fintech can face; the
  constraints are free against empty tables.
- **Multi-device from the start.** Sessions belong to devices, not users. Access
  tokens are bound to a `device_id`. Retrofitting this means redoing auth, push
  routing and history sync simultaneously.

## Encryption

Cloud chats are encrypted in transit and at rest, not end to end. Opt-in E2EE
"secret chats" using libsignal are planned; hand-rolled cryptography is not an
option at any point.

This is a deliberate choice with a trade-off worth stating plainly. A licensed
payment super-app operating under national regulation acquires AML and lawful
intercept obligations that blanket end-to-end encryption directly contradicts.
Telegram's split model — cloud chats server-side, secret chats end-to-end — is
the only shape that squares messaging with the Phase-2 ambition. It is a product
and legal decision, not a technical one, and it should be made consciously rather
than discovered.

## Localisation

Tajik (Cyrillic) first, Russian second; Uzbek and English after M1. Two
consequences that are easy to miss and awkward to fix late:

- Postgres needs an ICU collation. Under the C locale, Tajik characters
  (ғ ӣ қ ӯ ҳ ҷ) sort and compare wrongly, which breaks contact ordering and name
  search. The cluster is initialised with `tg-TJ` and a `sakina_tg` collation
  exists for case- and accent-insensitive lookup.
- **Flutter ships no Tajik locale.** `GlobalMaterialLocalizations` covers around
  eighty languages and `tg` is not among them, so declaring it supported trips an
  assertion at startup. `apps/mobile/lib/src/l10n.dart` provides fallback
  delegates that serve Russian for framework strings while Sakina's own copy stays
  Tajik.

## Scaling notes

Known simplifications, recorded so they are choices rather than surprises:

- **Fan-out** is one Redis channel that every gateway receives in full, filtering
  for locally-held users. Correct and simple; O(nodes) chatter per message. It
  stops being reasonable in the tens of nodes, at which point the channel shards
  by `hash(user_id)` and nothing client-side changes.
- **Messages** live in one unpartitioned table. Partition by `chat_id` range when
  it hurts, not before.
- **Presence** is per-process. Cross-node presence needs a shared Redis key with a
  TTL; not needed until there is more than one gateway.
