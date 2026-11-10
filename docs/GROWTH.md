# Getting to 10,000 users

The target is 5,000–10,000 real users. That number is small enough to reach
without a marketing budget and large enough to prove the product works — but only
if it is the *right* 10,000. Ten thousand people scattered across a country who
each have two contacts on the app is a dead app. A messenger's value is entirely
in whether the people you want to talk to are on it.

**So the operating principle: never recruit individuals. Recruit closed groups.**

One university faculty, one company, one neighbourhood football club, one
migrant community from one district. Inside a closed group, adoption compounds —
each new member makes it more useful for everyone already there. Across a
scattered user base it does the opposite. Fifty groups of two hundred beats ten
thousand strangers, and it is easier to get.

This is why signup is invite-gated by default (`REQUIRE_INVITE=true`). Invites
travel along real relationships, which is exactly the shape adoption needs.

---

## What we are actually selling

Not "a Tajik messenger." ORIZ already occupies that slogan, launched in November
2025 with the government behind it, and does not work (see
`docs/COMPETITIVE-ANALYSIS.md`). Repeating the pitch invites the comparison and
the shrug.

The three claims that are true and that nothing else in the market offers
together:

1. **It works when your connection does not.** Messages send on a bad line and
   arrive when it comes back. This is a real technical property of the build, not
   a slogan — and it is the property imo, Zalo and Telegram each won on.
2. **It reaches Russia.** WhatsApp has been fully blocked there since February
   2026 and Telegram is throttled. Most Tajik families have someone in Russia.
   Right now their main channel is broken.
3. **It is in Tajik.** Properly — not a machine translation with broken plurals.
   The interface, the error messages, the stickers, the humour.

Claim 2 is the wedge. Claims 1 and 3 are why people stay.

---

## Phase 0 — before any users (2–4 weeks)

Nothing below works if the app is not ready. Zalo's own account of how they beat
Facebook is "speed, reliability, minimal features." That is the whole strategy.

Non-negotiable before the first invite goes out:

- **Group chats.** Nobody migrates a one-to-one conversation. Groups are the
  atomic unit of adoption, and everything in this document assumes them.
- **Push notifications.** A messenger that does not notify is not a messenger.
- **Images and voice messages.** Voice matters disproportionately here: it works
  across literacy levels and it is how the region actually communicates.
- **Tajik stickers.** See below — this is not a nice-to-have.
- **It has to be fast on a 40 USD Android.** Test on the cheapest handset you can
  find, not on a flagship.

**Stickers deserve their own line.** LINE built a business on them — 510M sent
per day — and they are the cheapest cultural moat available. Tajik-language
packs, Navruz sets, local humour, recognisable Dushanbe references. A local
illustrator, twenty packs, a few hundred dollars. WhatsApp cannot match them
because it will never bother. This is the feature that makes people say *this one
is ours*, and it is worth more than any feature-parity item on the roadmap.

---

## Phase 1 — the first 100 (weeks 1–4)

**Goal: prove people talk to each other on it, not that they installed it.**

Seed manually. The founder's own circles — the university cohort, the company,
the gym, the family. Hand out invites in person, install the app on their phone
yourself, watch them use it for two minutes. That two minutes will teach more
than any analytics dashboard.

Pick **three seed groups** and get each to genuinely switch:

- one university group (a course cohort or a faculty — the Slavonic University
  cohort is the obvious first)
- one workplace
- one family with members in Russia — this is the test of claim 2

Success is not 100 installs. Success is **three groups where the daily
conversation has actually moved**, measured as: does the group still have traffic
on day 14 without anyone being reminded?

If a group goes quiet, ask why and fix it before recruiting another. A group that
churns has told you something no amount of marketing will fix.

## Phase 2 — 100 → 1,000 (months 2–4)

Now the invite tree does the work. Each member gets 5 invites
(`INVITES_PER_USER`). Scarcity is doing two jobs: limiting abuse, and making
membership feel like something rather than nothing.

Channels that fit this market specifically:

- **University campuses.** Tajik National University, the Slavonic University,
  the Technical University, the Medical University. Student groups are dense,
  online constantly, and price-sensitive about data. Sponsor nothing; just get
  one course group to switch and let the timetable spread it.
- **Telegram channels.** The existing content ecosystem is on Telegram. Do not
  fight it — recruit from it. Tajik-language channels with a few thousand
  subscribers will run a post cheaply, and their audience is already the
  messaging-native crowd.
- **Instagram and TikTok in Tajik.** Short videos of the app working on a bad
  connection. The demo that lands: airplane mode, send a message, turn the radio
  back on, watch it deliver. That is a fifteen-second video and it is the whole
  product claim.
