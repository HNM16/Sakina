# How a message reaches the other person

The full path, from a thumb hitting send to a phone lighting up. Everything
marked ✅ is built and covered by `services/gateway/scripts/e2e-smoke.mjs`;
everything marked ⬜ is not built yet and is called out honestly, because one of
the gaps is the difference between a demo and a messenger.

---

## The path

```
   Nekruz's phone                  Sakina servers                 Farrukh's phone
   ───────────────                 ──────────────                 ───────────────
1. write to SQLite ✅
   bubble appears (clock)
        │
2.      └── WS `send` ──────────►  gateway ✅
                                     │
3.                                   ├─ member check
                                     ├─ chats.last_seq + 1  ← the row lock
                                     └─ INSERT message
                                            │
4.      ◄── WS `sent` {seq} ────────────────┤ ✅
        clock → tick                        │
                                            │
5.                                   Redis publish ✅
                                            │
                                 ┌──────────┴──────────┐
                                 ▼                     ▼
                          gateway node A        gateway node B
                                 │                     │
6.                        is Farrukh here?      is Farrukh here?
                                 │                     │
                            ┌────┴────┐                
                     yes ───┘         └─── no          
                       │                    │
7.  online:            └── WS `message` ────┼──────────────► SQLite → renders ✅
                                            │
8.  offline:                                └── FCM / APNs ─► notification ✅
                                                              │
9.  reopens app:            ◄── WS `sync` {last_seq} ─────────┘ ✅
                            ─── the diff ──────────────────►
```

## Step by step

**1. Written locally first.** `sendText()` inserts into SQLite with state
`pending` and a device-generated `client_id`, then tells the UI to re-read. The
bubble is on screen with a clock icon before any packet leaves the phone. This
is why the app feels instant on a bad line — and why it works with the radio
off entirely.

**2. Over the socket.** One persistent WebSocket per device. If it is down the
frame goes into an in-memory queue and the message stays in the SQLite outbox;
both drain on reconnect. Nothing is lost by being offline.

**3. The server assigns the order.** Inside one transaction: confirm the sender
is a member, then `UPDATE chats SET last_seq = last_seq + 1 ... RETURNING`, then
insert the message with that `seq`. **The row lock on the chat is what makes
ordering correct** — two people sending simultaneously serialise on it, and
neither can get the same number.

Idempotency lives here too. A unique index on `(chat_id, client_id)` means a
client retrying a send whose ack was lost gets the *original* `seq` back rather
than a second message. This is the case that actually happens on Tajik mobile
data, and it is in the test suite.

**4. The sender gets an ack.** The `sent` frame carries the server-assigned
`seq`. The client swaps its optimistic row for the real one and the clock
becomes a tick. The ack is returned even for a duplicate — a client retrying is
precisely a client that never saw the first one.

**5–6. Fan-out.** The gateway publishes one envelope to Redis:
`{ user_ids, frame, exclude_device_id }`. Every gateway process receives it and
delivers only to the users it currently holds a socket for. The sending device
is excluded because it already got the ack; **the sender's other devices are
not** — that is how multi-device stays in sync.

This is O(nodes) chatter per message. Correct, simple, and fine to a handful of
nodes. Sharding the channel by `hash(user_id)` is the fix when it stops being
fine, and nothing client-side changes.

**7. Online delivery.** The recipient's client writes to SQLite, then the UI
re-reads. Same rule as sending: widgets never render a network response.

**8. ✅ Offline delivery — push.** When the app is closed the WebSocket is dead.
The OS killed it, and no amount of protocol design changes that. Delivery then
goes through the platform push services: **FCM on Android, APNs on iOS** (via
FCM, so the server talks to one provider rather than two).

Three pieces make it work:

- **Presence in Redis**, keyed per device with a TTL refreshed by the gateway's
  heartbeat. The gateway's own registry only knows its own sockets, so "is this
  device connected *anywhere*" has to live somewhere shared. Keyed per device
  because the decision is per device — a laptop with the web client open does
  not mean the phone in a pocket should stay silent.
- **A Redis queue**, so the gateway never waits on an HTTP round trip to Google
  while a user watches a send spinner.
- **`services/worker`**, which drains the queue, drops every device that
  currently holds a socket, and sends to the rest. A provider answering
  "unregistered" retires that token immediately; anything else is transient and
  only counts toward a limit, so an FCM outage cannot wipe every token on the
  platform.

**The payload carries no message text.** It carries `chat_id` and `seq`. The
client wakes, syncs, and composes the lock-screen notification from its own
SQLite. Content in the payload means handing message text to Google and Apple,
and it would have to be undone the moment E2EE arrives. A generic alert body is
still sent rather than a silent data-only push, because silent pushes are
throttled hard on iOS and unreliable in Android's Doze — a notification that
arrives beats a perfectly minimal one that does not.

Verified by `services/worker/scripts/push-smoke.mjs`: an offline device is
pushed, an online one is not, the sender is never pushed for their own message,
no message text appears anywhere in the payload, and a dead token is retired
rather than retried.

**9. Catch-up.** On reconnect the client sends its highest `seq` per chat and
gets back the diff. Because `seq` is gapless per chat, a hole is detectable by
arithmetic alone — no reconciliation pass, no "are you sure you have everything"
handshake. If the client is too far behind, the server says `has_more` and it
backfills over HTTP instead of dragging a week of history through the socket.

---

## Delivery states, and what each one honestly means

| Shown | Means |
| --- | --- |
| Clock | On this phone's disk. Nothing more. |
| Tick | The server has it and assigned a `seq`. It will arrive. |
| ⬜ Double tick | On the recipient's device. Needs a `delivered` frame — not built. |
| Blue / read | The recipient's `read_up_to_seq` passed it. ✅ |
| Error | Rejected — not a member, rate-limited, malformed. Stays in the thread, retryable. |

The gap is `delivered` — currently a message goes from `sent` straight to
`read`. The wire format has room; it needs a frame emitted when a client writes
an incoming message to disk.

---

## What is not built

| | Why it matters |
| --- | --- |
| **`delivered` receipts** | Users read the second tick as "it arrived"; we currently cannot say that. |
| **Notification enrichment** | The lock screen currently says "Паёми нав". Showing the real text needs an iOS Notification Service Extension and an Android enrichment step reading local SQLite. |
| **Media** | Presigned upload to MinIO, message carries the key. Never proxy bytes through the gateway. |
| **Group fan-out at scale** | Fine for small groups. A 10,000-member group needs the write fanned out differently. |
| **Server-side retention** | Messages accumulate forever. Fine at 10k users, a decision to make before it is not. |
