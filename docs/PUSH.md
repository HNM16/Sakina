# Push notifications

Without push, Sakina only delivers to people who already have it open. That is a
demo, not a messenger — which is why this was the top of M1.

The server path is built and tested end to end. What is left is a Firebase
project and a physical phone, neither of which can be created from a dev
container.

---

## How it works

```
gateway                    Redis                    worker              FCM/APNs
───────                    ─────                    ──────              ────────
message stored
   │
   ├─ fan-out to live sockets
   │
   └─ LPUSH push job ──►  queue  ──► BRPOP ──►  which recipients
                                                are offline?
                          presence ◄──────────  (per-device keys)
                                                      │
                                                      └──► send ────► 📱
```

Three decisions worth knowing:

**The gateway never calls FCM.** Sending is an HTTP round trip to a third party
that can be slow or down, and the person watching a send spinner must not wait
for it. The gateway pushes a job onto a Redis list and returns.

**Presence lives in Redis, keyed per device.** A gateway process only knows its
own sockets, so "is this device connected *anywhere*" has to be shared. Per
device rather than per user because the decision is per device — someone with
the web client open on a laptop still wants their phone to buzz. Keys carry a
TTL refreshed by the gateway heartbeat, so a process killed uncleanly self-heals
within 90 seconds instead of suppressing notifications forever.

**The payload carries no message text.** Only `chat_id`, `seq`, `message_id`,
`sender_id`. The client wakes, syncs over its socket, and composes the
lock-screen notification from its own SQLite. Two reasons, both firm: message
content in a push payload is message content handed to Google and Apple, and it
would all have to be undone the moment E2EE arrives.

A *generic* alert body is still sent rather than a fully silent data-only push.
Silent pushes are throttled hard by iOS and unreliable in Android's Doze, and a
notification that arrives is worth more than a perfectly minimal one that does
not.

## Dead tokens

Push tokens rot constantly — reinstalls, restores from backup, some OS updates.
A provider answering "unregistered" (FCM 404, APNs 410) is authoritative: the
token is retired immediately. Anything else is transient and only counts toward
`PUSH_FAILURE_LIMIT`, so an FCM outage cannot wipe every token on the platform
in one afternoon.

## Testing it without any of this set up

`PUSH_PROVIDER=console` records pushes instead of sending them, and the worker
exposes them at `/dev/pushes`. That is what makes the whole path testable with
no Firebase project, no Apple developer account, and no handset:

```bash
pnpm test:push
```

17 checks: an offline device gets a push, an **online one does not**, the sender
is never pushed for their own message, no message text appears anywhere in the
payload, and a dead token is retired rather than retried.

`PUSH_DEV_INSPECT` is refused in production, and `PUSH_PROVIDER=console` is too,
so neither can escape a dev machine.

---

## Setting up Firebase — the part you have to do

FCM handles both platforms: on iOS it forwards to APNs, so the server talks to
one provider instead of two.

### 1. Firebase project

1. Create a project at <https://console.firebase.google.com>.
2. Add an Android app with package name `tj.sakina.app`. Download
   `google-services.json` → `apps/mobile/android/app/`.
3. Add an iOS app with the same bundle id. Download `GoogleService-Info.plist` →
   `apps/mobile/ios/Runner/`.

Both files are gitignored — they identify your project and do not belong in the
repository.

### 2. Server credentials

Project settings → Service accounts → **Generate new private key**. From the
JSON:

```bash
FCM_PROJECT_ID=your-project-id
FCM_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"
PUSH_PROVIDER=real
```

The legacy server-key API was shut down in 2024; a service account is the only
option now. The private key contains real newlines — keep them escaped as `\n`
in the env file, which the provider unescapes.

### 3. iOS also needs an APNs key

Firebase cannot deliver to iOS on its own. In the Apple Developer portal,
Certificates → Keys → **+** → Apple Push Notifications service (APNs). Download
the `.p8` (once only — Apple will not let you download it again) and upload it
to Firebase under Project settings → Cloud Messaging → APNs Authentication Key.

`ApnsPushProvider` in `packages/core/src/push.ts` exists for talking to Apple
directly, should you ever want to drop the FCM dependency on iOS. It is not the
default path.

### 4. Flutter

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:4000 \
            --dart-define=WS_URL=ws://10.0.2.2:4001/ws
```

The app calls `Firebase.initializeApp()` in a try/catch: **without a Firebase
config it still runs, it just never notifies.** That keeps the project buildable
before anyone has set any of this up.

Android 13+ needs the runtime notification permission, which `PushService.start`
requests — after the chat list is on screen rather than on the splash, since a
permission prompt makes more sense once someone can see what they would be
notified about.

---

## Testing on a real phone

The only test that really counts, and the one no CI can run.

1. Sign in on the phone.
2. Send it a message from the browser dev client (`pnpm dev:client`).
3. **Background the app** — home button, not force-quit. A notification should
   arrive.
4. **Force-quit it entirely.** A notification should still arrive; that is the
   background isolate handler doing its job.
5. Open the chat and send again with the app in the foreground. There should be
   **no** notification — the message is already on screen.

Then the ones that break in the field:

- **Test on the phones the market actually buys.** Xiaomi, Oppo, Realme, Tecno.
  Their battery managers kill background work in ways stock Android does not,
  and this is where VoIP and messaging apps quietly stop working. Some need the
  app explicitly whitelisted in the vendor's battery settings — this is a
  support-documentation problem as much as an engineering one.
- **Leave the phone idle for an hour**, then send. That is Doze, and it is why
  the FCM messages are sent with `priority: HIGH`.
- **Mobile data, not wifi.** FCM keeps its own long-lived connection; on a
  congested Tajik cell it can be slow to wake.

## What is left

| | |
| --- | --- |
| **Notification enrichment** | The lock screen says "Паёми нав". Showing the real text needs an iOS Notification Service Extension and an Android enrichment step, both reading local SQLite. Worth doing — after the basic path is proven on real hardware. |
| **Per-chat mute** | `chat_members.muted_until` exists in the schema and is not yet honoured by the worker. |
| **Badge counts** | The unread count is computable from `last_seq - read_up_to_seq`; it is not currently sent. |
| **Quiet hours** | Nobody wants a group chat at 3am. |
| **Queue durability** | The queue is a Redis list with BRPOP: at-most-once. A worker killed mid-job loses that job, which costs a delayed notification, not a message — the client syncs everything on next open. Redis Streams with a consumer group is the upgrade, and the job shape does not change. |
