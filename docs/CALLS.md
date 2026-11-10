# Voice and video calls

Not built. This is the design, and the reason it is written down before any code
is that **calls in Tajikistan are a bandwidth-and-NAT problem, not a codec
problem**, and getting the infrastructure wrong is expensive to undo.

Target: M2, after push notifications and media.

---

## WebRTC, and no alternative worth considering

Every messenger uses it. It is in every browser and both mobile OSes, it handles
NAT traversal, jitter, packet loss and echo cancellation, and the alternative is
writing a real-time media stack, which is a company rather than a feature.

Three pieces:

- **Signalling** — how two clients agree to connect. This is *ours*, over the
  existing WebSocket.
- **STUN/TURN** — how they find a network path. This is where the money goes.
- **Media** — the audio and video itself, flowing directly between clients or
  through a relay.

## Signalling: new frame types, not a new system

Calls slot onto the existing socket. No second connection, no polling.

```
call_offer    { call_id, chat_id, sdp, media: "audio" | "video" }
call_answer   { call_id, sdp }
call_ice      { call_id, candidate }        // exchanged both ways
call_end      { call_id, reason }           // hangup | busy | declined | timeout | failed
```

A `call` message type also goes in the thread, so the history shows "missed
call, 14:32" like any other event. That is the pattern the whole architecture is
built on: a call is another message type on the same bus.

Server responsibilities are deliberately thin — route frames between members,
enforce membership, mint TURN credentials, log duration for the call log. **The
server never touches media.**

## The part that actually decides this: CGNAT

Nearly every mobile subscriber in Tajikistan sits behind carrier-grade NAT.
Both parties are behind it, neither has a routable address, and **peer-to-peer
will usually fail.** Calls will relay.

That has consequences worth stating in numbers, because they are the whole
operating cost of this feature:

- **STUN is nearly free** and works when at least one side is reachable. It will
  not be, most of the time.
- **TURN relays the entire call.** A voice call at ~40 kbps costs roughly
  **~36 MB per hour of server bandwidth** (both directions). Video is 10–20×
  that. On a 1,000-concurrent-call day this is the largest line item in the
  infrastructure bill by a wide margin.

`coturn` is already in `infra/docker-compose.yml` behind the `calls` profile, so
the shape is provisioned. What it needs before launch:

- **Hosted close to users**, ideally in-country. Relaying Dushanbe-to-Dushanbe
  audio through Germany adds latency to every call for no reason.
- **Ephemeral credentials.** Never a static shared secret in the app binary — a
  TURN server with a leaked static password becomes someone else's free proxy.
  Use the standard time-limited HMAC credential, minted per call by the API.
- **Real bandwidth budgeting.** Metered per call, with an eye on whether a
  1 GB/month VPS allowance is about to evaporate.

## Codecs

**Opus for audio.** Not negotiable — it is the WebRTC default, it is excellent,
and critically it adapts its bitrate downward under loss. At 16–24 kbps it still
sounds fine, which matters on a 3G cell outside Dushanbe.

**VP8 for video**, at least initially. H.264 has better hardware decode support
on cheap Android but carries patent licensing questions; VP8 is universally
supported in WebRTC and free. Revisit if battery drain on low-end devices proves
worse than the licensing headache.

Start **audio only.** Voice is what this market uses; video is a
bandwidth multiplier on top of a bandwidth problem, and it can wait.

## Making the phone ring

The hardest platform work, and it has nothing to do with WebRTC.

When the app is closed the socket is dead — same problem as message delivery
(`docs/DELIVERY.md`), but with a two-second budget instead of a leisurely one.

- **iOS: PushKit VoIP push + CallKit.** A VoIP push wakes the app even when it is
  suspended. **CallKit is mandatory** — Apple requires that a VoIP push be
  reported to CallKit essentially immediately, and an app that does not is
  terminated and loses the entitlement. The payoff is that calls appear on the
  lock screen like a real phone call.
- **Android: high-priority FCM + ConnectionService.** High-priority messages
  punch through Doze. Full-screen intent notification for the incoming-call UI.
  Test on the cheap Chinese Android skins the target market actually
  buys — Xiaomi, Oppo, Realme, Tecno — because their aggressive battery managers
  kill background work in ways stock Android does not, and this is where VoIP
  apps quietly break.

## Group calls, later

One-to-one is peer-to-peer (or relayed). Group calls are a different
architecture: every extra participant multiplies the streams, so past three or
four people it needs an **SFU** — a server that receives each stream once and
forwards it. LiveKit, Janus and mediasoup are the realistic options.

This is a substantial piece of infrastructure with substantial bandwidth cost.
Not before there is a reason.

## Encryption

WebRTC media is encrypted in transit by default (DTLS-SRTP) — even a TURN relay
forwards ciphertext it cannot read. That is the baseline and it is genuinely
good.

**End-to-end** for calls means the key exchange must not be brokered by our
server. Practical for one-to-one; considerably harder through an SFU, which is
one more reason group calls come later. Same tension as messaging: see the
encryption section in `docs/ARCHITECTURE.md`.

## Order of work

1. Signalling frames + call state machine, both clients online, same wifi
2. Self-hosted coturn with ephemeral credentials — nothing works on real
   networks without it
3. CallKit and ConnectionService, so calls survive a locked screen
4. Push wake-up, tested on cheap Android skins
5. Poor-network handling: adaptive bitrate, reconnection, "weak connection"
6. Call history as a message type in the thread
7. *Later:* video, then group calls via an SFU

The thing to build first is not the call — it is step 2. A call that works in
the office and fails on a real Tajik mobile network is worse than no call
feature, because it burns the reliability reputation that is the entire product
claim.
