# docs/brand

Everything that shows the identity rather than the product. The product's own
screens live in [`../prototype/`](../prototype/).

Read [`../BRAND.md`](../BRAND.md) first — it is the written system, and these
files are what it looks like.

| File | What it is | Open it when |
| --- | --- | --- |
| [`identity.html`](identity.html) | The whole system on one page: palette, type, the mark, both themes | You want the short version of `BRAND.md` with live swatches |
| [`marks.html`](marks.html) | Six candidate marks, animated, down to 16 px | The mark is being decided — see `../DESIGN-AUDIT.md` |
| [`samani.html`](samani.html) | The chosen mark, with every animation variant it could carry | Picking how САМАНӢ moves |
| [`motion.html`](motion.html) | The three motion primitives as live specimens, with a reduce-motion toggle | You are implementing anything in `../MOTION.md` |
| `identity.png` | A still of `identity.html`, for embedding in Markdown | — |
| `mark-check.png` | Evidence for the mark findings: silhouette, size ramp, squint test | — |
| `samani-frames.png` | Every САМАНӢ variant sampled across one cycle, so a loop can be judged from a still | — |
| `light-pass.png` | A still of ТОБ mid-crossing | — |

## Regenerating the images

```bash
pnpm brand:render
```

Renders `identity.png` and `mark-check.png` from source. The two are generated
rather than hand-captured because they had already drifted from the pages they
claim to show — `identity.png` was once captured in the light swap with the
mark's entrance animation still on frame zero, which left the mark invisible in
our own identity document.

## The rule for this folder

HTML here is a **specimen**, not a product surface. It exists to be looked at
while deciding something, and it uses the real tokens so that looking at it
tells you the truth. None of it ships.
