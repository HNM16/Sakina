# Performance

Two benchmarks, both runnable, both with a pass/fail bar. Numbers below are from
this repository on a dev container — the shape is what matters, not the absolute
values on your hardware.

```bash
pnpm bench             # both
pnpm bench:fps         # frame rate under message load (needs playwright)
pnpm bench:throughput  # gateway latency and saturation
```

---

## Frame rate

`tools/dev-client/bench-fps.mjs` drives a real Chromium tab with a burst of
incoming messages while sampling `requestAnimationFrame` and the long-task
observer, under **4× CPU throttling** — because everything is 60fps on a laptop
and the target device is a 40-dollar Android.

Two instruments, because they answer different questions. rAF deltas show what
the user sees; long tasks show *why*. A task blocking the main thread for 90ms
is the cause, the dropped frames are the symptom.

### Before and after

120 messages, 4× CPU throttle:

| | Before | After |
| --- | --- | --- |
| p50 frame | 16.7ms | 16.7ms |
| **p95 frame** | **50.0ms** | **16.8ms** |
| **p99 frame** | **133.3ms** | **16.8ms** |
| worst frame | 150.0ms | 16.8ms |
| dropped (>25ms) | 21 (8.2%) | **0** |
| frozen (>50ms) | 10 (3.9%) | **0** |
| long tasks | 9, worst 90ms | **0** |
| main thread blocked | **566ms** | **0ms** |

At 300 messages and 6× throttle it still holds: one dropped frame in 607, no
long tasks at all.

Average FPS is deliberately not the headline. An app that renders 200 frames at
4ms and 10 at 300ms averages out fine and feels broken.

### What was wrong

One thing, in two places: **the whole view was rebuilt on every incoming
message.**

The dev client cleared its message container and recreated every bubble each
time a frame arrived — quadratic in the number of messages, and a burst of
twenty in one tick meant twenty full rebuilds, nineteen of them thrown away
before anything painted.

Three fixes:

- **Keyed incremental DOM.** Each message owns a node keyed by `client_id`. New
  ones are appended in a single `DocumentFragment`; changed ones are patched in
  place (only two things ever change after a bubble is on screen — its delivery
  state and its seq); untouched ones are never looked at.
- **One render per frame.** Work is coalesced onto `requestAnimationFrame`, so a
  burst produces exactly one DOM update, immediately before the paint.
- **Skip the chat list when it has not changed.** A cheap signature check, since
  the sidebar changes far less often than the message list.

Plus one correctness improvement that fell out of it: autoscroll now only
follows the bottom if the user was already there. Yanking someone away from
history they are reading is worse than a missed scroll.

### The same fixes in Flutter

The Flutter client had the identical shape of bug, and worse, because its
version went through SQLite:

- `_refresh()` re-read **the entire chat** (up to 100 rows, each re-decoded from
  JSON) *and* the entire chat list on every incoming message, on the UI isolate.
- `loadChats()` was **N+1** — one query for the chats, then one "last message"
  query per chat, then a sort in Dart. Thirty chats meant thirty-one queries,
  and it ran on every message.
- `notifyListeners()` rebuilt everything under the `AnimatedBuilder`, once per
  socket frame.
- Typing frames — which arrive several times a second, per participant — each
  triggered a full rebuild.
- `notifyTyping` was called from `onChanged`, so **every keystroke became a
  WebSocket frame**: a burst of traffic on metered data and a rebuild on the
  recipient for each character.

What changed:

| | |
| --- | --- |
| `loadChats()` | N+1 → **one query**, ordered in SQLite, plus an index on `(chat_id, seq DESC, created_at DESC)` |
| Incoming message | full chat reload → **patch one message in memory** |
| `sent` ack | full chat reload → **flip one bubble's state** |
| Notifications | one per socket frame → **coalesced to one per rendered frame** |
| Typing received | full rebuild → **rebuild only on the not-typing→typing transition** |
| Typing sent | one frame per keystroke → **throttled to one per 3s** |
| `markRead` | O(n) fold over every message → **scan back from the end** |
| Startup | decoded every message of every chat → **only the chat being opened** |
| List items | no keys → **`ValueKey(clientId)`**, so elements are reused rather than rebuilt |
| `DateFormat` | constructed per bubble per rebuild → **hoisted** |

