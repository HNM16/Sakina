---
name: design-tells
description: Detect and remove the signals that make a web UI read as AI-generated or "vibecoded", either as a pre-ship gate on new work or as an audit-and-repair pass on an existing site. Use when the user says a site looks AI-generated, vibecoded, generic, templated, or "like Claude made it"; when they ask to de-slop, humanize, or make a design look intentional; when auditing an existing frontend for design quality; or before shipping any landing page, marketing site, or public-facing UI. Do not use for backend work, internal admin tools where familiarity is the goal, or pure accessibility reviews.
---

# Design Tells

A catalogue of the signals that make a page read as machine-produced, plus a
disciplined process for removing them without breaking the site.

## The one idea

**The tells are symptoms. The disease is undeclared defaults.**

A page reads as AI-generated when its decisions were inherited rather than
derived: the font that ships with the starter, the radius that ships with the
component library, the three-card row that fits any three things, the purple
that means nothing. Each individual choice is defensible. Together they read as
a page nobody decided.

This has a critical consequence: **banning the symptoms does not cure the
disease.** Swap Inter for a different default font and the page is still
undesigned. Worse, the anti-AI look is now its own recognizable default — cream
background, high-contrast serif, hairline rules, zero radius, terracotta accent,
monospace eyebrows. Fleeing to it is the same failure wearing different clothes.

So every rule in this skill resolves to one question:

> Did the content produce this choice, or did the choice arrive on its own?

If the content produced it, keep it and say why. If it arrived on its own,
derive it from the subject or delete it. Never substitute one default for
another.

## Gate: should this page be distinctive at all?

Run this before anything else. Distinctiveness is not universally correct.

Push for a strong point of view on: landing pages, marketing sites, portfolios,
launch pages, docs homepages, product sites, editorial, anything competing for
attention.

Push for boring convention on: internal admin tools, medical and clinical
interfaces, government and legal forms, financial transaction flows, accessibility-
first products, checkout, anything where a user error is expensive. Here,
familiarity lowers error rates and an unexpected layout is a defect. Report tells,
but only fix the integrity failures (Category D below) and leave the conventional
patterns alone.

If unsure which bucket the project is in, ask. Do not guess and redesign.

## Two modes

### Mode 1 — BUILD (pre-ship gate)

Use when generating new UI. This mode does not replace the `frontend-design`
skill; that one supplies the creative direction, this one is the checkpoint
before the work ships.

1. Write a one-line design thesis naming the subject, its audience, and the
   single job of the page.
2. Derive tokens from the thesis: 4-6 named colors, a type pairing, a spacing
   and radius scale, one signature element. Every value needs a sentence of
   justification tracing back to the thesis.
3. Run the pre-flight in `references/tells.md`. For every tell present, record
   the justification or remove it.
4. Verify the invariants in `references/guardrails.md`. Any change that lowers
   contrast, removes a focus state, adds motion without a reduced-motion path,
   or fabricates content is rejected regardless of how it looks.

If step 2 produces the same tokens you would produce for an unrelated brief,
the thesis is not doing work. Rewrite it before writing code.

### Mode 2 — AUDIT and REPAIR (existing site)

Use when a site already exists. Default to reporting; fix only when asked.

1. **Inventory.** Run `scripts/scan.py <project-dir>` for the mechanically
   detectable tells. The script never edits anything.
2. **Read.** The scanner finds tokens, not judgment. Read the actual pages for
   the structural, copy, and integrity tells it cannot see.
3. **Classify each finding** into one of four categories (see below). The
   category determines the fix, and the categories have different urgency.
4. **Verdict per finding**: Justified (content produced it — keep, note why),
   Default (nobody chose it — derive or delete), or Integrity (not an aesthetic
   issue at all — fix first).
5. **Report** in the table format below. Stop here unless the user asked for
   fixes.
6. **Repair** in category order: D first, then A, then B, then C. Smallest diff
   that achieves the fix. Token-level before component-level. One reviewable
   commit per category. Build and test after each.

## The four categories

**A. Defaults.** Values reached for because they were nearest, not because they
were right. Fonts (Inter, Geist, Space Grotesk, Roboto, system stacks), purple-
and-black, pure white, harsh multi-stop gradients, Lucide icons everywhere,
the library's stock radius, uniform drop shadows, rainbow and neon and stock
pastel palettes, radial blur orbs, dot grids, sparkle icons.
*Fix:* derive from the subject's own world. Not a different default.

**B. Structural clichés.** Layouts applied to content rather than drawn from it.
Three feature cards in a row, bento grids, three pricing tiers, the colored
stripe, the decorative terminal window, checkmark bullet lists, animated arrows.
*Fix test:* if there were five things instead of three, would the layout have
five slots? If yes, the shape came from the content — keep it. If the content
was padded or trimmed to fit the shape, the shape is the tell.

**C. Copy clichés.** "It's not X, it's Y." Emoji as section markers. Sparkle
language. Em dashes at a density no human sustains. Superlatives with no object.
*Fix:* rewrite for specificity. Note that em dashes and the occasional triad are
normal in good prose; the tell is cadence and density, not the character. Do not
ban punctuation.

**D. Integrity and completeness failures.** Fabricated testimonials, invented
logos or metrics, no real product demo, missing privacy policy, missing terms,
missing loading states. These are not aesthetic problems and they are the most
dangerous to "fix" carelessly. **Read `references/guardrails.md` before touching
any of them.** In short: never fabricate social proof, never present generated
legal text as final, never fake a product demo.

## Report format

```
FINDING   <short name>
WHERE     path:line (or "site-wide")
CATEGORY  A | B | C | D
VERDICT   Justified | Default | Integrity
WHY       one sentence on what makes it read as inherited, or why it is earned
FIX       the specific change, or "none — keep"
BLAST     files touched / tokens affected / needs user decision
```

End the report with a short summary: counts by category, the three highest-value
fixes, and anything that needs a decision only the user can make (brand colors,
legal facts, whether a testimonial is real).

## Honesty about the method

This is a heuristic, not a measurement. Do not produce a numeric "AI score" and
do not claim a page has been made undetectable. The goal is a page whose choices
can each be defended, not a page that passes a checker.

And never fix by obfuscation: no deliberate typos, no randomized jitter, no
fake hand-drawn imperfection added purely to look human. That is cargo-culting
authenticity and it degrades the work.

## Reference files

- `references/tells.md` — the full catalogue: detection signal, why it reads as
  inherited, when it is legitimate, and the correct fix for each tell.
- `references/guardrails.md` — the invariants, the twenty foreseeable ways this
  process makes a site worse, and how to avoid each.
- `scripts/scan.py` — read-only static scanner. `python3 scan.py <dir>`,
  `--json` for machine output, `--quick` for the high-signal subset.
