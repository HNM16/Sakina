# Install

Drop the `design-tells` folder into either:

- `~/.claude/skills/design-tells/` — available in every project
- `<project>/.claude/skills/design-tells/` — this project only, and committable
  so the whole team gets it

Verify:

```
ls ~/.claude/skills/design-tells/SKILL.md
python3 ~/.claude/skills/design-tells/scripts/scan.py .
```

## Triggering

The skill description covers the natural phrasings: "this looks AI-generated",
"why does my site look vibecoded", "audit my landing page", "de-slop this".

To make it fire automatically before any UI ships, add this to the project's
`CLAUDE.md`:

```markdown
## Frontend

Before shipping any public-facing UI, run the `design-tells` skill in BUILD mode.
Before changing the design of an existing page, run it in AUDIT mode and show me
the report before making changes.

Never fabricate testimonials, logos, metrics, or product screenshots. Never emit
final legal text. Never remove a focus state.
```

Those last three lines are worth having in `CLAUDE.md` regardless of the skill,
since they are the failure modes with real consequences.

## How it composes with other skills

- `frontend-design` supplies the creative direction. `design-tells` is the gate
  that runs after it. Use both; they do not overlap.
- `web-design-guidelines` covers accessibility and interface guideline
  compliance. Run it after any visual change from this skill, since guardrail G1
  requires an accessibility re-check.
- `ui-ux-pro-max` supplies palettes and font pairings if you want a menu to pick
  from. Note that picking from a menu is still picking a default; use it for
  reference, not as the source of the decision.

## Typical session

```
> audit the landing page for design tells

  runs scripts/scan.py, reads the pages, produces the report, stops

> fix category D and the hard invariants, leave the rest

  fixes integrity and accessibility findings only, one commit per category

> now the defaults, but keep the brand purple

  brand constraint recorded, palette derived around it, contrast re-checked
```
