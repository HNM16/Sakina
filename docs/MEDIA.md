# Photos, videos and files

Run `pnpm test:social` to see all of this exercised end to end.

## The one decision everything follows from

**The bytes never pass through the API.**

The client asks for a ticket, uploads straight to object storage, then sends a
message carrying the key. A 40MB video on the uplink most of this audience has
would otherwise occupy a Node request for two minutes, and media is the largest
thing this product will ever move.

```
client                    api                     storage
  |  POST /v1/media/upload  |                         |
  |------------------------>|  authorise, then sign   |
  |<------------------------|  { key, url, headers }  |
  |                                                   |
  |  PUT <presigned url>                              |
  |-------------------------------------------------->|
  |                                                   |
  |  send { type: media, key, ... } over the socket   |
  |------------------------>|                         |
```

Authorisation happens at step one, before a byte moves. Checking afterwards
would mean anyone with an account could use the bucket as free storage by
uploading and never sending — and it would mean a channel subscriber spends
their data allowance on a video before being told they cannot post.

## Two providers

Same pattern as push and email, for the same reason.

| | |
| --- | --- |
| `local` | Files on disk, served back through the API with an HMAC-signed URL. No infrastructure, which is what makes the whole path testable on a laptop |
| `s3` | MinIO in production, with SigV4 query-string presigning written out by hand |

`local` is not a shortcut around the real flow. The client still requests a
ticket, still gets a URL that expires, and still cannot read a key it was not
given — only the transport differs. That is what makes the smoke test meaningful.

SigV4 is ~80 lines in `packages/core/src/storage.ts` rather than a dependency:
the AWS SDK is roughly 15MB for the one function used here, and the signing
algorithm has not changed since 2012.

**Untested:** the `s3` path has never run against a real MinIO, because there is
no Docker in the environment this was built in. `local` is covered end to end.
Same shape of caveat as FCM and APNs in `docs/PUSH.md`.

## Limits, and why they are low

| Kind | Cap |
| --- | --- |
| Image | 12 MB |
| Video | 64 MB |
| File | 100 MB |
| Thumbnail | 512 KB |

Set against Tajik mobile data, not against what a server can store. A 100MB
video is technically easy and practically hostile: on a metered connection it is
real money, and on a typical uplink it is a four-minute upload that will not
survive being backgrounded. Telegram's 2GB limit is a desktop feature that
happens to also exist on mobile.

Above 5MB the app asks before sending. Only above — asking about every 200KB
photo trains the dialog away inside a week, which is the failure mode every
confirmation dialog has.

Photos are downscaled to 2048px at quality 82 on the way in. The target device
is a cheap Android and the target network is metered; a 12MP original helps
nobody at the size it will be looked at.

## The allowlist, and the two refusals

Mime types are an **allowlist**. The blocklist version of this decision is how
you end up hosting phishing pages: someone uploads `text/html`, the download URL
renders it in a browser, and it is on your domain.

Two types are refused outright rather than downgraded to `file`:

- **`text/html`** — a "document" a browser will execute is not a document.
- **`image/svg+xml`** — SVG is a script container wearing an image's clothes.

Anything unrecognised becomes `file`, which is safe: files are only ever served
as `Content-Disposition: attachment` with `X-Content-Type-Options: nosniff`, and
never inline.

The **server** decides the kind from the mime type, and sends it back in the
ticket. A client that decided for itself could label an executable as a photo.

## Keys

```
chat/<chat-id>/<kind>/<uuid>.<ext>
```

Namespaced by chat, so "delete this chat's media" is a prefix scan. Random, so
knowing a chat id does not let you enumerate its photos. **No filename** — that
goes in the message payload, not into a URL that every proxy in between will log.

Every read re-checks membership rather than trusting the message the key arrived
in, so leaving a group actually stops working. And a key can only be fetched for
the chat it belongs to: without that check a member of chat A could ask for a
signed URL to chat B's photo.

## On the client

Attachments are **not** downloaded automatically unless they are already on disk.
A photo shows its size and waits for a tap. This is the difference between
opening a family group costing nothing and opening it costing a week's data.

Downloads are cached by key, forever. Object keys are immutable — the same key
always names the same bytes — so there is no invalidation problem. The download
writes to a `.part` file and renames, because rename is atomic and a half-written
file that looks complete is worse than no file.

Every attachment has three real states, not one spinner standing in for the
others: **not fetched** (with the size, so the cost of tapping is visible),
**fetching**, and **failed** (with a retry, because an attachment that vanishes
is worse than one that says it failed).

## What is not built

- **Thumbnails are in the protocol and not yet generated.** `thumb_key` exists
  on `MediaPayload` and the server will sign an upload for one; nothing creates
  them yet. Until then a photo in a list is the full photo, which is exactly the
  data cost the field exists to avoid. This is the highest-value gap here.
- **Voice notes.** `VoicePayload` has been in the protocol since the first
  commit; nothing records them.
- **Orphan sweep.** An upload that is ticketed and never sent leaves bytes in
  storage with no message pointing at them. `StorageProvider.remove` exists for
  it; the job that calls it does not.
- **Progress.** Uploads report 0 then 1. Real progress needs a streaming PUT.
