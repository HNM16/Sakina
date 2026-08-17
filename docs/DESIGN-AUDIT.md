# Design audit

Run of the `design-tells` skill (`.claude/skills/design-tells/`) in AUDIT mode
across every surface in the repo. Findings only — nothing here has been fixed.

The skill's premise is worth restating, because it changes what counts as a
finding: *the tells are symptoms, the disease is undeclared defaults.* Every
entry below resolves to one question — **did the content produce this choice, or
did the choice arrive on its own?** "Justified" is a real verdict, and several
entries have it.

No score is produced, and none will be. Guardrail G18 forbids it, correctly: a
number would imply a threshold at which a page stops reading as generated, and
there isn't one.

---

## Scope

| Surface | Bucket (G10) | Depth |
| --- | --- | --- |
| `apps/web` | **undecided — needs a decision, see the end** | full read |
| `apps/mobile` | convention by strategy | temperature only |
| `tools/dev-client` | internal test harness | Category D only |
| `docs/` + `docs/brand/` | editorial | full read |

`apps/web/components/ui/**` is stock shadcn, unmodified and almost entirely
unimported by the one page that exists. Guardrail G16 says the library's tells
live in its tokens, so it is audited at the token level and not file by file.
The scanner's 60-odd hits in there are noise.

---

## Findings

### The one that matters

```
FINDING   Two Sakinas
WHERE     apps/web/app/page.tsx:88 vs docs/BRAND.md
CATEGORY  A
VERDICT   Default
WHY       The repo's only web page renders the word "Sakina" in cyan neon with
          fireworks and a pulsating heart, while docs/BRAND.md defines Sakina as
          firuza on night and states the thesis as "a quiet app so the
          conversation can be loud" — one name, two identities, neither aware of
          the other.
FIX       Needs a decision, not a patch. See "Only you can decide" below.
BLAST     Everything or nothing in apps/web. Zero elsewhere.
```

### Integrity and safety — fixed first, per the skill

```
FINDING   No reduced-motion path anywhere in apps/web
WHERE     apps/web — site-wide (parallax-background.tsx:40-85, page.tsx:46-70,
          pulsating-heart.tsx, fireworks.tsx)
CATEGORY  D
VERDICT   Integrity
WHY       Twenty particles, two orbs, two glowing lines and a heart all animate
          on `repeat: Infinity` with no `prefers-reduced-motion` branch, which
          hard invariant 3 and guardrail G2 both reject outright.
FIX       Gate the infinite loops behind a reduced-motion check and disable
          transform/opacity animation rather than merely shortening it. framer-
          motion's `useReducedMotion()` is the least invasive route.
BLAST     4 components. Presentation only. No layout change.
```

```
FINDING   lang="en" on entirely Russian content
WHERE     apps/web/app/layout.tsx:19
CATEGORY  D
VERDICT   Integrity
WHY       Every word on the page is Russian; a screen reader will pronounce it
          with English phonemes, and G14 covers exactly this class of semantic
          damage.
FIX       `lang="ru"`. One attribute.
BLAST     1 line.
```

```
FINDING   Analytics with no privacy policy
WHERE     apps/web/package.json:41 (@vercel/analytics 1.3.1),
          layout.tsx:22 — no route matching privacy
CATEGORY  D
VERDICT   Integrity
WHY       The site genuinely collects data, so this is a real D3 rather than a
          missing-checkbox finding.
FIX       Per G4, a clearly-labelled DRAFT derived from an actual inventory of
          what is collected, never presented as final, plus an explicit list of
          the facts only a person can supply: legal entity, jurisdiction,
          retention, whether GDPR applies to Tajik and EU visitors.
          Alternatively, drop the analytics — a personal letter does not need
          them, and removing the collection removes the obligation.
BLAST     Needs a user decision before anything is written.
```

### Defaults

```
FINDING   The page announces its own generator
WHERE     apps/web/app/layout.tsx:7-11
CATEGORY  A
VERDICT   Default
WHY       `title: 'v0 App'`, `description: 'Created with v0'`,
          `generator: 'v0.app'` — the browser tab, the search result and the
          share preview all currently say the page was generated. This is the
          most literal possible instance of an undeclared default.
FIX       Real metadata. Whatever the page becomes, it has a name.
BLAST     1 file, 3 lines. Improves SEO and share previews immediately.
```

```
FINDING   Geist sans and mono
WHERE     apps/web/app/layout.tsx:2-3, globals.css:43-44
CATEGORY  A
VERDICT   Default
WHY       The face that ships with the v0/Vercel starter, named in tell A1.
FIX       Only if apps/web becomes a product surface. Then: Noto Sans, for the
          reason in BRAND.md — Tajik Cyrillic needs ғ ӣ қ ӯ ҳ ҷ, and the
          existing page is Russian, so coverage is a live constraint, not a
          preference. Verify licensing per G5 before specifying anything else.
BLAST     Token-level: every component.
```

```
FINDING   Neon cyan as the whole palette
WHERE     apps/web/app/globals.css:46-73, fireworks.tsx:17,
          pulsating-heart.tsx:42
CATEGORY  A
VERDICT   Default
WHY       `#00d9ff` is the sole accent, the fireworks cycle
          `#00d9ff / #00ffaa / #ff00ff / #ffaa00`, and the CSS comment above the
          block reads "Luxury Tech Color Palette" — generator vocabulary
          describing colour assigned by generator, which is tell A8 exactly.
