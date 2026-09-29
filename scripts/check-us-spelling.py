#!/usr/bin/env python3
"""Fail on British spellings in the instruction files.

Prose only. Fenced blocks and inline code are blanked before matching, so a real
identifier named Colour or a serialise() method is never flagged and never
renamed. Comments inside a fenced block follow the same spelling rule but are
not machine-checked, because nothing distinguishes them from surrounding code.

Usage:
    check-us-spelling.py PATH [PATH ...]

A PATH may be a file or a directory; directories are scanned recursively for
*.md. Exit 0 when clean, 1 on any hit, 2 when given no arguments.
"""

import glob
import os
import re
import sys

# British form -> US form. Word-boundary matched, case-insensitive.
# Deliberately excluded: forms Merriam-Webster lists as standard US variants
# (ax/axe, burnt as an adjective, grey in proper nouns).
PAIRS = [
    # -our
    ("behaviour", "behavior"),
    ("colour", "color"),
    ("favour", "favor"),
    ("flavour", "flavor"),
    ("honour", "honor"),
    ("labour", "labor"),
    ("neighbour", "neighbor"),
    ("rumour", "rumor"),
    ("endeavour", "endeavor"),
    ("candour", "candor"),
    ("rigour", "rigor"),
    ("vigour", "vigor"),
    ("armour", "armor"),
    ("harbour", "harbor"),
    ("humour", "humor"),
    ("odour", "odor"),
    ("savour", "savor"),
    ("splendour", "splendor"),
    ("valour", "valor"),
    ("parlour", "parlor"),
    ("clamour", "clamor"),
    # -yse
    ("analyse", "analyze"),
    ("paralyse", "paralyze"),
    ("catalyse", "catalyze"),
    # -re
    ("centre", "center"),
    ("metre", "meter"),
    ("theatre", "theater"),
    ("fibre", "fiber"),
    ("litre", "liter"),
    ("calibre", "caliber"),
    ("sombre", "somber"),
    ("spectre", "specter"),
    # -ce vs -se
    ("defence", "defense"),
    ("offence", "offense"),
    ("pretence", "pretense"),
    ("licence", "license"),
    ("practise", "practice"),
    # silent -e
    ("judgement", "judgment"),
    ("acknowledgement", "acknowledgment"),
    ("ageing", "aging"),
    # single vs double consonant
    ("fulfil", "fulfill"),
    ("enrolment", "enrollment"),
    ("instalment", "installment"),
    ("skilful", "skillful"),
    ("wilful", "willful"),
    ("appal", "appall"),
    ("distil", "distill"),
    ("labelled", "labeled"),
    ("labelling", "labeling"),
    ("cancelled", "canceled"),
    ("cancelling", "canceling"),
    ("modelling", "modeling"),
    ("modelled", "modeled"),
    ("signalling", "signaling"),
    ("signalled", "signaled"),
    ("travelled", "traveled"),
    ("travelling", "traveling"),
    ("fuelled", "fueled"),
    ("totalled", "totaled"),
    ("marvellous", "marvelous"),
    ("counsellor", "counselor"),
    # miscellaneous
    ("grey", "gray"),
    ("sceptic", "skeptic"),
    ("sceptical", "skeptical"),
    ("scepticism", "skepticism"),
    ("mould", "mold"),
    ("smoulder", "smolder"),
    ("plough", "plow"),
    ("storey", "storey_US_story"),
    ("tyre", "tire"),
    ("kerb", "curb"),
    ("aluminium", "aluminum"),
    ("programme", "program"),
    ("speciality", "specialty"),
    ("aeroplane", "airplane"),
    ("manoeuvre", "maneuver"),
    ("orientated", "oriented"),
    ("whilst", "while"),
    ("amongst", "among"),
    ("learnt", "learned"),
    ("spelt", "spelled"),
    ("dreamt", "dreamed"),
    ("leapt", "leaped"),
    ("cheque", "check"),
    ("gaol", "jail"),
]

