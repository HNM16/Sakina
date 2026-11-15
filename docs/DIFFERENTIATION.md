# What makes it Sakina and not another Telegram

Research only. Nothing here is built, and several of these should never be.

[`BACKLOG.md`](BACKLOG.md) is the list of things that make the app *complete*.
This is the list of things that make it *chosen*. They are different problems
and the second one is harder, because completeness has a known answer and
distinctiveness does not.

---

## The pigeon question

There is a genre of messaging app built on artificial delay. The best-known
serious one is Slowly, where a letter travels at a simulated speed based on the
real geographic distance between sender and recipient — Dushanbe to Moscow takes
hours. There are novelty versions where the message is carried by a cartoon
pigeon that occasionally dies in transit and the message is lost.

These work, and it is worth being precise about *why* they work, because copying
the surface would be a mistake.

**The mechanic is manufactured scarcity.** Instant messaging made a message cost
nothing to send, and things that cost nothing to send stop being worth much to
receive. A pen-pal app puts the cost back: you wait, so you write something worth
waiting for. The delay is not the feature. The *care* the delay forces is the
feature. The pigeon dying is the same trick turned up — a message that might not
arrive is a message you choose your words for.

**Now the important part: Sakina's users do not need scarcity manufactured for
them.** They have it. A construction worker in Yekaterinburg with 200MB left in
the month and a two-hour time difference from his daughter in Kulob is already
living inside the constraint that Slowly simulates. Selling him simulated
distance would be, at best, tone-deaf.

So the move is not to copy the gimmick. **It is to invert it.** Every idea in
Tier 1 below comes from one reframe:

> Instant messengers treat distance as a problem to erase. Sakina's users cannot
> erase it. The opportunity is to make real distance *felt as connection* rather
> than as absence — to design for the separation instead of pretending it away.

That reframe is defensible in a way a pigeon is not, because it comes from the
audience rather than from a mood.

---

## How to judge a candidate

Six tests. An idea that fails 4, 5 or 6 should be cut regardless of how it
sounds in a pitch.

1. **Does it survive a 2G connection and a 16GB phone?** If it needs bandwidth we
   do not have, it is a feature for a different market.
2. **Would somebody describe it to another person?** At 5–10k users, word of
   mouth is the only channel that matters. A feature nobody can explain in one
   sentence does not get explained.
3. **Does it get better when a whole family uses it?** Group value beats solo
   value here. The unit of adoption is a household, not a person
   (`docs/GROWTH.md`).
4. **How long would Telegram need to copy it?** If a sprint, it is not a moat —
   though it can still be worth building for the users we get before then.
5. **Is it quiet?** `docs/BRAND.md`: the chrome stays still so the content can be
   loud. A feature that shouts is off-brief no matter how clever.
6. **Is it honest?** Does it solve a problem the user actually has, or does it
   manufacture one so we have something to solve? **This is the pigeon test**,
   and it is the one most novelty features fail.

---

## Tier 1 — distinctive and load-bearing

### 1. Нома — the letter

**What.** A second message mode alongside chat. You compose a long message over
hours or days (kept as a local draft), and send it once. It arrives as a letter:
its own view, its own typography, an opening ritual. Deliberately missing from
this mode: typing indicators, read receipts, "last seen", and any pressure to
reply quickly. A letter can be replied to with a letter, days later, and that is
the expected rhythm rather than a failure.

**Why.** This is Slowly's real insight applied to people who actually live it. A
migrant worker gets twenty minutes on a Sunday. Chat's rhythm punishes that: he
opens the app to forty unanswered messages and the accumulated guilt of not
having replied for a week. Nothing about a chat interface says "it is fine that
you were away." A letter's rhythm says exactly that — nobody feels bad about
taking three days to answer a letter. **We would be removing the pressure that
instant messaging created, for the people it hurts most.**

It also inverts the pigeon precisely: no artificial delay, no fake pigeon. The
delay is the one that already exists in these people's lives, and the app stops
treating it as a fault condition.

Cheap, too. It is a message type, a different renderer, and *suppressing* signals
we already send.

**Against it.** Two modes is a concept to teach, and concepts are expensive. It
risks being used once and forgotten. Mitigation: do not launch it as a mode —
launch it as what happens when you write past a few hundred characters, and let
the app offer it.

**Tests:** 1 ✅ (text is tiny) · 2 ✅ · 3 ✅ · 4 — hard to copy because Telegram's
whole product is built on immediacy · 5 ✅ (the quietest thing here) · 6 ✅

---

### 2. Ҳастам — the presence beacon

**What.** A one-tap signal, roughly fifty bytes, that says one of a handful of
things: *I'm home. I'm fine. I've arrived. Good night.* It is not a message — it
is a state that shows against your name in the people who care about you. No
text, no thread, no reply expected.

