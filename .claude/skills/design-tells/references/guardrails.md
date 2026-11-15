# Guardrails

Removing design tells is a change to working software. Most of the damage this
process can do is predictable, so it is enumerated here.

## Hard invariants

A change is rejected if it does any of the following, no matter how much better
the result looks:

1. Lowers text or UI contrast below WCAG AA.
2. Removes or weakens a focus, hover, or active state on an interactive control.
3. Adds motion with no `prefers-reduced-motion` path.
4. Fabricates a testimonial, logo, metric, customer count, rating, award, case
   study, or product screenshot.
5. Presents generated legal text as final.
6. Reduces a touch target below 44x44 CSS pixels.
7. Breaks heading hierarchy, landmarks, alt text, or label associations.
8. Changes application logic, routing, data flow, or tests. This process touches
   presentation only.

---

## G1. Accessibility regression

The single most likely way this goes wrong. "No drop shadows, no hover, no soft
radius, less motion" reads as an instruction to strip interaction affordances,
and stripping them breaks the site for keyboard and low-vision users.

- Never delete a focus ring. If it is ugly, redesign it; `outline: none` without a
  replacement is a defect.
- Hover feedback on controls is required. Only decoration on non-controls is cut.
- Hover does not exist on touch. Any state that matters needs an active or focus
  equivalent.
- Re-check contrast after every palette, opacity, or background change, including
  disabled states, placeholder text, borders on inputs, and text over images.
- Translucent surfaces (backdrop blur) must be checked against the worst-case
  content that can scroll behind them, not the current screenshot.

Run an accessibility check after the visual pass, not before. The
`web-design-guidelines` skill covers this ground and composes well here.

## G2. Motion and vestibular safety

Chasing distinctiveness pushes toward motion. Every animation, including skeleton
shimmer and staggered reveals, needs a `prefers-reduced-motion: reduce` path that
disables transform and opacity animation rather than merely shortening it. Adding
motion without this introduces a new defect while fixing an old one. No
scroll-jacking, no parallax that hijacks scroll position, no autoplaying loops
longer than a few seconds without a pause control.

## G3. Never fabricate

The Category D tells tempt fabrication because the page has a hole where evidence
should be. Filling the hole with invented evidence is worse than the tell.

Never generate: testimonials, customer names, company logos, user counts, revenue
or performance numbers, funding, awards, star ratings, review counts, case study
outcomes, or screenshots of software that does not exist.

If the page needs the section and there is nothing true to put in it, remove the
section and use a trust device that is real.

**Inverse risk:** do not delete content that might be real. A real customer quote
can look templated. Ask before removing anything that could be genuine.

## G4. Legal text

Never emit final terms of service or a privacy policy. Emit a draft that is:
derived from an actual inventory of the code's data collection; clearly labelled
as requiring review by a qualified person; and accompanied by an explicit list of
facts only the user can supply (entity, jurisdiction, retention, sub-processors,
contact, applicable regimes). A confidently generated privacy policy that
misstates data practices is a legal liability, not a design improvement.

## G5. Font licensing

"Do not use Inter" pushes toward paid or unlicensed faces. Before specifying any
font, confirm the project can legally use it in the way it will be used: web
embedding is a separate license from desktop, and trial or personal-use licenses
are common. Prefer self-hosting with a verified license or an open face with a
clear SIL/OFL grant. Never hotlink a foundry's preview file. Always ship a real
fallback stack and load only the weights and subsets actually used.

## G6. Performance budget

Distinctiveness is easy to buy with bytes and GPU. Set the budget before the
redesign and measure after: web font payload, blocking requests, LCP, CLS, and
main-thread cost of any canvas, WebGL, shader, or `backdrop-filter` on scroll. A
memorable page with a four-second LCP is a worse page. If a signature element
cannot fit the budget, it is not the signature element.

## G7. The anti-slop trope

