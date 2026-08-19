# What is missing

Everything Sakina needs to stop feeling like a skeleton and start feeling like
an app someone would choose. The order is an argument, not a schedule.

**Section A is built** (`pnpm test:motion`). Everything else is still research.

Effort is rough: **S** is a day or less, **M** is a few days, **L** is a week or
more, **XL** is a project with its own design.

For the features meant to make Sakina *different* rather than *complete*, see
[`DIFFERENTIATION.md`](DIFFERENTIATION.md).

---

## A. Motion and feel ✅ built

**Done.** The vocabulary lives in `apps/mobile/lib/src/motion.dart` and
`pnpm test:motion` fails the build if an animation is added without it.

Everything below is implemented. Kept in full rather than deleted, because the
argument for each one is the record of why it exists — and because the next
person to change an animation should be able to read what it was for.

One thing to keep in mind while reading: **none of it has been run.** There is
no Flutter SDK in this environment, so the motion is read-checked and
machine-checked but never once watched. Durations and curves are the values
most likely to want adjusting the first time somebody sees them on a real
phone.

| | Feature | Why it matters | Effort |
| --- | --- | --- | --- |
| A1 ✅ | **Hero transition on opening a chat** — the avatar and title fly from the list row into the app bar | This is the single highest-value animation in any messenger. It answers "where did I come from" without a thought, and it is what makes Telegram feel expensive. Flutter's `Hero` does most of it | M |
| A2 ✅ | **Message send animation** — the bubble lifts from the composer rather than appearing | The composer-to-bubble jump is the most repeated interaction in the product. Ten thousand times a day per user, and right now it is a hard cut | M |
| A3 ✅ | **Staggered chat-list entry on first load** — rows arrive over ~200ms | Covers the moment where an empty list becomes a full one. Without it, the list pops and looks like a bug | S |
| A4 ✅ | **Pull-to-refresh with real feedback** — the chorkhona mark drawing itself as you pull | A brand moment in a place people already pull. Cheap: the mark is already a `CustomPainter`, animate its stroke | M |
| A5 ✅ | **Typing indicator with animated dots** | Currently text. Animated is the universal signal, and text reads as a status bar rather than as a person | S |
| A6 ✅ | **Unread badge count-up**, and the badge shrinking to nothing when a chat is read | The moment of "I cleared it" deserves feedback. Counting down to zero is more satisfying than a badge disappearing | S |
| A7 ✅ | **Swipe-to-reply** with a spring-back and a haptic tick at the threshold | The most-used gesture in modern messengers. Also a Nielsen #7 win: an expert shortcut that beginners never have to find | M |
| A8 ✅ | **Long-press context menu with a scale-and-blur backdrop** | Where reply, forward, copy, delete, react all live. Without it, every message action needs its own button | M |
| A9 ✅ | **Reduced-motion audit as a test** — extend `test:devices` to assert every animation has a zero path | We built `motion()` and nothing enforces its use. A guardrail that is not checked decays | S |
| A10 ✅ | **Haptics vocabulary** — a light tick on send, a heavier one on error, none on scroll | Haptics are the cheapest way to feel expensive, and the most commonly overdone. A written vocabulary stops it becoming noise | S |
| A11 ✅ | **Skeleton screens with a shimmer that respects reduce-motion** | See section B. Listed here because the shimmer is the part that gets it wrong | S |
| A12 ✅ | **Page transition direction that matches the hierarchy** — forward slides in, back slides out | Currently both use the same builder. Directionality is how people build a spatial model of an app | S |

## B. Loading, empty and error states

The design-tells catalogue calls this Category D — not aesthetics, completeness.
Some of it exists; most does not.

