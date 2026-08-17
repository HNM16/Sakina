# Tell catalogue

Each entry: what to look for, why it reads as inherited, when it is genuinely
correct, and the fix. Nothing here is banned outright. The verdict always depends
on whether the content produced the choice.

---

## Category A — Defaults

### A1. Inter, Geist, Space Grotesk, Roboto, Arial, bare system stacks
**Signal:** `font-family` or `next/font` import naming any of these; a `--font-sans`
token pointing at them; Tailwind's untouched default stack.
**Why:** these are the fonts that ship with the starter. Choosing none of them is
still not a choice; choosing one deliberately is.
**Legitimate when:** a design system mandates it, it is the brand face, the product
is a dense data tool where Inter's metrics genuinely help, or the locale set
requires the coverage these faces have.
**Fix:** pick a display face with a point of view and a body face that supports it,
both traceable to the subject. Verify the license before specifying it (see
guardrails G5). Load only the weights actually used. Keep a real fallback stack.

### A2. Purple and black
**Signal:** `#8B5CF6`, `#A855F7`, `#7C3AED`, `violet-*`/`purple-*` accents on
near-black, especially as the only accent.
**Why:** it is the default "AI product" palette and carries no meaning.
**Legitimate when:** it is the brand color. Brand always wins — see G8.
**Fix:** derive the palette from the subject's own materials, artifacts, or
vernacular. Name 4-6 values and state what each one is for.

### A3. Pure white background
**Signal:** `#fff` / `bg-white` as the page canvas.
**Why:** it is the absence of a decision, and it makes every shadow and border
look like a default too.
**Legitimate when:** the design is genuinely about maximum contrast, or print-like
clarity, or an existing system specifies it.
**Fix:** an off-white or tinted canvas chosen against the palette. Do not
reflexively reach for `#F4F1EA` — that warm cream is itself the current anti-AI
default (see G7).

### A4. Harsh multi-stop gradients
**Signal:** `linear-gradient` with three or more color stops across distant hues;
Tailwind `from-X-500 via-Y-500 to-Z-500`; gradient text on headings.
**Why:** gradients are used to add interest where the composition has none.
**Legitimate when:** the gradient encodes something (a scale, a range, a physical
material) or it is a single restrained tonal shift within one hue.
**Fix:** if the composition needs rescuing, rescue the composition. Otherwise
reduce to two stops within a narrow hue range, or remove.

### A5. Lucide icons everywhere
**Signal:** broad `lucide-react` imports, an icon on every list item and button.
**Why:** the same icon set with the same stroke weight appears on every generated
site, and icons get used as decoration rather than as signs.
**Legitimate when:** icons carry real meaning (status, file type, direction), or
the set is part of the design system.
**Fix:** delete icons that only decorate. For the ones that remain, either commit
to a set with a distinctive stroke and terminal, or draw the handful you need.
Consistency of weight and grid matters more than the source.

### A6. Uniform drop shadows
**Signal:** `shadow-md`/`shadow-lg` on every card, same blur, same offset, no
consistent light source.
**Why:** depth applied by habit rather than to express layering.
**Legitimate when:** elevation is meaningful (overlays, popovers, drag states) and
the shadow system has a stated light direction and tiers.
**Fix:** define one light source and two or three elevation tiers. Ambient surfaces
get no shadow. Consider borders, tint shifts, or spacing to express layering.

### A7. The library's stock radius
**Signal:** `--radius: 0.5rem`, `rounded-lg`/`rounded-xl` applied identically to
buttons, cards, inputs, images, and modals.
**Why:** one radius everywhere is the shadcn default, not a system.
**Legitimate when:** the value was chosen and the scale is deliberate.
**Fix:** build a small radius scale where the value relates to the element's size
and role. Sharp is a valid choice; so is very round. Uniform is the tell.

### A8. Rainbow, neon, and stock pastel palettes
**Signal:** hue-cycling category colors, saturated `#00FF*`-adjacent accents, the
Tailwind 200-level pastel set used as a palette.
**Why:** color assigned by generator rather than by meaning.
**Legitimate when:** categorical data genuinely needs distinguishable hues (then
use a perceptually spaced, colorblind-safe scale), or the brand is loud.
**Fix:** a dominant color with one or two sharp accents beats an even distribution.
Check contrast at every pairing after any palette change (G1).

