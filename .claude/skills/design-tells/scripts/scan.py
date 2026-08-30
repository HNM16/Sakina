#!/usr/bin/env python3
"""Read-only scanner for the mechanically detectable design tells.

    python3 scan.py <dir> [--json] [--quick]

This script NEVER edits, moves, or creates anything. It reads files and prints
findings. Every finding is a *candidate*: the catalogue in references/tells.md
lists, for each tell, the context in which it is simply correct. A match is the
start of a judgement, not the end of one.

It covers Category A (defaults) and the grep-able parts of B, C and D. The
structural, copy and integrity tells that need reading — whether three cards
were padded to fill a grid, whether a testimonial is real — are not detectable
here by design, and the skill's step 2 exists for them.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, asdict

# Files worth reading. Everything else is skipped before it is opened.
EXTENSIONS = {
    ".tsx", ".ts", ".jsx", ".js", ".mjs", ".cjs",
    ".css", ".scss", ".sass", ".less",
    ".html", ".htm", ".svelte", ".vue", ".astro",
    ".md", ".mdx",
    ".dart", ".kt", ".swift",
}

SKIP_DIRS = {
    "node_modules", ".git", ".next", "dist", "build", "out", "coverage",
    ".turbo", ".vercel", "vendor", "__pycache__", ".dart_tool", "Pods",
    ".svelte-kit", ".astro", "target",
}

# A file over this size is almost always generated or vendored.
MAX_BYTES = 600_000


@dataclass
class Finding:
    tell: str
    name: str
    category: str
    path: str
    line: int
    excerpt: str
    note: str


@dataclass
class Rule:
    tell: str
    name: str
    category: str
    pattern: str
    note: str
    quick: bool = False
    exts: tuple[str, ...] = ()          # empty = all
    flags: int = re.IGNORECASE


# --------------------------------------------------------------------------
# Category A — defaults
# --------------------------------------------------------------------------
RULES: list[Rule] = [
    Rule("A1", "Starter font",
         "A",
         r"""(?:font-family[^;{}]*|--font-[\w-]+\s*:\s*|next/font/google['"\s,{]*)"""
         r"""["']?\b(Inter|Geist|Space\s*Grotesk|Roboto|Arial|Helvetica)\b""",
         "The font that ships with the starter. Legitimate when a design system "
         "mandates it, it is the brand face, or the locale set needs its coverage.",
         quick=True),

    Rule("A2", "Default AI purple",
         "A",
         r"(#8B5CF6|#A855F7|#7C3AED|#6D28D9|\b(?:bg|text|from|to|via|border)-(?:violet|purple)-\d{3}\b)",
         "The default 'AI product' accent. Legitimate only when it is the brand "
         "colour — brand always wins (G8).",
         quick=True),

    Rule("A3", "Pure white canvas",
         "A",
         r"(\bbg-white\b|background(?:-color)?\s*:\s*(?:#fff(?:fff)?|white)\b)",
         "The absence of a decision. Legitimate for print-like clarity or maximum "
         "contrast. Do not reflexively swap to #F4F1EA — that is now its own "
         "default (G7).",
         quick=True),

    Rule("A4", "Multi-stop gradient",
         "A",
         r"(\bfrom-[\w-]+\s+via-[\w-]+\s+to-[\w-]+\b|linear-gradient\([^)]*,[^)]*,[^)]*,[^)]*\)"
         r"|\bbg-clip-text\b.*\bbg-gradient)",
         "Interest added where the composition has none. Legitimate when the "
         "gradient encodes a scale, a range, or a real material."),

    Rule("A5", "Lucide icon set",
         "A",
         r"""from\s+["']lucide-react["']""",
         "The same set at the same stroke weight appears on every generated site. "
         "Legitimate when the icons carry meaning rather than decorate."),

    Rule("A6", "Uniform drop shadow",
         "A",
         r"\bshadow-(?:md|lg|xl)\b",
         "Depth applied by habit. Legitimate when elevation is meaningful and the "
         "system states a light direction and tiers."),

    Rule("A7", "Stock radius",
         "A",
         r"(--radius\s*:\s*0\.5rem|\brounded-(?:lg|xl)\b)",
         "One radius everywhere is the shadcn default, not a system. The tell is "
         "uniformity — sharp and very round are both valid choices.",
         quick=True),

    Rule("A8", "Neon / stock pastel",
         "A",
         r"(#(?:0{2}[Ff]{2}(?:[0-9A-Fa-f]{2})|[0-9A-Fa-f]{0,2}[Ff]{2}00[0-9A-Fa-f]{0,2})\b"
         r"|\b(?:bg|text)-(?:red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|"
         r"indigo|violet|purple|fuchsia|pink|rose)-200\b)",
         "Colour assigned by generator rather than by meaning. Legitimate when "
         "categorical data needs distinguishable, colourblind-safe hues."),

    Rule("A9", "Radial blur orb",
         "A",
         r"(blur-(?:2xl|3xl)|filter\s*:\s*blur\(\s*\d{2,}px)",
         "Atmosphere applied to hide an empty composition. Legitimate as part of a "
         "coherent atmospheric direction running through the whole page.",
         quick=True),

    Rule("A10", "Dot grid texture",
         "A",
         r"radial-gradient\(\s*circle[^)]*\)\s*(?=[^;]*background-size)|"
         r"radial-gradient\(circle[^;]{0,80}1px",
         "A texture with no relationship to the subject. Legitimate when the "
         "subject is about grids, plotting, mapping, or measurement."),

    Rule("A11", "Sparkle shorthand",
         "A",
         r"(\bSparkles?\b|\bWand2\b|\bmagical?\b|\bsprinkle\b|✨|🪄)",
         "The universal 'AI feature' shorthand, now pure noise. Name the actual "
         "capability instead.",
         quick=True),

    Rule("A12", "Backdrop blur finish",
         "A",
         r"(\bbackdrop-blur(?:-\w+)?\b|backdrop-filter\s*:\s*[^;]*blur)",
         "Applied as a finish rather than to express layering. Contrast must be "
         "checked against the WORST-CASE background behind it, not the screenshot "
         "(G1), and it costs GPU on scroll (G6)."),

    # ----------------------------------------------------------------------
    # Category B — structural clichés
    # ----------------------------------------------------------------------
    Rule("B1", "Three-across grid",
         "B",
         r"\b(?:md|lg|sm)?:?grid-cols-3\b",
         "Test: if there were five things, would there be five slots? If the "
         "content was padded or trimmed to fill the shape, the shape is the tell.",
         quick=True),

    Rule("B5", "Decorative terminal",
         "B",
         r"(terminal|\$\s+npm\s+i|>\s*_\s*<)",
         "Used as texture to signal 'technical'. Legitimate when the product has a "
         "CLI and the output shown is real — faked output is also a D2 problem."),

    Rule("B6", "Checkmark bullets",
         "B",
         r"(\bCheck(?:Circle|Circle2)?\b\s*/?>|✓|✔|&check;)",
         "Every item marked positive means the marks carry no information. "
         "Legitimate in a real comparison where the marks differ."),

    Rule("B7", "Bouncing scroll cue",
         "B",
         r"(animate-bounce|scroll\s+to\s+explore|animate-pulse\s+.*chevron)",
         "Motion compensating for a hero that does not invite scrolling. Needs a "
         "reduced-motion path if it stays (G2).",
         quick=True),

    # ----------------------------------------------------------------------
    # Category C — copy clichés
    # ----------------------------------------------------------------------
    Rule("C1", "Not-X-but-Y cadence",
         "C",
         r"(not\s+just\s+an?\s+\w+|isn['’]t\s+(?:a|an|just)\s+\w+[^.]{0,40}it['’]s\s+)",
         "Rhythm substituting for a claim. State what the thing does, with a noun "
         "a user would use."),

    Rule("C3", "Emoji as structure",
         "C",
         r"^\s*(?:[#>*-]|<h[1-6][^>]*>)\s*[\U0001F300-\U0001FAFF☀-➿]",
         "Decoration that does not survive translation or a screen reader. Use "
         "type weight and spacing for hierarchy.",
         flags=re.IGNORECASE | re.MULTILINE),

    Rule("C4", "Unanchored superlative",
         "C",
         r"\b(seamless(?:ly)?|effortless(?:ly)?|blazing(?:ly)?\s+fast|10x|"
         r"cutting[- ]edge|state[- ]of[- ]the[- ]art|game[- ]chang\w+|"
         r"revolutionar\w+|next[- ]gen\w*)\b",
         "A claim with nothing behind it. Replace with a specific fact, or cut. "
         "Any number used must be real (D1).",
         quick=True),

    # ----------------------------------------------------------------------
    # Category D — integrity (grep-able portion only)
    # ----------------------------------------------------------------------
    Rule("D1", "Possible fabricated proof",
         "D",
         r"(trusted\s+by|used\s+by\s+[\d,]+|join\s+[\d,]+\+?\s+\w+|"
         r"\b\d[\d,.]*(?:k|m|\+)\s+(?:users|teams|customers|developers|companies)\b|"
         r"testimonial|★{2,}|⭐{2,})",
         "NOT an aesthetic finding. Never rewrite into better-sounding fake proof "
         "and never generate new proof (G3). If it might be real, ASK before "
         "removing it.",
         quick=True),

    Rule("D5", "Decorative pulse",
         "D",
         r"animate-pulse",
         "Reveals a page never used with slow or absent data when it stands in for "
         "a real loading state. Skeletons must respect reduced-motion (G2)."),

    Rule("D6", "Blanket hover motion",
         "D",
         r"(transition-all|hover:scale-1\d\d|hover:-translate-y|hover:shadow-2xl)",
         "Separate FEEDBACK from DECORATION. Feedback on real controls must stay — "
         "removing it is an accessibility regression (G1). Cut transforms on things "
         "that are not controls.",
         quick=True),
]