| | Feature | Why it matters | Effort |
| --- | --- | --- | --- |
| B1 | **Skeleton chat list on cold start** sized to the rows it replaces | The app currently shows an empty screen while SQLite opens. On a cheap Android that is 300–600ms of looking broken | S |
| B2 | **Skeleton message list** when opening a chat with no local history | Same, and worse: an empty conversation looks like lost history | S |
| B3 | **Per-message send-failure UI with retry on the bubble** | `docs/UX.md` #9 already flags this as owed. A failed message you cannot retry is a dead end | S |
| B4 | **Upload progress** — real bytes, not 0-then-1 | We report two states. On a 40MB video over a slow uplink that is two minutes of nothing. Needs a streaming PUT | M |
| B5 | **Cancel an in-flight upload** | Owed in `UX.md` #3. Sending the wrong 40MB video and being unable to stop it is a real cost in money | M |
| B6 | **A global "reconnecting" state that distinguishes *no network* from *server unreachable*** | Two very different user actions: turn on wifi, versus wait. Conflating them wastes the user's time | S |
| B7 | **Empty states for every list** — no members, no search results, no media in a chat | Each needs a real next action, not a shrug | S |
| B8 | **First-run experience** — what a brand-new account sees | Currently: an empty chat list and a button. There is no moment that explains what this app is | M |
| B9 | **Error taxonomy in three languages** — every `DomainError` code mapped to a sentence a person can act on | We have `DomainError` and human messages server-side, but the client shows raw server strings for some paths | M |

## C. Profile and settings

This is the biggest structural hole. There is no profile screen and no settings
screen at all — language is a sheet hanging off the app bar and sign-out is an
icon. Telegram's settings tree is the reference because it is the one this
audience already knows.

**Profile (yours)**

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| C1 | Avatar: set, crop, remove | The schema has `avatar_key` and nothing writes it. A messenger where everyone is a grey circle feels unfinished | M |
| C2 | Display name, bio | `display_name` exists; bio does not | S |
| C3 | **Username (@handle)** | The column exists and is unused. Critically important here: a user switching between a Tajik and a Russian SIM keeps one identity. Also the only way to be findable without giving out a phone number | M |
| C4 | Phone/email management — add a second identity, remove one | The model supports multiple identities per user; there is no UI. A migrant with two SIMs needs both | M |
| C5 | QR code for your profile, and a scanner | Solves the "paste a user id" problem *today*, without contact discovery's privacy work. Two people in a room can connect in five seconds | M |

**Profile (theirs)**

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| C6 | View another user: avatar, name, @handle, shared groups | There is nowhere to see who someone is | M |
| C7 | Block / unblock, report | Safety floor. Currently there is no way for a user to stop someone contacting them | M |
| C8 | Shared media grid for a chat | The universal "where was that photo" affordance | M |

**Settings tree**

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| C9 | **Settings screen at all**, with the standard sections | Language and sign-out are currently app-bar icons. That does not scale past three settings | M |
| C10 | Notifications: per-chat mute (1h / 8h / forever), preview on/off, sound | `chat_members.muted_until` exists in the schema and nothing sets it | M |
| C11 | **Data and storage** — see D-section market items; deserves top-level placement | For this audience it is arguably the most important settings page, not a footnote | M |
| C12 | Privacy: last seen, read receipts, who can add me to groups, who can find me by phone | Telegram's granularity is the expectation. Read receipts especially — in a family, "seen and not replied" starts arguments | L |
| C13 | Appearance: theme (night/day/system), text size, chat wallpaper | `themeMode` is hardcoded to dark. A day-mode user currently cannot get to it | S |
| C14 | Devices: list active sessions, revoke one, revoke all | Sessions are per-device in the schema and there is no way to see or kill them. This is a security floor, not a nicety | M |
| C15 | Storage: cache size, clear cache, per-chat storage usage, auto-delete media older than N | Media cache currently grows forever on a 16GB phone | M |
| C16 | Export chat history | Trust device, and the honest answer to "what if I stop using this" | M |
| C17 | About / FAQ — who runs Sakina, where the data lives, does it work from Russia | `docs/GROWTH.md` predicts these questions. Not answering them is a trust problem | S |

## D. Chat interactions — table stakes