The overcorrection is now its own default: cream near `#F4F1EA`, high-contrast
serif display, terracotta or warm-clay accent near `#D97757`, hairline rules,
zero radius, monospace eyebrows, dense broadsheet columns. Also: near-black with a
single acid-green accent. These are legitimate directions for some briefs, and
they are wrong as a reflex. If the fix for a purple-and-black page is a cream-and-
serif page, nothing was decided; the same generator ran with a different seed.

## G8. Brand and design system override

If the project has brand guidelines, a token file, a component library, or an
existing visual system, those win. Report that a brand color matches a common
default; do not change it unilaterally. Purple is not banned if the brand is
purple. Inter is not banned if the design system specifies Inter.

## G9. Context gates every rule

Most tells have a context in which they are simply correct. A terminal window on a
CLI product. A bento grid over genuinely heterogeneous data. Three pricing tiers
for a business with three plans. Checkmarks in an actual comparison table. Always
check the content before flagging, and record "Justified" as a real verdict rather
than treating every match as a defect.

## G10. Not every product should be distinctive

Internal tools, clinical interfaces, government forms, financial flows, and
checkout benefit from convention. Familiar patterns lower error rates. Do not push
a triage dashboard into editorial-magazine mode. In these products, fix only the
Category D integrity failures and leave the conventional patterns intact.

## G11. Blast radius and scope

An audit is not a rewrite. State the blast radius before acting: token-level
changes touch every component, which is usually correct but must be said out loud
and followed by a build and a test run. Prefer the smallest diff that achieves the
fix. Group changes into one reviewable commit per category. Never refactor logic,
rename props, restructure routes, or touch tests while doing a visual pass. If the
user asked for an audit, deliver the report and stop.

## G12. Theme coverage

A palette change applied to one theme silently breaks the other. Apply every color
change to light, dark, and any high-contrast variant, and re-check contrast in
each. The same applies to system-preference media queries and any per-tenant
theming.

## G13. Internationalization and RTL

Distinctive display faces frequently lack coverage for non-Latin scripts, and
tight tracking, small caps, and custom ligatures break in translation. Check
whether the project ships other locales before committing to a face. Layouts that
depend on directional composition need an RTL check. Text expansion of 30-40
percent is normal in translation; fixed-height hero type will break.

## G14. Semantics and SEO

Visual restructuring commonly damages crawlability: headings replaced with styled
divs, hero copy moved into an image or canvas, link text turned into icons,
sections turned into non-semantic containers. Preserve heading order, landmark
regions, link text, alt text, and structured data through any layout change.

## G15. Content-shaped layouts break with real content

A layout tuned to the placeholder copy will break with real copy: longer headlines,
missing images, one-item lists, twelve-item lists, very long names. Test every
changed layout at the extremes before shipping.

## G16. Component library churn

Replacing a component library to escape its defaults is almost always the wrong
trade. Most of its tells live in its tokens: radius, shadow, font, spacing,
palette. Change the tokens first and re-evaluate. Only consider replacement if the
tokens genuinely cannot express the direction.

## G17. Do not fake humanity

No deliberate typos, no randomized rotation or jitter, no synthetic grain added
purely to defeat detection, no hand-drawn filter over generated shapes. These
degrade the work and fool nobody. Distinctiveness comes from decisions, not from
noise.

## G18. No score, no guarantee

Do not produce a numeric authenticity score and do not claim a page will no longer
read as AI-generated. Report findings and justifications. Overstating certainty
here is its own failure.

## G19. Cost and proportion

Match effort to the request. A quick pass names the top few findings. A full pass
walks every page. Do not run a full redesign because someone asked why a button
looks generic, and do not silently spend a long session on an audit that was meant
to take minutes.

## G20. Ask rather than assume

Three things are genuinely unknowable from the code and must be asked, not
guessed: whether a piece of social proof is real, what the brand constraints are,
and which of the two product buckets in G10 this project falls into. Guessing any
of these produces confident, wrong, expensive changes.
