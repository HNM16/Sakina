# One person, one account

Email sign-in exists because the team cannot receive +992 SMS from outside
Tajikistan. It unblocks building, and it costs something real: **email is a far
weaker identity than a phone number.**

A phone number is scarce. It costs money, it needs a SIM, and one person
realistically controls a handful. An email address costs nothing and takes
fifteen seconds. Worse, a single mailbox can be *written* an unbounded number of
ways, and every variant reaches the same inbox:

```
nekruz@gmail.com
ne.kruz@gmail.com
n.e.k.r.u.z@gmail.com
nekruz+beta@gmail.com
NEKRUZ@GoogleMail.com
```

Five addresses, one person, one inbox. Store the raw string and that is five
accounts. At that point "we have 10,000 users" means nothing, group membership
can be stuffed, and any future invite or referral mechanism is free money.

Three layers, in order of how much they actually help.

---

## Layer 1 — canonicalisation

`packages/core/src/identity.ts`

Every address is reduced to one canonical form, and the unique index is on that
form, not on what was typed. The raw string is still stored for display, because
showing someone a mangled version of their own address is its own usability bug.

The rules are **per provider**, and that is the important part:

| Rule | Applies to | Example |
| --- | --- | --- |
| Lowercase everything | all | `NEKRUZ@GMAIL.COM` → `nekruz@gmail.com` |
| Strip `+tag` | providers that support it | `nekruz+beta@gmail.com` → `nekruz@gmail.com` |
| Strip dots | **Gmail only** | `ne.kruz@gmail.com` → `nekruz@gmail.com` |
| Dot ≡ hyphen | **Yandex only** | `ne.kruz@yandex.ru` → `ne-kruz@yandex.ru` |
| Alias domains | Gmail/Yandex/Proton/Outlook/iCloud families | `@googlemail.com` → `@gmail.com`, `@ya.ru` → `@yandex.ru` |

**Why per provider and not globally.** Dots are meaningless at Gmail and
meaningful nearly everywhere else. Stripping them globally would merge
`a.b@company.com` and `ab@company.com` — two different colleagues — into one
account, locking one of them out permanently. Over-normalising is a worse failure
than under-normalising, because it produces a support case that cannot be fixed
without manual database surgery.

**Why Yandex and Mail.ru get first-class treatment.** They are more common than
Gmail among this audience, and Yandex in particular serves one mailbox under
yandex.ru, yandex.com, ya.ru, yandex.by, yandex.kz, yandex.uz and yandex.com.tr.
An implementation that only knows about Gmail would miss most of the duplicates
that actually occur here.

**Disposable domains** are refused outright — mailinator, tempmail, guerrillamail
and the rest. The built-in list is a floor, not a solution: these services add
domains faster than any hard-coded list tracks. Put a maintained list behind
`DISPOSABLE_EMAIL_DOMAINS` before opening registration.

### What this layer cannot do

**It cannot tell that a Gmail account and a Yandex account belong to the same
person.** Those are two genuinely different mailboxes. No amount of string
handling will ever connect them, and any product decision that assumes otherwise
is wrong. Canonicalisation removes the *free* duplicate — the lazy one, the one
someone gets by typing a dot. It does not remove the deliberate one.

---

## Layer 2 — cost per account

`packages/core/src/repo/signup.ts`

Since duplicates cannot be detected perfectly, make them expensive.

- **Per device.** `MAX_SIGNUPS_PER_DEVICE` (default 3, per 24h). One handset
  creating twenty accounts is the actual attack, and this stops it. Three rather
  than one because shared family phones are normal here.
- **Per network.** `MAX_SIGNUPS_PER_IP` (default 20, per 24h). A backstop, not a
  primary defence: Tajik ISPs put many subscribers behind CGNAT, and a university
  lab is one address. Set it too tight and you block a real cohort.
- **Resend cooldown.** `OTP_RESEND_COOLDOWN_SECONDS`, keyed on the canonical
  identity — so the cooldown itself cannot be sidestepped with a dotted variant.

Only *signups* are limited, never sign-ins. Someone returning on a new phone, or
a family sharing one, must not be blocked by a limit aimed at farming. The check
runs after the server knows whether the address is new.

IP addresses are stored **hashed**. The counters need to compare addresses, not
read them; keeping plaintext would be collecting personal data for no purpose.

---

## Layer 3 — invites

`REQUIRE_INVITE=true`

The strong one. An account has to be vouched for by an existing account, and each
member holds a small number of invites (`INVITES_PER_USER`, default 5). Codes are
single-use by default and claimed under a row lock, so a code pasted into a group
chat cannot be redeemed twice by everyone tapping at once.

Codes avoid `0`, `O`, `1`, `I` and `L`, because they get read aloud and typed
from screenshots.

This is the layer that actually holds, and it is nearly free to run at this size.
It is also the growth mechanism — see `docs/GROWTH.md`. A thing people have to
ask to get into spreads better than an open signup form, and invites travel along
real relationships, which is exactly the shape adoption needs.

**Recommendation: run invite-only through the whole beta.** Turn it off only when
phone verification is live.

---

## Reserved test identities

`TEST_IDENTITIES="qa@sakina.tj:000000"`

Fixed identity/code pairs that skip delivery in **every** environment, production
included. This is not a development shortcut to strip before launch — App Store
and Play reviewers cannot receive a Tajik SMS either, and an account they cannot
sign into is a rejected app. Firebase Auth ships the same mechanism for the same
reason.

It bypasses *delivery*, never *verification*:

- an explicit allowlist, never a pattern or prefix rule;
- the code is still checked, in constant time — a reserved identity with the
  wrong code is refused exactly like any other;
- comparison is against the canonical form, so a reserved address cannot be
  reached through a variant that skipped normalisation;
- their presence is logged loudly at boot rather than left to be found in a
  config file.

Separately, `OTP_DEV_MODE` returns the code in the HTTP response and registers a
`/v1/auth/dev/inbox` route for testing on a real handset. The API **refuses to
boot** with it enabled when `NODE_ENV=production`, so in production that route
does not exist at all rather than existing and being guarded.

---

## The real answer, later

Phone verification. Everything above is containment for a stopgap.

When there is a Tajik SMS arrangement — or Telegram Gateway at roughly $0.01 per
code, which works from anywhere today with no operator contract — phone becomes
the primary identity and email demotes to a recovery method. The schema already
supports it: `identities` holds many rows per user, and `linkIdentity` attaches a
phone to an existing account without touching anything else.

That is also when contact discovery becomes possible, which is when the app stops
feeling empty. Do the privacy design first — Signal's private contact discovery
is the reference, and "upload the address book in plaintext" is the default
everyone regrets, especially in a country where who-knows-whom is sensitive.

---

## Verifying it

```bash
node services/api/scripts/auth-smoke.mjs
```

15 checks: every Gmail and Yandex variant resolving to one account, non-Gmail
dots staying distinct, disposable refusal, reserved-identity containment, and the
per-device ceiling. Run it after any change to the auth path.