FIX       Derive from the subject. If the page stays a personal letter the
          subject is the letter, not "luxury tech". If it becomes Sakina's site,
          BRAND.md already did this work and G8 says it wins.
BLAST     Token-level. Re-check contrast in both themes afterwards (G1, G12).
```

```
FINDING   Radial blur orbs
WHERE     apps/web/components/parallax-background.tsx:63, 75
CATEGORY  A
VERDICT   Default
WHY       Two `w-96 h-96 rounded-full blur-3xl` divs — tell A9, atmosphere
          applied to carry a composition that is otherwise five paragraphs of
          text.
FIX       The letter is the content and it is genuinely personal; give it
          presence typographically instead. Also costs GPU on scroll (G6).
BLAST     1 component.
```

```
FINDING   Two conflicting radius tokens
WHERE     apps/web/app/globals.css:31 (0.625rem) and :75 (0.5rem)
CATEGORY  A
VERDICT   Default
WHY       Both define `--radius` at root scope, so one silently loses and the
          whole `radius-sm/md/lg/xl` scale derives from whichever wins. Two
          sources of truth for one token is the shadcn default surviving
          alongside a half-made edit.
FIX       Delete the dead one. Then decide whether a single radius is a scale or
          just the library's stock value (A7) — the tell is uniformity, and
          sharp is as valid a choice as round.
BLAST     1 file. Affects every rounded element, so build and eyeball after.
```

### Copy — and this one is ours

```
FINDING   Em dash density across docs/
WHERE     docs/BRAND.md (8.3 per 500 words), COMPETITIVE-ANALYSIS.md (9.0),
          CALLS.md (6.9), BANS.md (5.8) — catalogue threshold is ~3.0
CATEGORY  C
VERDICT   Default
WHY       Tell C2, and it is a hit on documentation written in this session, not
          on inherited code. The catalogue is right that it reads as cadence
          rather than character.
FIX       Vary sentence construction on the next substantive edit of each file.
          Explicitly NOT a find-and-replace on the character — tells.md says
          that produces stilted copy and fixes nothing, and it is correct.
BLAST     Prose only. Low priority; genuinely a tell.
```

### Recorded as Justified

Guardrail G9 says context gates every rule and "Justified" is a real verdict, so
these are findings that were checked and kept.

```
FINDING   The mobile app copies Telegram's layout
WHERE     apps/mobile — site-wide
CATEGORY  B
VERDICT   Justified
WHY       docs/UX.md argues familiarity is free adoption for an audience where
          some users are on their first smartphone, and the skill's own G10 puts
          products where user error is expensive in the convention bucket.
          Judge the temperature, not the arrangement.
FIX       none — keep
```

```
FINDING   Market figures in the competitive analysis
WHERE     docs/COMPETITIVE-ANALYSIS.md:116, 152, 153
CATEGORY  D
VERDICT   Justified
WHY       The scanner flags "935M", "~95% of the population", "26.7M customers"
          as possible fabricated proof. They are cited third-party research
          about WeChat and Kakao — statements about other companies, not social
          proof for Sakina, which is what D1 actually prohibits.
FIX       none — keep. G3's inverse risk applies: do not delete things that
          might be real.
```

```
FINDING   Check and cross marks in the dev client
WHERE     tools/dev-client/index.html:449, verify.mjs:39, bench-fps.mjs:229
CATEGORY  B
VERDICT   Justified
WHY       Tell B6 fires when every item is marked positive so the marks carry no
          information. Here they are pass/fail state that genuinely differs, in
          an internal harness.
FIX       none — keep
```

```
FINDING   Dark-first palette in the mobile theme
WHERE     apps/mobile/lib/src/theme.dart
CATEGORY  A
VERDICT   Justified
WHY       Derived, and the derivation is written down: battery cost on a budget
          Android, readability in mountain sun, and a name that means stillness.
          Firuza traces to Samanid tilework. G8 makes this the system that
          overrides the skill's defaults list, not a candidate for replacement.
FIX       none — keep
```

---

## Summary

**Counts.** A: 6 · B: 2 (both Justified) · C: 1 · D: 4 (1 Justified).
Thirteen findings, four of them recorded as Justified.

**The three highest-value fixes**, in order:

1. **The reduced-motion path in `apps/web`.** It is the only hard-invariant
   violation in the repo, it affects real people with vestibular disorders, and
   it is a contained change to four components.
2. **`lang="en"` → `lang="ru"`.** One attribute, immediate accessibility gain.
3. **The v0 metadata.** Three lines, and until they change, the tab, the search
   result and every shared link say the page was generated.

None of these three touch the visual design, and all three are worth doing
regardless of how the decision below goes.

## Only you can decide

Guardrail G20 lists three things that must be asked rather than guessed. Two are
live here:

**What is `apps/web` for?** Right now it is the personal letter, kept
deliberately when the monorepo was scaffolded. Every Category A finding above is
conditional on the answer. If it stays a personal letter, most of them are moot —
a letter is allowed to be neon, and the only work worth doing is the three fixes
above. If it becomes Sakina's marketing site, the brand system in `BRAND.md`
already exists and the page should be rebuilt on it rather than patched toward
it.

**Is anything in the letter's presentation load-bearing?** The fireworks, the
typewriter and the heart are Category A tells by the catalogue. They are also
somebody's personal expression, and G3's inverse risk — do not delete content
that might be real — applies to intent as much as to testimonials. They stay
until you say otherwise.
