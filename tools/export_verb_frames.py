#!/usr/bin/env python3
"""List the verbs LTGOLD codes as taking a that-clause.

A native verb record's first digit is its frame (`know*V1знать`,
`decide*V11решать`). Native T3 rule 78 reads a nonzero frame before `that` as a
complementizer; with frame 0 (every OpenRussian verb) `They know that Russia
will help` became `знают этой России`. This writes `verb<TAB>digit` for each
single-word V/Z key whose first digit is not 0, to
openrussian/overlays/verb-frames.txt.

    python3 tools/export_verb_frames.py LTGOLD/BASE.DIC
"""
import re
import sys

seen = {}
for line in open(sys.argv[1], "rb").read().split(b"\n"):
    if b"*" not in line:
        continue
    key, value = line.split(b"*", 1)
    if not re.fullmatch(rb"[a-z]+", key):
        continue
    match = re.match(rb"([VZ])(\d)", value)
    if match and match.group(2) != b"0":
        seen.setdefault(key.decode(), match.group(2).decode())
for key in sorted(seen):
    print(f"{key}\t{seen[key]}")