Everything here exists in every messenger this audience already uses. Their
absence is what makes the app feel like a demo.

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| D1 | **Reply to a message** (quote + jump to original) | The single most-used feature in group chat. Without it, family groups are unreadable | M |
| D2 | **Forward** | The main vector by which a messenger spreads. Also the main vector by which misinformation spreads — needs a "forwarded" label from day one | M |
| D3 | **Edit** (with an "edited" marker) | `edited_at` exists in the schema and nothing writes it | M |
| D4 | **Delete** — for me / for everyone, with undo not confirm | `deleted_at` exists and nothing writes it. Undo per `UX.md` | M |
| D5 | **Reactions** | Cheap emotional bandwidth. In a family group of twelve it is the difference between 40 "ok" messages and none. Needs its own table and a compact wire representation | L |
| D6 | **Copy / select multiple / share out** | Basic and missing | S |
| D7 | **Drafts, persisted per chat** | You type half a message, switch chats, come back. Losing it is a small betrayal people remember | S |
| D8 | **Link previews** | Needs a server-side fetcher (never fetch from the client — it leaks the reader's IP to the link's host) | L |
| D9 | **Mentions (@) and mention-only notifications** | The thing that makes a 200-person group survivable | M |
| D10 | **Pinned messages** in groups and channels | Where a group puts its rules or an address | M |
| D11 | **Scroll-to-bottom button with unread count**, and jump-to-first-unread on open | Opening a busy group at the top with no way down is a common complaint | S |
| D12 | **Date separators and "unread" divider** in the message list | Currently messages run together with no temporal structure | S |
| D13 | **Voice messages** | `VoicePayload` has been in the protocol since the first commit and nothing records one. Arguably belongs in table stakes *and* in the market section: in a partly oral culture with a hard keyboard, voice is not a convenience, it is the primary input | L |
| D14 | **Emoji picker with recents**, plus a Tajik/Russian-aware search | The system picker is fine on iOS and poor on cheap Android | M |
| D15 | **Stickers** | `docs/COMPETITIVE-ANALYSIS.md` argues this is a primary revenue line for LINE and the cheapest cultural moat available. Tajik-specific sticker packs are the sort of thing people screenshot and share | L |

## E. Chat list and navigation

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| E1 | **Search** — messages, chats, people, in that order of difficulty | The most-missed feature once someone has 50 chats. Message search needs a local FTS index (SQLite FTS5) *and* an ICU-aware tokenizer for Tajik | L |
| E2 | **Pin a chat to the top** | The family group should not fall below a channel | S |
| E3 | **Archive** | The escape valve that stops a chat list becoming unusable | M |
| E4 | **Mark unread / mark read** | Small, universally expected | S |
| E5 | **Swipe actions on a list row** — archive, mute, pin | Expert speed without beginner cost | M |
| E6 | **Chat folders / tabs** (All, Personal, Groups, Channels) | Telegram's answer to list overload. Deferrable until users have enough chats to need it | L |
| E7 | **Bottom navigation** once there is more than one destination | Today there is one screen, so a bottom bar would be a lie. The moment Settings and Contacts exist, it is needed | M |
| E8 | **Contacts screen with phone-book matching** | The last piece that removes "paste a user id". Needs the privacy design in `ROADMAP.md` — hashed identifiers, never a plaintext address-book upload | XL |

## F. Media, beyond what is built

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| F1 | **Thumbnail generation** | The protocol field `thumb_key` exists and nothing fills it, so a photo in a list is the full photo. This is the highest-value gap in the whole media stack and it is a data-cost problem, not a polish one | M |
| F2 | **BlurHash or a 20-byte preview** in the payload | An instant, zero-fetch placeholder. Perfect for this network | M |
| F3 | **Resumable uploads** | A 40MB video on Tajik mobile data will be interrupted. Without resume, it starts over | L |
| F4 | **Multi-select send** — several photos at once, as an album | Sending twelve photos as twelve messages is what makes a family group unusable after a wedding | M |
| F5 | **Image editor** — crop, rotate, draw, caption | Table stakes, and a place to put a Tajik sticker overlay later | L |
| F6 | **Document preview** — PDF first page, at least | Currently a filename and a size | M |
| F7 | **GIF support and a search** | Deferrable; needs a third-party provider and that is a data and privacy decision | M |
| F8 | **Orphan sweep** — ticketed uploads never sent | `StorageProvider.remove` exists; the job that calls it does not. Cost problem, not user-facing | S |
| F9 | **Auto-download rules** — never / wifi only / always, per media type | Belongs in Data and Storage. The default must be "wifi only" for video | M |