COMPILED = [(r, re.compile(r.pattern, r.flags)) for r in RULES]

# Presence checks rather than pattern matches.
PRESENCE = [
    ("D3", "Privacy policy", "D", ("privacy",),
     "Draft only, clearly labelled as needing review by a qualified person, with "
     "an explicit list of the facts only the user can supply (G4)."),
    ("D4", "Terms of service", "D", ("terms", "tos"),
     "Same rule as D3. Never binding text presented as complete (G4)."),
]

EM_DASH_LIMIT = 3.0        # per 500 words, from tells.md C2
EM_DASH_MIN_WORDS = 150    # below this the ratio is noise


def walk(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".venv")]
        for name in filenames:
            if os.path.splitext(name)[1].lower() not in EXTENSIONS:
                continue
            path = os.path.join(dirpath, name)
            try:
                if os.path.getsize(path) > MAX_BYTES:
                    continue
            except OSError:
                continue
            yield path


def read(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def scan_text(rel: str, text: str, quick: bool) -> list[Finding]:
    found: list[Finding] = []
    lines = text.splitlines()

    for rule, regex in COMPILED:
        if quick and not rule.quick:
            continue
        if rule.exts and os.path.splitext(rel)[1].lower() not in rule.exts:
            continue
        seen_lines: set[int] = set()
        for match in regex.finditer(text):
            line_no = text.count("\n", 0, match.start()) + 1
            if line_no in seen_lines:
                continue
            seen_lines.add(line_no)
            excerpt = lines[line_no - 1].strip() if line_no <= len(lines) else ""
            found.append(Finding(rule.tell, rule.name, rule.category, rel,
                                 line_no, excerpt[:160], rule.note))
            if len(seen_lines) >= 8:      # enough to establish the pattern
                break

    # C2 is a density measure, not a pattern match.
    if not quick and os.path.splitext(rel)[1].lower() in {".md", ".mdx", ".html", ".htm"}:
        words = len(text.split())
        dashes = text.count("—")
        if words >= EM_DASH_MIN_WORDS and dashes:
            per_500 = dashes * 500.0 / words
            if per_500 > EM_DASH_LIMIT:
                found.append(Finding(
                    "C2", "Em dash density", "C", rel, 0,
                    f"{dashes} em dashes across {words} words ({per_500:.1f} per 500)",
                    "A cadence rather than a character. Vary sentence construction — "
                    "do NOT find-and-replace the character, which fixes nothing.",
                ))

    return found


def scan_presence(root: str) -> list[Finding]:
    found: list[Finding] = []
    names = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel_dir = os.path.relpath(dirpath, root)
        for entry in list(dirnames) + list(filenames):
            names.append(os.path.join(rel_dir, entry).lower())
    blob = "\n".join(names)

    for tell, name, category, keys, note in PRESENCE:
        if not any(key in blob for key in keys):
            found.append(Finding(tell, f"{name} — absent", category, "(site-wide)",
                                 0, "no matching route, page, or file", note))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", nargs="?", default=".")
    parser.add_argument("--json", action="store_true", dest="as_json",
                        help="machine-readable output")
    parser.add_argument("--quick", action="store_true",
                        help="high-signal subset only")
    args = parser.parse_args()

    root = os.path.abspath(args.directory)
    if not os.path.isdir(root):
        print(f"not a directory: {root}", file=sys.stderr)
        return 2

    findings: list[Finding] = []
    scanned = 0
    for path in walk(root):
        text = read(path)
        if text is None:
            continue
        scanned += 1
        findings.extend(scan_text(os.path.relpath(path, root), text, args.quick))

    if not args.quick:
        findings.extend(scan_presence(root))

    findings.sort(key=lambda f: (f.category, f.tell, f.path, f.line))

    if args.as_json:
        print(json.dumps({
            "root": root,
            "files_scanned": scanned,
            "findings": [asdict(f) for f in findings],
        }, indent=2))
        return 0

    print(f"\ndesign-tells scan — {scanned} files under {root}")
    print("read-only: nothing was modified\n")

    if not findings:
        print("  no mechanical tells matched.")
        print("  this is step 1 of 2. the structural, copy and integrity tells")
        print("  still need reading — see SKILL.md step 2.\n")
        return 0

    by_tell: dict[str, list[Finding]] = {}
    for finding in findings:
        by_tell.setdefault(f"{finding.tell} {finding.name}", []).append(finding)

    for key in sorted(by_tell):
        group = by_tell[key]
        print(f"  [{group[0].category}] {key} — {len(group)} site(s)")
        for finding in group[:6]:
            where = f"{finding.path}:{finding.line}" if finding.line else finding.path
            print(f"      {where}")
            if finding.excerpt:
                print(f"        {finding.excerpt}")
        if len(group) > 6:
            print(f"      … and {len(group) - 6} more")
        print(f"        note: {group[0].note}")
        print()

    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.category] = counts.get(finding.category, 0) + 1
    summary = "  ".join(f"{cat}={counts.get(cat, 0)}" for cat in "ABCD")
    print(f"  {len(findings)} candidates    {summary}")
    print("\n  every line above is a CANDIDATE, not a defect. each tell has a")
    print("  context where it is correct — see references/tells.md, and record")
    print("  'Justified' as a real verdict. no score is produced, by design.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