**These are not measured.** There is no Dart SDK in this environment, so the
Flutter changes are reasoned from the same profile the browser client made
visible, not verified on a device. Run `flutter run --profile` with the
performance overlay on a real cheap Android before believing any of it.

A review pass over the uncompiled Dart found three bugs the first version
introduced, worth recording because they are what "unverified" actually means:

- **Batching on a microtask does not batch anything.** Every WebSocket frame
  arrives in its own event-loop turn, so a microtask fires once per message and
  the coalescing achieved nothing. It now defers to `addPostFrameCallback` —
  plus an explicit `scheduleFrame()`, because a post-frame callback never runs
  if the app is idle and no frame is pending, which would have meant messages
  silently never appearing.
- **Appending broke ordering against pending messages.** Unsent messages have no
  seq and sort last (`COALESCE(seq, MAX)` in SQLite). Blindly appending an acked
  message put it *after* a pending one. Insertion now scans back from the end —
  still O(1) for the common case, and correct when the tail is unsent.
- **`notifyListeners()` after dispose throws.** A frame callback scheduled just
  before sign-out would fire against a disposed `ChangeNotifier`. Every notify
  path is now guarded, including after each `await`.

---

## Gateway latency and throughput

`services/gateway/scripts/bench-throughput.mjs` runs 20 concurrent
conversations, in two phases.

**Phase 1 — latency at realistic load** (100 msg/s). This is the number that
matters. Ten thousand users sending twenty messages a day averages about 2/s;
even a twentyfold peak is around 50/s. Measuring latency at 4000/s tells you
what a saturated queue looks like, not what a user experiences.

```
ack latency  (send → server assigned a seq)     p50 3.6ms   p95 4.9ms   p99 7.3ms
end-to-end   (sender's wire → recipient's socket) p50 3.9ms   p95 5.5ms   p99 9.5ms
```

**Phase 2 — saturation.** Roughly **500–800 msg/s** on a single Node process
against one Postgres, varying run to run with whatever else the container is
doing — treat it as an order of magnitude, not a figure. Even the low end is
around **10× a busy-hour peak for 10,000 users**, so throughput is not the
constraint at this stage and optimising it further would be premature.

### What changed

The send path made about seven Postgres round trips per message. Two were
removed:

- **Membership folded into the seq allocation.** The transaction used to SELECT
  membership, then UPDATE the chat's `last_seq`. Now one statement does both —
  the row lock and the authorisation happen together, via `EXISTS` in the
  `WHERE`. Distinguishing "not a member" from "no such chat" costs a query, but
  only on the error path, which runs rarely.
- **Membership cached for the fan-out.** `getMemberIds` ran on every message,
  receipt and typing frame to answer a question that almost never changes. Now
  cached in process for 5 seconds.

The cache uses a short TTL rather than explicit invalidation, deliberately.
Correctness degrades gracefully: the worst case is that someone just added to a
group waits a few seconds for their first message, or someone just removed gets
one more. Both self-heal, and neither justifies the cross-process coupling that
precise invalidation would need.

Effect: roughly 750 → 800 msg/s saturation, and p50 end-to-end under saturation
dropped about 37%. Modest, which is the honest result — the send path was not badly written to
begin with, and the remaining cost is inherent to writing a row durably.

### Running it

The gateway's own per-connection send limit will throttle the benchmark and you
will measure the limiter instead of the server:

```bash
SEND_RATE_LIMIT=100000 SEND_RATE_WINDOW_MS=1000 pnpm dev
pnpm bench:throughput
```

---

## What is still unmeasured

| | |
| --- | --- |
| **Flutter on a device** | The changes above are reasoned, not profiled. Needs `flutter run --profile` on a cheap Android with the performance overlay. |
| **Many concurrent sockets** | The benchmark runs 40 sockets. The interesting question is thousands, and where memory per connection lands. |
| **Large groups** | Fan-out is tested at two members. A 200-member group multiplies the delivery work per message. |
| **Deep history** | Every chat in these tests is short. Scroll-back performance over tens of thousands of messages is untested, on both the server and in SQLite. |
| **Real networks** | All of this runs on loopback. The product claim is about a congested Tajik cell, and that is only provable there. |
