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

## Language

Tajik first, then Russian, then English. Tajik Cyrillic needs ғ ӣ қ ӯ ҳ ҷ — check
any font against those six before specifying it, and check any layout against
Tajik string lengths, which run roughly a third longer than English.