# -ise / -isation families, generated so the table above stays readable.
ISE_STEMS = [
    "organ",
    "real",
    "recogn",
    "priorit",
    "summar",
    "minim",
    "maxim",
    "standard",
    "normal",
    "initial",
    "serial",
    "apolog",
    "emphas",
    "util",
    "custom",
    "optim",
    "special",
    "author",
    "categor",
    "character",
    "critic",
    "familiar",
    "general",
    "item",
    "legitim",
    "memor",
    "modern",
    "synchron",
    "visual",
    "capital",
    "central",
    "commercial",
    "computer",
    "digit",
    "final",
    "formal",
    "hospital",
    "ideal",
    "local",
    "legal",
    "material",
    "mobil",
    "monet",
    "neutral",
    "personal",
    "polar",
    "popular",
    "random",
    "rational",
    "stabil",
    "steril",
    "symbol",
    "sympath",
    "synthes",
    "systemat",
    "theor",
    "vapor",
    "vocal",
]
_SUFFIXES = [
    ("ise", "ize"),
    ("ises", "izes"),
    ("ised", "ized"),
    ("ising", "izing"),
    ("isation", "ization"),
    ("isations", "izations"),
]
for _stem in ISE_STEMS:
    for _brit, _us in _SUFFIXES:
        PAIRS.append((_stem + _brit, _stem + _us))

# "storey" has no clean single-word US form in every sense; fix the entry.
PAIRS = [(b, "story") if a == "storey_US_story" else (b, a) for b, a in PAIRS]

# Inflected forms. A base pair differs by an internal substitution, so the same
# suffix attaches to both sides. Without this the scanner passed "neighbouring"
# and "colours" while flagging "neighbour" and "colour", which is the gap that
# let five inflections survive a full sweep.
#
# Some generated forms are not words ("centreing"). A non-word costs nothing: it
# simply never matches. The risk being avoided is the false negative.
_INFLECTIONS = (
    "s",
    "ing",
    "ed",
    "er",
    "ers",
    "less",
    "ful",
    "able",
    "ably",
    "al",
    "ally",
    "ist",
    "ists",
    "ism",
)
# A stem ending in "e" drops it before a vowel-initial suffix: analyse becomes
# analysed, not analyseed. Both sides drop identically.
_E_DROP = ("ed", "ing", "er", "ers", "able", "ably", "ist", "ists", "ism")
_inflected = []
for _b, _a in PAIRS:
    for _suffix in _INFLECTIONS:
        _inflected.append((_b + _suffix, _a + _suffix))
    if _b.endswith("e") and _a.endswith("e"):
        for _suffix in _E_DROP:
            _inflected.append((_b[:-1] + _suffix, _a[:-1] + _suffix))
PAIRS = PAIRS + _inflected

_seen = set()
TABLE = []
for _b, _a in PAIRS:
    if _b not in _seen:
        _seen.add(_b)
        TABLE.append((_b, _a))

PATTERN = re.compile(r"\b(" + "|".join(re.escape(b) for b, _ in TABLE) + r")\b", re.I)
REPLACEMENT = {b.lower(): a for b, a in TABLE}


def strip_code(text):
    """Return lines with fenced blocks and inline code blanked out."""
    lines = []
    in_fence = False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            lines.append("")
            continue
        if in_fence:
            lines.append("")
            continue
        lines.append(re.sub(r"`[^`]*`", "``", line))
    return lines


def scan_file(path):
    """Return a list of (line_number, found, want, context) for one file."""
    hits = []
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
    except (OSError, UnicodeDecodeError) as exc:
        sys.stderr.write(f"cannot read {path}: {exc}\n")
        raise
    for number, line in enumerate(strip_code(raw), 1):
        for match in PATTERN.finditer(line):
            found = match.group(1)
            hits.append((number, found, REPLACEMENT[found.lower()], line.strip()))
    return hits


def collect(paths):
    targets = []
    for path in paths:
        if os.path.isfile(path):
            targets.append(path)
        elif os.path.isdir(path):
            targets += sorted(glob.glob(os.path.join(path, "**", "*.md"), recursive=True))
        else:
            sys.stderr.write(f"no such path: {path}\n")
            return None
    return targets


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    targets = collect(argv[1:])
    if targets is None:
        return 3
    if not targets:
        sys.stderr.write("no markdown files found under: {}\n".format(" ".join(argv[1:])))
        return 3

    total = 0
    for target in targets:
        hits = scan_file(target)
        if not hits:
            continue
        print(target)
        for number, found, want, context in hits:
            print(f"  {number:5d}  {found:<20} -> {want:<20} | {context[:88]}")
        total += len(hits)

    if total:
        print(f"\n  FAIL  {total} British spelling(s) in {len(targets)} file(s) scanned")
        return 1
    print(f"  PASS  US spelling across {len(targets)} file(s), {len(TABLE)} forms checked")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
