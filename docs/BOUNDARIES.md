# Boundaries

> The rule: a mistake should fail at a boundary, not leak into something that
> was working.

This document is the answer to one question — *when the next change goes wrong,
how much of the app does it take with it?* — and the answer is enforced rather
than hoped for. Every rule below has a check, every check has been verified
against a real violation, and `pnpm test` runs all of them.

## Why this is stricter than a normal codebase

This app is edited by people and by models. A model that has misread the task
does not fail loudly — it writes plausible code in the wrong place. Asked to
"make the badge blue" it will write a hex value into the badge, which is a
correct answer to the question and a wrong answer to the question the codebase
is asking. Asked to "animate the send button" it will reach for the light pass,
which already means *delivered* and now means nothing.

Conventions do not stop that. There is nothing to hit. A checked boundary turns
"quietly broke something that worked" into a failed build with a filename in it,
which is the entire difference between a change that costs ten minutes and one
that costs an afternoon of finding out what else moved.

The rules are also, deliberately, few. A boundary nobody can remember is a
boundary that gets worked around.

---

## 1. Sections do not know about each other

`pnpm test:boundaries`

```
ui/sections/<name>/   owned by that section — nothing else may import it,
                      and it may not import a sibling
ui/sections/section.dart, sections.dart
                      the contract and the registry: the only public seam
ui/auth/              the way in — only main.dart may import it, and it may
                      not import a section
ui/*.dart             shared vocabulary: motion primitives, skeletons,
                      indicators, the empty state, the mark
```

A section receives the app through `SectionScope` rather than reaching for it.
When one needs a new capability — a call service, a mini-app host — it becomes a
field there, and the sections that do not read it are unaffected.

**Adding a section:** a directory under `ui/sections/`, a class implementing
`SakinaSection`, and a line in `sections.dart`. Nothing counts or names them
anywhere else.

**When you genuinely need something from next door:** move it into `ui/` and
make it shared vocabulary, deliberately, where the next person can see it.
Do not reach sideways. The check will stop you, and it is right to.

## 2. Colour is defined in the theme and nowhere else

`pnpm test:design`

`Color(0x…)`, `Color.fromARGB` and `Colors.<name>` live in `theme.dart`.
Everything else takes colour from `SakinaPalette.of(context)` or
`Theme.of(context).colorScheme`.

The failure this prevents is quiet and permanent: a hex value typed into a
widget keeps working, looks right on the day, and then stops tracking the theme
forever. Firuza moves, the app moves, one button does not, and nobody finds out
from the code.

**When a new colour is genuinely needed** — the media viewer's black ground was
one — add it to `SakinaColors`, give it a name and a reason, and expose it on
`SakinaPalette`. "The ground a photo sits on" is a design decision even when the
answer is the obvious one.

The only waved-through cases are `Colors.transparent` and black/white *with an
opacity*, for scrims and shadows: that is the absence of colour rather than
brand colour, and routing it through the palette would say something untrue
about it.

## 3. Every animation says what it means

`pnpm test:motion`

Three rules, and the third is the one that matters most here:

1. A file that animates must reach the reduce-motion gate.
2. A `duration:` must come from the vocabulary in `motion.dart`, never written
   at the call site.
3. A file that animates must carry a `MOTION: <kind>` line naming one of:

| Kind | Means |
| --- | --- |
| `ТОБ` | the light pass — fires **once**, when something becomes true, never loops |
| `НАФАС` | the breath — the object in doubt expresses its own waiting |
| `ЧАРХ` | the turn — the mark stepping while something works |
| `PAGE` | hierarchical navigation — full-width travel meaning deeper, or back |
| `SECTION` | lateral navigation — a fade-through between siblings, no travel |
| `ENTRANCE` | a one-shot arrival of a row or a bubble |
| `GESTURE` | motion that tracks a finger and settles when released |

Rule 3 exists because the other two cannot catch the worst failure. `MOTION.md`
says the light pass means *delivered* precisely because it fires once on
success and never while waiting — and nothing stopped a new animation from
using it as a loading shimmer, at which point it means nothing anywhere,
including where it was right. The same applies to horizontal travel, which means
*deeper* and *back* and must not also come to mean *next tab*.

So an animation has to declare itself. Adding one is then a choice between
inheriting an existing kind's rules or adding a kind to the list — a deliberate
act, visible in the diff, rather than a meaning quietly borrowed.

Keep the list short. Seven is a vocabulary; twenty is a synonym list, and
synonyms are how a motion language stops meaning anything.

## 4. Strings, layout and the analyzer

Already enforced, listed here so the set is in one place:

- `pnpm test:l10n` — every string in Russian, Tajik and English; no key defined
  twice; every key the UI asks for exists. `t()` returns the key on a miss, so
  the failure mode is a tab labelled `explore`.
- `pnpm test:devices` — layout constants against real device widths.
- `pnpm test:flutter` — the real analyzer.
- `pnpm test:widgets` — the app's widgets actually built and laid out. The
  unread badge passed analysis and shipped as a bar across every chat name;
  only running it caught that.

---

## What this does not protect you from

Worth being honest about the edges, so the checks are not trusted further than
they go.

- **Behaviour.** A boundary check sees imports, not logic. A change that keeps
  every rule and breaks the chat list is caught by `test:widgets` or by nothing.
  When you fix a bug, leave a test that fails on it — that is the only rule here
  that scales.
- **Runtime coupling.** Two sections that both write the same repository field
  are coupled no matter which directories they live in.
- **Taste.** Nothing here stops a section being ugly, only from making the
  others ugly with it.
