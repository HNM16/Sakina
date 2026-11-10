# Protocol

The wire contract between clients and Sakina. Authoritative for both the
TypeScript schemas in `packages/protocol` and the hand-written Dart mirror in
`apps/mobile/lib/src/models.dart` — when the two disagree, this document and the
zod schemas win.

Transport is JSON over one WebSocket per device. JSON is the M0 choice because it
is debuggable and both languages agree on it for free; protobuf is expected
around M2, once the frame set stops changing and per-megabyte cost starts to
matter. Envelope keys are kept short and payloads flat so that swap stays
mechanical.

## Frames

Every frame is `{ "t": <tag>, "d": <payload> }`.

### Client → server

| `t` | Payload | Notes |
| --- | --- | --- |
| `hello` | `{ v, token, device_id }` | Must be first. Socket is unauthenticated until `ready`. |
| `send` | `{ client_id, chat_id, payload }` | `client_id` is the idempotency key. |
| `read` | `{ chat_id, up_to_seq }` | A cursor, not per-message flags. |
| `typing` | `{ chat_id }` | Ephemeral, never stored, consumes no seq. |
| `sync` | `{ cursors: [{ chat_id, last_seq }] }` | Reconnect: "send me the diff." |
| `ping` | `{}` | Client-side keepalive, every 25s. |

### Server → client

| `t` | Payload | Notes |
| --- | --- | --- |
| `ready` | `{ user, server_time, chats }` | Handshake complete. |
| `message` | `Message` | Also sent to the sender's *other* devices. |
| `sent` | `{ client_id, chat_id, id, seq, created_at }` | Ack of your own send. |
| `read` | `{ chat_id, user_id, up_to_seq }` | Someone read up to this point. |
| `typing` | `{ chat_id, user_id }` | |
| `sync` | `{ chat_id, messages, has_more }` | `has_more` → backfill over HTTP. |
| `error` | `{ code, message, ref? }` | `ref` echoes the failing `client_id`. |
| `pong` | `{}` | |

Error codes: `bad_frame`, `unauthorized`, `forbidden`, `not_found`,
`rate_limited`, `payload_too_large`, `internal`.

## Message

```jsonc
{
  "id":         "uuid",   // server-assigned
  "client_id":  "uuid",   // DEVICE-generated, before sending
  "chat_id":    "uuid",
  "sender_id":  "uuid",
  "seq":        1,        // server-assigned, monotonic and gapless PER CHAT
  "payload":    { "type": "text", "text": "Салом!" },
  "created_at": 1754553600000,  // epoch ms, server clock
  "edited_at":  null,
  "deleted_at": null
}
```

Payload types: `text`, `media`, `voice`, `system`, and — reserved, not yet
implemented — `payment` and `service_card`. The set is open by design: payments,
bills and mini-app results arrive as new types on this bus, never as a parallel
system. Adding one must never require touching delivery, sync or storage.

Money in any payload is **integer minor units** (diram, 1/100 TJS) and never a
float.

## The two rules that matter

### 1. Retry with the same `client_id`

The client generates `client_id` before sending and reuses it verbatim on every
retry. The server dedups on `(chat_id, client_id)` and returns the original `seq`
and `id`. It sends the ack even for a duplicate, because a client that is
retrying is a client that never saw the first one.

This is what makes sending safe on a connection that dies mid-request. Generating
a fresh id on retry would silently duplicate the user's message.

### 2. Sync is "everything after seq N"

```
client → { "t":"sync", "d":{"cursors":[{"chat_id":"…","last_seq":7}]} }
server → { "t":"sync", "d":{"chat_id":"…","messages":[…],"has_more":false} }
```

Because `seq` is gapless per chat, the client detects a hole by arithmetic alone
and never needs a separate reconciliation pass. If `has_more` is true, the client
is too far behind to catch up on the socket and backfills over
`GET /v1/chats/:id/messages` instead of dragging history through the connection.

## Delivery lifecycle

```
        write to local SQLite
compose ────────────────────► pending ──── `sent` ack ────► sent
                                 │                            │
                                 │ error frame                │ `read` frame
                                 ▼                            ▼
                              failed                         read
```

The client renders from SQLite at every stage. A message is on screen before the
socket has been touched.

## HTTP

Small on purpose — HTTP handles only what a socket is bad at.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v1/auth/otp/request` | Send a code. Returns `dev_code` in dev mode. |
| `POST` | `/v1/auth/otp/verify` | Verify, register device, issue tokens. |
| `POST` | `/v1/auth/refresh` | Rotate. The presented token is revoked. |
| `POST` | `/v1/auth/logout` | Revoke every session on the device. |
| `GET` | `/v1/me` | Profile and device list. |
| `GET` | `/v1/chats` | Chat summaries. |
| `POST` | `/v1/chats` | Create direct or group. Direct is unique per pair. |
| `GET` | `/v1/chats/:id/messages` | Backfill: `after_seq`, `before_seq`, `limit`. |
| `POST` | `/v1/chats/:id/read` | Read cursor, for clients without a socket. |

Errors are `{ "error": { "code", "message" } }`.

Access tokens are 15-minute JWTs bound to a `device_id`. Refresh tokens are
opaque, stored only as SHA-256 hashes, and rotate on every use — a stolen token
replayed after the legitimate client has rotated fails, which surfaces the theft
instead of granting an indefinitely renewable session.
