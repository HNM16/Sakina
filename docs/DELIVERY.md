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
8.  offline:                                └── FCM / APNs ─► notification ⬜
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

**8. ⬜ Offline delivery — the gap that matters.** When the app is closed the
WebSocket is dead. The OS killed it, and no amount of protocol design changes
that. Delivery then requires the platform push services: **FCM on Android, APNs
on iOS**. This is not built. Until it is, Sakina only delivers to people who
already have it open, which is a demo rather than a messenger. It is the single
highest-priority item in M1.

The design when it is built: push carries no message content, only "you have
something new in chat X". The client wakes, opens the socket, and syncs. Content
in the notification payload means handing message text to Google and Apple, and
it breaks the moment E2EE arrives.

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
| **Push notifications (FCM/APNs)** | Without this the app only works while open. **Highest priority in M1.** |
| **`delivered` receipts** | Users read the second tick as "it arrived"; we currently cannot say that. |
| **Media** | Presigned upload to MinIO, message carries the key. Never proxy bytes through the gateway. |
| **Group fan-out at scale** | Fine for small groups. A 10,000-member group needs the write fanned out differently. |
| **Server-side retention** | Messages accumulate forever. Fine at 10k users, a decision to make before it is not. |