## G. Notifications

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| G1 | **Per-chat mute**, honouring `muted_until` | Schema exists, nothing sets it | M |
| G2 | **Notification grouping and summary** — "3 new messages in Оила" | Currently every message is its own notification. A busy group is a phone that will not stop buzzing, and the fix people reach for is uninstalling | M |
| G3 | **Reply from the notification** | Android direct-reply and iOS quick actions. The single biggest reduction in time-to-reply | M |
| G4 | **Quiet hours** — a global schedule | See `DIFFERENTIATION.md`; there is a better version of this than the generic one | S |
| G5 | **In-app notification banner** when a message arrives for a chat you are not in | Currently nothing happens | S |
| G6 | **Badge count on the app icon** | Expected, and currently absent | S |
| G7 | **Notification preview control** — show sender / show text / show nothing | A privacy setting that matters when a phone is shared, which in this market it often is | S |

## H. Voice and calls

`docs/CALLS.md` has the design. None of it is built. This is M2 and the largest
single chunk of remaining work.

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| H1 | One-to-one voice calls (WebRTC, coturn already provisioned) | The reason many people install a messenger at all, especially for calling home | XL |
| H2 | Video calls | Same, plus grandparents seeing grandchildren, which is the whole emotional case for the product | XL |
| H3 | Group calls | Deferrable | XL |
| H4 | Call history in the chat as a message type | Fits the existing open message-type design | M |
| H5 | Low-bandwidth codec tuning and an audio-only fallback that engages automatically | On a Tajik mobile network, a call that degrades gracefully beats a call that drops | L |

## I. Trust, safety and privacy

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| I1 | **Block and report** | Absent. This is the floor, not a feature | M |
| I2 | **Report a channel/group**, with a moderation queue | A channel product without a report path is a liability the day it grows | L |
| I3 | **Rate limits on channel creation and joins** | Anti-spam. `ANTI-ABUSE.md` covers signup but not content | M |
| I4 | **Two-step verification (a password on top of the OTP)** | Email OTP alone means an email compromise is an account compromise | M |
| I5 | **Login alerts** — "a new device signed in" | Cheap, and the thing that catches an account takeover | S |
| I6 | **Session list with revoke** | Duplicate of C14; listed twice because it is both a settings feature and a security control | M |
| I7 | **Disappearing messages, per chat** | Expected by anyone who has used Telegram or Signal. Not a differentiator — see `DIFFERENTIATION.md` on why it should not be the headline | L |
| I8 | **The encryption decision** | `ARCHITECTURE.md` flags the tension between E2E and a regulated payments layer. It needs deciding rather than defaulting, and the answer shapes I7, cloud backup, and search | XL |

## J. Accessibility

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| J1 | **Screen-reader labels on every interactive element**, in all three languages | Currently tooltips exist on some icons and nothing else. A blind user cannot use this app today | M |
| J2 | **Semantic order and focus traversal** through the message list | Bubbles need to read as "from X, at 09:41, delivered" | M |
| J3 | **Contrast audit at the 1.6x text scale** in both themes | We check layout at scale; we do not check contrast at it | S |
| J4 | **Keyboard navigation** for the tablet and desktop layouts | Two-pane exists; nothing can be driven from a keyboard | M |
| J5 | **Large-touch mode** — see K5, elder mode, which subsumes this | | |

## K. The market — Tajikistan and the migrant corridor