**Why.** The deepest anxiety in a split family is not a shortage of conversation.
It is not *knowing*. Did he get there. Is she alright. Is the bus in. A phone
call to ask costs money and a message asking "are you okay?" carries an
implication nobody wants to make explicit.

WhatsApp's "last seen" accidentally serves this need, which is why people watch
it obsessively and why it feels like surveillance — it is information leaked
rather than offered. **The same information, offered deliberately and mutually,
stops being surveillance and becomes care.** That reframing is the whole idea.

And it is the cheapest thing anyone can send on a metered connection, which
matters strategically: it is a reason to prefer us that is *created by* the
constraint our competitors ignore.

**Against it.** Presence features become obligations — "you didn't beacon me" is
a real failure mode, and in a controlling relationship it is worse than that. It
must be per-person, revocable silently, and never show a history. Design this one
with someone who understands the coercive-control risk before writing code.

**Tests:** 1 ✅ (bytes) · 2 ✅ · 3 ✅ · 4 — easy to copy, but nobody has, because
their users do not have the problem · 5 ✅ · 6 ✅

---

### 3. The data budget, on the surface

**What.** Not a "data saver" toggle in settings. A number the user can look at:
*34 of 200 MB this month.* Per-chat breakdown. A projection of what the video you
are about to send will cost. A one-tap "text only until payday."

**Why.** For this audience data is money and the anxiety is constant and
specific. No major messenger surfaces it, because their users genuinely do not
care — which is exactly why it is available to us. It converts our hardest
constraint into our most visible advantage, and it is *explainable in one
sentence*, which test 2 says is the whole game at this size.

There is a second-order effect worth naming: a user who can see the cost of media
will send less of it, which lowers our storage and egress bill. The interests
line up, which is rare.

**Against it.** Measuring per-chat data attribution accurately is fiddly. An
approximate number that is visibly wrong is worse than none.

**Tests:** 1 ✅ · 2 ✅ · 3 ➖ (solo value) · 4 — a sprint to copy, but strategically
uninteresting to them · 5 ✅ · 6 ✅

---

### 4. Пайк — carry a message for someone else

**What.** Store-and-forward over Bluetooth/Wi-Fi Direct. Your phone holds an
encrypted, sealed message for a stranger and hands it on when it meets a phone
with signal. Prior art: Briar, Bridgefy, FireChat.

**Why.** There are places in this country where this is the *only* thing that
works — Pamir valleys, the Anzob tunnel, the border queue at Oybek where
thousands of people wait for hours with no signal and one thing on their mind,
which is telling someone at home where they are.

And it is a story. "The app that works in the mountains" is the kind of sentence
that gets repeated, which is test 2 in its strongest form. The Pamirs are also
exactly where the chorkhona in our own logo comes from, which is a coherence you
cannot buy.