- **Migrant communities in Russia.** Moscow, St Petersburg, Yekaterinburg,
  Novosibirsk. Community WhatsApp and Telegram groups, землячество associations,
  and the physical places — money transfer offices, halal shops, mosques. This is
  the highest-intent audience in the world for claim 2, and almost nobody is
  competing for it.
- **Football and gyms.** Amateur teams are perfect closed groups: fixed roster,
  constant logistics chatter, a captain who decides where the group lives.

What to avoid: paid app-install ads. They buy exactly the scattered individuals
this plan is designed not to recruit, and the retention will be dismal.

## Phase 3 — 1,000 → 10,000 (months 4–9)

At a thousand users the loop should be self-sustaining. What changes:

- **Open registration selectively.** Consider dropping `REQUIRE_INVITE` per
  domain first — e.g. allow anyone with a university address
  (`ALLOWED_EMAIL_DOMAINS`) before opening entirely.
- **Move to phone signup.** By now there should be a Tajik SMS or flash-call
  arrangement, or Telegram Gateway at ~$0.01/code. Email was always the stopgap;
  phone is what makes contact discovery work, and contact discovery is what makes
  a messenger stop feeling empty.
- **Contact discovery, with the privacy design done first.** Signal's approach is
  the reference. Do not upload plaintext address books — in a country where
  who-knows-whom is sensitive, that is both an ethical and a trust problem.
- **Channels.** Let the Telegram channel operators you recruited from run a
  Sakina channel too. Copy Telegram's revenue share when there is revenue to
  share; creators go where they get paid.
- **Regional groups.** Khujand, Bokhtar, Kulob. Dushanbe-only is a failure mode —
  the second city always feels like an afterthought and behaves accordingly.

---

## Measure these, ignore the rest

Installs and registered users are vanity numbers, and the invite system means
they will look good regardless. What matters:

| Metric | Why | Target at 10k |
| --- | --- | --- |
| **D7 / D30 retention** | The only real verdict | D7 > 40%, D30 > 25% |
| **Median contacts per user** | Below ~3 the app is empty and they leave | > 5 |
| **% of users in an active group** | Groups are what retain | > 70% |
| **Messages per active user per day** | Real use vs. a checked box | > 20 |
| **Invite acceptance rate** | Whether people vouch for it | > 30% |
| **Message delivery success on first attempt** | Claim 1, measured | > 99% |
| **Cold start to chat list** | On a cheap Android | < 2s |

The one to watch hardest is **median contacts per user**. It is the metric that
tells you whether you are recruiting groups or individuals, and it is the
difference between a messenger and a directory of strangers.

---

## Things that will go wrong

- **The graveyard problem.** Someone installs, sees an empty chat list, and never
  returns. Mitigation: never let anyone finish signup without at least one
  conversation. Invites should carry the inviter, and the first screen after
  signup should be a chat with the person who invited them — not an empty list.
- **Group migration stalls.** A group moves, two members do not follow, the
  conversation moves back. Mitigation: recruit the group's *organiser*, not its
  members. Every group has one person who decides where it lives.
- **One bad week kills it.** At this size reputation is a single conversation.
  An outage, a lost message, a crash on a popular phone model — any of these will
  be discussed in every group at once. Reliability is the marketing.
- **Being mistaken for ORIZ, or for a state project.** Users will ask who is
  behind this and where the data goes. Have a straight answer ready, publish a
  real privacy policy, and do not hide the team. The distinction from a state
  messenger is the position; it has to be legible.
- **Zalo's stumble.** They won Vietnam on being the pleasant local option and
  then fell out of the top 200 in early 2026 on policy changes and user
  frustration. Whatever gets added later — ads, monetisation, integrations —
  the moment the app becomes annoying, the local advantage inverts.

---

## Budget

Realistically achievable at 5–10k users with almost nothing:

| Item | Approximate |
| --- | --- |
| Server (Hetzner or equivalent) | $40–80 / month |
| Domain, TLS, object storage | $20 / month |
| Email OTP (Resend free tier → paid) | $0–20 / month |
| SMS or Telegram Gateway at 10k users | ~$100 one-off at $0.01/code |
| Sticker illustration, ~20 packs | $300–800 one-off |
| Telegram channel posts | $50–200 per post |
| **Total to 10k** | **well under $3,000** |

The expensive input is time spent in rooms with the groups you are recruiting.
There is no way to buy that, and it is also the part that produces the feedback
that makes the product good.