### A9. Radial blur orbs
**Signal:** `absolute rounded-full blur-3xl` divs behind the hero; large soft
radial gradients in the background.
**Why:** atmosphere applied to hide an empty composition.
**Legitimate when:** the effect is part of a coherent atmospheric direction that
runs through the whole page.
**Fix:** if the hero needs presence, give it real content: the most characteristic
thing in the subject's world. Remove the orbs.

### A10. Dot grids and hairline meshes
**Signal:** `background-image: radial-gradient(circle, ... 1px, transparent 1px)`
with `background-size` around 16-24px.
**Why:** a texture with no relationship to the subject.
**Legitimate when:** the subject is genuinely about grids, plotting, mapping,
fabrication, or measurement.
**Fix:** remove, or replace with a texture drawn from the subject's materials.

### A11. Sparkle icons and sparkle language
**Signal:** `Sparkles`, `Wand2`, star-burst glyphs on anything AI-adjacent; copy
using "magic", "magical", "sprinkle".
**Why:** the universal shorthand for "AI feature", now pure noise.
**Legitimate when:** essentially never as decoration. As a brand mark, only if
drawn for the brand.
**Fix:** delete. Name the actual capability instead.

### A12. Liquid glass / heavy backdrop blur
**Signal:** `backdrop-filter: blur()` or `backdrop-blur-*` on navs, cards, modals,
usually with a translucent white or black fill.
**Why:** applied to every surface as a finish rather than to express layering over
content.
**Legitimate when:** a surface genuinely floats over changing content and the blur
aids separation.
**Fix:** verify text contrast against the *worst-case* background behind the
surface, not the screenshot background — translucency makes contrast
unpredictable and this is a real accessibility failure (G1). Cheaper and more
reliable: an opaque surface with a tint shift. Blur also costs GPU on scroll;
check against the performance budget (G6).

---

## Category B — Structural clichés

### B1. Three feature cards in a row
**Signal:** `grid-cols-3` with exactly three cards, each an icon, a bold phrase,
and two lines of body copy.
**Why:** the shape came first and the content was cut or padded to fill it.
**Legitimate when:** there really are three things of equal weight.
**Test:** if there were five, would there be five slots? If the answer is "we would
have picked the best three", the layout is driving the content.
**Fix:** let the count and hierarchy follow the content. Unequal things deserve
unequal space. One strong thing beats three weak ones.

### B2. Bento grids
**Signal:** a mosaic of unequal rounded tiles, usually with one hero tile.
**Why:** a shape borrowed from a different product's information density.
**Legitimate when:** the content is genuinely heterogeneous and the size differences
encode importance or type.
**Fix:** if the tiles are interchangeable, it is a list wearing a costume. Use a
list, or make the size differences mean something.

### B3. Three pricing tiers with the middle one highlighted
**Signal:** three columns, "Most popular" badge on the middle, checkmark features.
**Why:** the pattern is applied before anyone decided what the plans are.
**Legitimate when:** the business genuinely has three plans.
**Fix:** show the plans that exist. If there is one plan, show one, clearly. The
highlight badge should reflect actual data, not a layout convention — if you do
not know what most customers pick, do not claim it (this crosses into D1).

### B4. Colored stripe accents
**Signal:** a thin gradient or solid bar at the top of the page, cards, or sections.
**Why:** decoration standing in for hierarchy.
**Legitimate when:** the stripe encodes state, category, or progress.
**Fix:** remove, or make it carry information.

### B5. Decorative terminal window
**Signal:** a mock terminal with three colored dots, animated typing, fake output.
**Why:** used as a texture to signal "technical" on products with no CLI.
**Legitimate when:** the product actually has a CLI or the output shown is real.
**Fix:** if there is a CLI, show real commands and real output. If not, delete it.
Faked output is also an honesty problem (D2).

### B6. Checkmark bullet lists
**Signal:** a check glyph before every item in a feature or benefit list.
**Why:** every item marked positive means the marks carry no information.
**Legitimate when:** the list is a comparison and some items are genuinely absent,
or it reflects a real completion state.
**Fix:** plain list, or a real comparison where the marks differ.

### B7. Animated arrows and bouncing scroll cues
**Signal:** `animate-bounce` chevrons, arrows that translate on hover, "scroll to
explore" indicators.
**Why:** motion applied to compensate for a hero that does not invite scrolling.
**Legitimate when:** the fold genuinely hides content in a non-obvious way.
**Fix:** make the fold indicate continuation through composition. If motion stays,
it needs a reduced-motion path (G2).

