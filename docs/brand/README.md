# docs/brand

Everything that shows the identity rather than the product. The product's own
screens live in [`../prototype/`](../prototype/).

Read [`../BRAND.md`](../BRAND.md) first — it is the written system, and these
files are what it looks like.

| File | What it is | Open it when |
| --- | --- | --- |
| [`identity.html`](identity.html) | The whole system on one page: palette, type, the mark, both themes | You want the short version of `BRAND.md` with live swatches |
| [`marks.html`](marks.html) | Six candidate marks, animated, down to 16 px | The mark is being decided — see `../DESIGN-AUDIT.md` |
| [`samani.html`](samani.html) | ЧАРХ, the quarter turn, with its two timings on sliders | Working on how the mark moves |
| [`motion.html`](motion.html) | The three motion primitives as live specimens, with a reduce-motion toggle | You are implementing anything in `../MOTION.md` |
| [`navigation.html`](navigation.html) | The chat transition, draggable, with theme / reduce-motion / RTL toggles and a frame-rate readout | You are touching page transitions or the back gesture |
| `identity.png` | A still of `identity.html`, for embedding in Markdown | — |
| `mark-check.png` | Evidence for the mark findings: silhouette, size ramp, squint test | — |
| `charkh-frames.png` | One turn of ЧАРХ sampled at fixed moments, so the easing can be judged from a still | — |
| `nav-frames.png` | The chat transition at five points, so the parallax ratio can be read off a still | — |
| `light-pass.png` | A still of ТОБ mid-crossing | — |

## Regenerating the images

```bash
pnpm brand:render
```

Renders `identity.png`, `mark-check.png`, `charkh-frames.png` and
`nav-frames.png` from source. (`light-pass.png` predates the script and is still
hand-captured.) They are generated rather than captured by hand because they had
already drifted from the pages they claim to show — `identity.png` was once
captured in the light swap with the mark's entrance animation still on frame
zero, which left the mark invisible in our own identity document.

## The rule for this folder

HTML here is a **specimen**, not a product surface. It exists to be looked at
while deciding something, and it uses the real tokens so that looking at it
tells you the truth. None of it ships.
