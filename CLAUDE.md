# Sakina — working notes for Claude

A messenger for Tajikistan, built to become a super-app. Read `README.md` first,
then `docs/ARCHITECTURE.md`.

## Frontend

Before shipping any public-facing UI, run the `design-tells` skill in BUILD mode.
Before changing the design of an existing page, run it in AUDIT mode and show me
the report before making changes.

Never fabricate testimonials, logos, metrics, or product screenshots. Never emit
final legal text. Never remove a focus state.

## The brand is the design system, and it wins

`docs/BRAND.md` and `apps/mobile/lib/src/theme.dart` are the source of truth for
colour, type and the mark. Guardrail G8 in the skill says an existing system
overrides its defaults list — this is that system. Firuza (`#35B9AC`) is the
accent because it is the glaze on Samanid tilework, not because it tested well;
do not swap it out to escape a tell.

Two things that look like tells and are not:

- **The app deliberately copies Telegram's layout.** `docs/UX.md` argues that
  familiarity is free adoption, and skill guardrail G10 agrees — convention
  lowers error rates in products where a mistake is expensive. The chrome is
  conventional on purpose. Judge the *temperature*, not the arrangement.
- **`tools/dev-client/` is an internal test harness**, not a product surface.
  G10 bucket: convention. Fix integrity findings there, leave the rest.

## Which bucket is which

| Surface | Bucket | What the skill should do |
| --- | --- | --- |
| `apps/web` | undecided — see `docs/DESIGN-AUDIT.md` | ask before redesigning |
| `apps/mobile` | convention, by strategy | integrity + temperature only |
| `tools/dev-client` | internal tool | Category D only |
| `docs/brand/` | editorial | full pass |

## Before changing layout or strings

- **Layout constants live in `apps/mobile/lib/src/layout.dart` and are checked
  against `tools/device-matrix/devices.json`.** Change one and `pnpm test:devices`
  fails until you change the other. Nothing branches on a device name; the matrix
  exists to establish the 320–834 range, not to special-case phones.
- **Every user-facing string goes through `L10n.t`.** `pnpm test:l10n` fails if a
  key is missing a language or if the UI asks for a key that does not exist —
  `t()` returns the key itself on a miss, so the failure mode is a button
  labelled `chanel_name` rather than a crash.
- **Every animation goes through `apps/mobile/lib/src/motion.dart`.**
  `pnpm test:motion` fails if an animating file never reaches the reduce-motion
  gate, or if a `duration:` is written at the call site instead of named in the
  vocabulary. Adding a looping indicator means adding its period there too.
- **`pnpm test:dart` is not a compiler.** There is no Flutter SDK in this
  environment and none of `apps/mobile` has ever been compiled. The script checks
  imports, declared packages, bracket balance and undefined Sakina-named symbols.
  Say so when reporting Flutter work.

## Language

**Russian first, then Tajik, then English.** The order is a product decision,
not a linguistic one: Russian is the language every part of the audience can
read, including the migrant workers in Russia who are a large share of who this
is for. A phone set to neither lands on Russian.

That does not demote Tajik in the places it decides things:

- **Fonts are still chosen on Tajik.** Tajik Cyrillic needs ғ ӣ қ ӯ ҳ ҷ. Check
  any face against those six before specifying it — Russian coverage proves
  nothing about them.
- **Layouts are still sized on Tajik.** Tajik strings run roughly a third longer
  than English, and longer than Russian too. Size against the longest of the
  three, which is almost always Tajik.
- **The picker is endonymic.** Русский / Тоҷикӣ / English, each in its own
  language. Never translate a language name into a language the reader does not
  have.
