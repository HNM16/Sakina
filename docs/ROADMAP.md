# Roadmap

First make it work, then make it perfect.

## M0 — two people can talk ✅

**Done when:** two devices exchange a message, it arrives instantly, and it
survives app restart and airplane mode. Nothing else — no media, no groups, no
avatars.

- [x] Monorepo, Docker Compose, one-command local stack
- [x] `packages/protocol` — the wire contract
- [x] Schema: users, devices, sessions, chats, membership, messages
- [x] Phone + OTP auth, device-bound sessions, rotating refresh tokens
- [x] WebSocket gateway: send, ack, deliver, typing, read cursors, sync
- [x] Per-chat gapless `seq`; idempotent sends on `(chat_id, client_id)`
- [x] Ledger tables with database-enforced invariants, holding nothing
- [x] Flutter client: four screens, SQLite store, outbox, reconnect
- [x] End-to-end smoke test (`services/gateway/scripts/e2e-smoke.mjs`)

Verified: 24/24 backend checks pass, including the flaky-network retry case and
offline catch-up. The Flutter client has not been compiled — see
`apps/mobile/README.md`.

## M1 — a messenger people would actually use

The gap between "it works" and "I would install this."

- Contact discovery — phone-book matching, with a privacy design of its own
  (hashed identifiers, no plaintext address-book upload)
- Media: images and files. Presigned MinIO uploads, resumable, client-side
  downscaling before upload — the user is paying per megabyte
- Group chats: admin roles, invite links, member management
- Push notifications: FCM and APNs, routed per device
- Profiles: display name, username, avatar
- Message editing, deletion, reply-to, forwarding
- Proper i18n: ARB files, Tajik and Russian complete
- **A real OTP path.** Direct arrangement with Tcell / Megafon Tajikistan /
  Babilon-M / ZET-Mobile, or a regional aggregator holding one. Plan for flash-call
  verification as the primary route and SMS as fallback: far cheaper per
  verification and already familiar in the region. International aggregators
  deliver to +992 unreliably and at a price a free messenger's signup funnel does
  not survive. Start this early — it is procurement lead time, not engineering
  time.

## M2 — voice

- Voice messages (Opus, waveform preview)
- One-to-one calls over WebRTC
- **Self-hosted coturn is mandatory.** Nearly every mobile user in Tajikistan sits
  behind carrier-grade NAT, so peer-to-peer will mostly fail and calls will relay.
  Budget the bandwidth
- Swap the wire format to protobuf, now that the frame set has settled
- In-country hosting: latency, last-mile, and likely data-residency rules

## M3 — the platform

The point at which Sakina stops being only a messenger.

- Service accounts: `users.kind = bot`, webhook delivery, a bot API
- Mini-apps: WebView plus a JS bridge, with a permission model designed before
  the first third party is let in
- `service_card` message type: bills, receipts and mini-app results rendered
  inline in a thread
- Channels for one-to-many broadcast

## M4 — money

Not before the licensing question is answered.

- **Regulatory work first.** NBT licensing, or a partnership where a licensed
  bank is the ledger of record and Sakina is the experience layer. Assume the
  partnership route for years one and two
- `services/ledger`: the double-entry core, already schema'd and constrained
- `PaymentProvider` adapters — Korti Milli, Alif, Dushanbe City, Eskhata,
  Amonatbonk, operator wallets — each a plugin behind one interface
- `payment` message type: transfers inside a conversation, which is the feature
  that makes a messenger into a super-app
- Utility bills: Barqi Tojik and the rest, as `service_card` flows
- Merchant QR payments
- AML, transaction limits, reconciliation, dispute handling — the unglamorous
  majority of the work

**Remittances are the strategic prize.** Tajikistan has among the world's highest
remittance-to-GDP ratios, and a large share of users work abroad. Cheap, fast
transfers home would be the strongest possible wedge — and cross-border money
movement is the most heavily regulated thing in this document, which is why it
sits at the end rather than the beginning.

## Deliberately not doing yet

- Kubernetes. Docker Compose on a VPS until it genuinely hurts
- Sharded fan-out. One Redis channel until there are enough nodes to justify it
- Message-store partitioning. One table until the query plans complain
- End-to-end encryption by default. See the encryption section in
  `ARCHITECTURE.md` — the tension with a regulated payments layer is real and
  needs deciding, not defaulting