---

## Category C — Copy clichés

### C1. "It's not X, it's Y"
**Signal:** "not just a tool, a teammate"; "isn't software, it's a system".
Also the negation-then-reveal cadence generally.
**Why:** it substitutes rhythm for a claim.
**Fix:** state what the thing does, specifically, with a noun a user would use.

### C2. Em dash density
**Signal:** more than roughly three per five hundred words, or several per
paragraph, especially in the parenthetical-aside pattern.
**Why:** it is a cadence, not a character. Human copy varies its punctuation.
**Legitimate when:** normal editorial prose uses them freely and well.
**Fix:** vary sentence construction. Do not do a find-and-replace on the character;
that produces stilted copy and fixes nothing.

### C3. Emoji as structure
**Signal:** emoji as section markers, bullets, or in headings and buttons.
**Why:** decoration that does not survive translation, screen readers, or a serious
brand.
**Fix:** remove. Use type weight and spacing for hierarchy.

### C4. Unanchored superlatives
**Signal:** "seamless", "effortless", "powerful", "10x", "blazing fast" with no
object, number, or comparison.
**Why:** claims with nothing behind them read as generated.
**Fix:** replace with a specific fact, or cut. If a number is used, it must be real
(see D1).

---

## Category D — Integrity and completeness

**These are not aesthetic findings. Read `guardrails.md` before touching any of
them. They are fixed first and they have hard rules.**

### D1. Fabricated testimonials, logos, metrics
**Signal:** quotes with plausible names and titles that appear nowhere else; "used
by 10,000 teams"; a logo wall; star ratings; "trusted by" with no source.
**Why:** it is not a design tell, it is a false statement to users.
**Fix:** **delete. Never rewrite into better-sounding fake social proof, and never
generate new social proof of any kind.** If a claim might be real, ask the user
before removing it — do not delete real customer content. If the page needs trust
and there is none to show, use something true instead: an open repository, a real
changelog, transparent pricing, a signed founder note, a public roadmap.

### D2. No real product demo
**Signal:** an abstract hero illustration, a mock screenshot, a faked terminal or
dashboard, on a page selling a product.
**Fix:** show the real interface. If it does not exist yet, say so plainly
("in development", "join the waitlist") and restructure the page around what is
true. **Do not generate a fake screenshot of a product that does not exist.**

### D3. No privacy policy
**Signal:** no route, page, or file matching privacy.
**Fix:** this requires care. First inventory what the site actually collects: read
the code for analytics, cookies, auth providers, form endpoints, embedded
third-party scripts, session storage, error reporting. Then produce a **clearly
labelled draft** derived from that inventory, with a header stating it requires
review by a qualified person, plus an explicit TODO list of the facts only the
user can supply: legal entity name, jurisdiction, retention periods, sub-
processors, contact address, whether GDPR/CCPA apply. **Never present generated
legal text as final or authoritative.**

### D4. No terms of service
**Signal:** no route, page, or file matching terms.
**Fix:** same rule as D3. Draft, labelled, reviewed by a human. Never binding text
presented as complete.

### D5. Missing loading and empty states
**Signal:** no skeletons, no suspense boundaries, no empty-state components; content
that pops in; `animate-pulse` used as decoration rather than as a loading state.
**Why:** it reveals a page that was never used with real, slow, or absent data.
**Fix:** real work, not a visual patch. Add loading states at the actual async
boundaries, sized to match the content they replace so the layout does not shift.
Add empty states with a real next action. Add error states. Skeletons must respect
reduced-motion (G2).

### D6. Hover animation on everything
**Signal:** `transition-all` site-wide; `hover:scale-105` and `hover:-translate-y-1`
on non-interactive cards; every surface lifting.
**Why:** decoration that dilutes the feedback real controls need.
**Fix, and this one is easy to get dangerously wrong:** separate **feedback** from
**decoration**. Feedback on real controls is required and must stay — removing
hover, focus, and active states is an accessibility regression, not a design
improvement (G1). Sharpen it instead: fast (roughly 120-180ms), on specific
properties rather than `all`, and always paired with a visible focus state and a
touch-friendly active state, since hover does not exist on touch devices. Delete
the decoration: transforms on things that are not controls. Every remaining
transition needs a reduced-motion path (G2).
