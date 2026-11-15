# Running on the actual phones people have

The app is expected to work from a Galaxy A15 to an iPhone 17 Pro Max, plus the
awkward ones in between — a Fold's outer screen, a Flip, a tablet.

Three files do this work:

| | |
| --- | --- |
| `tools/device-matrix/devices.json` | 31 real devices, in logical units |
| `apps/mobile/lib/src/layout.dart` | the layout system the app actually uses |
| `tools/device-matrix/verify.mjs` | proves the two agree, and that the rules hold |

Run it with `pnpm test:devices`.

## The matrix is test data, not layout logic

Nothing in the app branches on a device. There is no `isIPhone`, no model list,
no per-device special case. A layout that needs to know it is on an iPhone 15 is
a layout that breaks on the iPhone 18, and that is a maintenance bill nobody
budgets for.

What the table is for is establishing the **range**: 320 to 834 logical units
wide. Every rule is written against that range, and the verifier then runs the
rules at all 31 widths to prove they hold.

The numbers are in logical units — points on iOS, dp on Android, CSS pixels in a
browser. Physical pixel counts and screen diagonals are marketing, and neither
one is what a layout sees.

## Breakpoints

| | Width | Why this number |
| --- | --- | --- |
| **narrow** | < 375 | The Galaxy Z Fold's outer screen is 344. Below this line a row cannot hold an avatar, two lines, a timestamp and a badge honestly |
| **compact** | < 600 | Material 3's own boundary. One pane |
| **medium** | 600–839 | Material 3. Two panes: the Fold's inner screen lands here at 674 |
| **expanded** | ≥ 840 | Material 3. Tablets |

`compact` and `medium` are Material's, unchanged. Inventing a parallel set of
breakpoints next to the ones the widget library already thinks in is exactly the
gratuitous difference `UX.md` argues against.

`narrow` is ours, and it sits *inside* compact — 344 and 440 are both "compact"
to Material, and that 96-unit gap is the difference between a composer with room
for a label and one without.

## What is actually verified

Three passes, in increasing order of what they can catch.

**1. Drift.** The verifier parses the constants out of `layout.dart` and fails if
they no longer match `devices.json`. This is the check that matters in a year:
the matrix and the Dart are two files, and two files disagree eventually.

**2. Arithmetic.** The layout rules run at all 31 widths. Every device must have
usable width after gutters, a message bubble wide enough to hold a word and a
timestamp, a detail pane that is still a conversation, and vertical room for
messages after the app bar, the composer and both safe-area insets.

**3. Rendering.** A real browser at each of the 31 viewports, checking for
horizontal overflow, controls under the 44-unit floor, and — using canvas text
measurement against the page's own font — Tajik labels that do not fit at the
maximum text scale.

The rendering pass drives `tools/dev-client`, not the Flutter app, because the
Flutter app cannot be compiled in this environment. The dev client is built to
the same breakpoints and pass 1 keeps them honest, so this measures something
real; it is still not the same thing as running the app.

**What none of this proves:** that the Flutter widgets render correctly. No Dart
runs here. `layout.dart` is read-checked and its constants are machine-checked;
the widgets are unverified, the same caveat that applies to all of `apps/mobile`.

## Two things the rendering pass found

Worth recording, because both looked like the layout was wrong and only one was.

**A control under 44 units.** Real, and fixed by giving every input and button a
`min-height`. Hard invariant 6 in the design-tells guardrails, and the iOS HIG
floor. Our own controls are sized to Material's 48 so a rounding error cannot
push one under.

**A drawer measured mid-transition.** Not real. The matrix deliberately crosses
the two-pane breakpoint in both directions — which is what a Fold does when it
closes — and the check was sampling one frame into a 180ms slide. The fix was to
wait for the transition rather than to reorder the matrix, because crossing back
and forth is the case worth testing.

## Sizes near the knowledge cutoff

The iPhone 17 line and the iPhone Air are marked `"confidence": "check"` in the
matrix. They sit close to the edge of what this was written from, and they should
be confirmed against Apple's spec page before anyone relies on them for store
assets.

The layout does not depend on them being exact — only on them being inside the
320–834 range, which every phone Apple has shipped comfortably is.

## Text scale

Accessibility text goes to 3.1x on iOS and 2.0x on Android. `layout.dart` clamps
at 1.6x. Past that the honest choice is between a broken layout and a smaller
font, and a broken layout helps nobody — but the floor is 1.0, because shrinking
text for someone who asked for bigger text is user-hostile.

`hasRoomForInlineLabels` is a function of width *and* text scale, so a wide phone
at a large font is correctly treated as cramped. A raw width check would miss it.

## Reduced motion

`SakinaLayout.motion()` returns `Duration.zero` when the platform asks for
reduced motion, and every animation the app authors goes through it. Guardrail G2
is explicit that shortening an animation is not the same as disabling it, which
is why it returns exactly zero rather than something small.