**Against it.** This is the hardest thing on the list by a wide margin. Battery
cost, an entirely separate trust and encryption model (you are asking phones to
carry strangers' data), abuse potential, and platform restrictions on background
Bluetooth that get tighter every OS release. It should be scoped as a research
spike, not a feature — and probably as a *separate, optional* capability rather
than something in the main path.

**Tests:** 1 ✅ (works with *no* network) · 2 ✅✅ · 3 ✅ · 4 — very hard to copy ·
5 ✅ · 6 ✅

---

## Tier 2 — culturally specific, high affinity, low cost

These will not carry the product alone, but each one signals "this was built for
you, by someone who knows" — and that signal is worth more here than a feature
comparison.

### 5. Namoz-aware quiet

Prayer times computed on-device from location (no network call, no location
leaving the phone). Notifications hold during the prayer window and deliver
after. Optionally, a shared quiet state so a family knows why someone is not
replying.

**Why.** Millions of people in this audience pray five times a day and every
messenger they use is oblivious to it. This is the definition of a detail that
says *we know who you are*. It is also literally what the app's name means:
sakina is tranquility, and holding the phone still during prayer is the name
taken seriously.

**Against it.** Religious features must be opt-in and must never assume. Get the
calculation method right — there are several madhabs with different conventions,
and a wrong time is worse than no feature.

### 6. Time-zone-aware sending

Sakina knows the recipient's local time. Sending at 02:00 their time offers:
*deliver now, or at 07:00?*

**Why.** The Dushanbe–Moscow gap is two hours; Dushanbe–Vladivostok is five the
other way. Waking a parent at 2am is a real and frequent harm, and every
messenger makes it easy. This is the single cheapest idea on this page and one of
the kindest.

### 7. Navruz and Eid time capsules

Write a message now for delivery on a specific date. Aimed squarely at the
festivals that matter here.

**Why.** Navruz is *the* moment of the year in this culture, and it is when the
diaspora most wants to reach home. A message written in a quiet moment in
February and delivered on 21 March is a better message than one typed in a rush
on the day. This is the pigeon's anticipation mechanic, honestly earned — the
delay is chosen by the sender for a reason, not imposed by a cartoon bird.

### 8. Elder mode

A whole-app switch: larger targets, voice-first composition, three features on
screen instead of thirty, no swipe gestures.

**Why.** A very large share of the people being *called* are grandparents in
villages, often on their first smartphone. Every messenger fails them, and the
person who installs the app is usually a grandchild who will choose whichever one
their grandmother can actually use. This is a growth feature disguised as an
accessibility feature.

### 9. Тоҷикӣ keyboard help

The six characters ғ ӣ қ ӯ ҳ ҷ are absent from most default Cyrillic keyboards,
so people substitute Russian letters and their own language degrades on screen.
Even a long-press row above the composer would be notable.

**Why.** It is a daily physical friction that no international product will ever
bother to fix. It costs almost nothing. And it is upstream of everything else we
have already committed to — `CLAUDE.md` says fonts are chosen on those six
characters; it would be strange to render them beautifully and leave people
unable to type them.

---

## Tier 3 — worth exploring, unproven

- **On-device voice transcription.** Send text instead of audio when bandwidth is
  bad; make voice notes searchable. Russian ASR is good enough today; **Tajik is
  not, and pretending otherwise would be dishonest** — treat Tajik as a research
  item, not a feature.
- **Remittance receipts as a message type.** `payment` is already reserved in the
  enum. Tajikistan is among the most remittance-dependent economies in the world,
  and "I sent it" is one of the most-sent messages in this corridor. The obvious
  M4 on-ramp, but it needs a licensed partner and years of regulatory work — see
  `ARCHITECTURE.md`.
- **Village and mahalla channels.** Hyper-local channels keyed to a real place.
  Strong community fit, and a serious moderation liability. Do not ship without
  I2 from the backlog.
- **Shared family album.** A group's photos as an album rather than a scroll,
  with the elder-friendly framing. Competes with the message list for attention,
  so it must not become a feed.

---

## What we should not build, and why

Being explicit about the rejections is most of the value of a document like this.

- **A literal pigeon.** Cute once, uninstalled twice. Fails test 6 outright: it
  manufactures a problem for people who have the real version. Also fails test 5
  — a bird animation is the loudest possible chrome.
- **Messages that can be lost on purpose.** The pigeon's death mechanic. Our
  entire protocol design — gapless `seq`, idempotent retries, offline catch-up —
  exists to make delivery *trustworthy* on a network that is already unreliable.
  Deliberately losing a message would be undoing our best engineering as a joke,
  in a market where "did it arrive?" is a genuine daily anxiety.
- **Stories / a feed.** Telegram and WhatsApp both have them and we would lose
  that race on content volume. It also directly contradicts "a quiet app so the
  conversation can be loud."
- **An AI assistant bolted into the chat list.** Every messenger is doing it, it
  is expensive per user, it needs a network round trip this audience cannot
  afford, and it answers no question anyone here is asking. (On-device
  transcription is different: it is a tool, not a personality.)
- **Crypto, tokens, or an NFT anything.** The payments story here is remittances
  and utility bills through a licensed partner. Anything else is regulatory
  suicide in a country where the National Bank is not relaxed about this.
- **Disappearing messages as the headline.** Build it (backlog I7) — it is
  expected. But positioning on privacy invites a comparison with Signal that we
  lose, and it invites a conversation with a government we would rather have
  later than earlier.
- **Gamification — streaks, points, badges.** Duolingo's mechanics on a family
  conversation would be grotesque. A streak turns talking to your mother into a
  chore with a score.
- **A crowded super-app launcher on day one.** The super-app is the destination
  (`ARCHITECTURE.md`), and the mini-app grid is what it looks like *after*
  people already open the app daily. Shipping the grid first is how you get an
  app that does eleven things badly.

---

## The one-sentence version

If Sakina is going to be described by one person to another, the sentence should
be something like:

> *It's the one that works when you have no signal and no data left, and it
> doesn't make you feel bad for not replying.*

Which is Tier 1, items 1 through 4. Everything else is support.

---

## What to do next with this

None of it, yet. The ten items at the end of [`BACKLOG.md`](BACKLOG.md) come
first, and the argument is simple: a distinctive feature sitting on top of an app
that cannot reply to a message is a distinctive broken app. Reply, settings,
thumbnails and voice notes are worth more than any idea on this page.

The two things worth doing *now*, because they are cheap and they inform
everything else:

1. **Talk to twenty people in the corridor** — ten in Russia, ten at home. Ask
   what they do when they run out of data, and what they do when they cannot
   reach someone. Do not ask them what features they want; nobody can answer
   that. Items 1, 2 and 3 above are hypotheses drawn from published market facts
   and they need contact with actual people before anyone writes code.
2. **Reserve the protocol space.** `letter` and `beacon` as message types cost
   nothing to add to the enum today and are awkward to retrofit later — the same
   reasoning that already put `payment` and `service_card` in there before a line
   of payments code existed.