These are not polish. They are the reasons someone chooses this over Telegram,
and several are listed again in `DIFFERENTIATION.md` where they rise to strategy.

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| K1 | **Data budget, visible** | Not a buried toggle: a number the user can see. For an audience paying by the megabyte, data is money, and no incumbent surfaces it because their users do not care | M |
| K2 | **Text-only mode** — a hard switch that refuses to fetch any media | The setting someone turns on for the last week of the month | S |
| K3 | **Aggressive compression profiles** tuned per network type | Sending a 300KB photo instead of 4MB is the difference between sending it and not | M |
| K4 | **Works-on-2G tuning** — timeouts, retry backoff, payload sizes | Much of the country is not on 4G. The protocol is already retry-safe; the constants are not tuned for it | M |
| K5 | **Elder mode** — larger targets, voice-first, fewer features on screen | A large share of the people being called are grandparents in villages. Every messenger fails them, and the family is the one who installs the app | L |
| K6 | **Tajik keyboard help** — ғ ӣ қ ӯ ҳ ҷ are missing from most default Cyrillic keyboards | A real, daily, physical friction that no international product will ever fix. Even a long-press hint row in the composer would be notable | M |
| K7 | **Transliteration search** — typing `salom` finds `салом` | Many users type Latin out of keyboard habit. Makes search actually work | M |
| K8 | **Remittance receipt as a message type** | `payment` is already reserved in the enum. Tajikistan is among the most remittance-dependent economies on earth, and "I sent it" is one of the most-sent messages in this corridor | L |
| K9 | **Russia-reachability engineering** — domain fronting, alternate transports, no single blockable endpoint | WhatsApp is blocked in Russia; assuming Sakina never will be is optimism, not a plan. This is architecture, and it is cheap now and expensive later | L |
| K10 | **Prayer times and Ramadan awareness** | See `DIFFERENTIATION.md` | M |

## L. Platform and infrastructure

| | Feature | Why | Effort |
| --- | --- | --- | --- |
| L1 | **Desktop / web client** | `apps/web` is a placeholder. Shared computers and internet cafés are still normal here | XL |
| L2 | **Multi-device sync of read state and drafts** | Sessions are already per-device; the state is not shared | L |
| L3 | **Cloud backup and restore** | The number-one reason people fear switching messengers is losing history | L |
| L4 | **Push via a non-Google path** | Huawei devices and de-Googled Androids are common in this market. FCM is not universal here the way it is in Europe | L |
| L5 | **App size budget** | Every megabyte is a barrier on a metered connection and a 16GB phone. Should be a tracked number with a CI check | S |
| L6 | **Crash and ANR reporting** | We have no idea what breaks on real devices, and cannot get one | M |
| L7 | **Feature flags** | Needed before any staged rollout | M |
| L8 | **Onboarding analytics** — funnel only, privacy-respecting, self-hosted | You cannot fix a signup funnel you cannot see. Must be self-hosted, or it contradicts the trust story | M |

---

## If I had to pick ten

In order, and the argument for the order is: first stop the app feeling broken,
then stop it feeling empty, then make it worth switching to.

1. **D1 Reply** — group chat is unreadable without it
2. **C9 Settings + C13 theme + C14 devices** — the app has nowhere to *be* configured
3. **F1 Thumbnails** — the largest unnecessary data cost in the product
4. **D13 Voice messages** — the primary input method for a large share of the audience
5. **A1/A2 Hero and send animations** — the two motions that make it feel built rather than assembled
6. **B1/B2 Skeletons** — 600ms of looking broken on every cold start
7. **G2 Notification grouping** — the current behaviour is an uninstall trigger
8. **C3 Usernames + C5 QR** — kills "paste a user id" without waiting for contact discovery
9. **I1 Block and report** — safety floor, and a store-review requirement
10. **K1 Data budget** — the cheapest thing that makes us visibly different

Everything in `DIFFERENTIATION.md` sits *after* these, deliberately: a
distinctive feature on top of an app that cannot reply to a message is a
distinctive broken app.
