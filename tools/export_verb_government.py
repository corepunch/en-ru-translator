#!/usr/bin/env python3
"""List LTGOLD's verb government byte for lemmas the OpenRussian build also has.

OpenRussian carries no valency, so the builder coded every verb 0x88
(transitive). LTGOLD's BASE.RUS keeps the native byte (0x80 intransitive,
0x84 dative, 0x90 instrumental, 0x88 accusative, ...) as the third byte of a
verb record. This writes `lemma<TAB>hex` for every shared verb whose byte is
whose government differs from the plain accusative (bits 0x3F other than
0x08; 0xC8 carries a different flag and stays as built), to
openrussian/overlays/verb-government.txt.

    python3 tools/export_verb_government.py LTGOLD/BASE.RUS openrussian/BASE.RUS
"""
import sys

def verbs(path):
    result = {}
    for line in open(path, "rb").read().split(b"\n"):
        if b"*V" not in line:
            continue
        key, value = line.split(b"*", 1)
        if len(value) > 2 and value[:1] == b"V":
            result[key] = value[2]
    return result

historical = verbs(sys.argv[1])
current = verbs(sys.argv[2])
for key in sorted(historical):
    if key in current and historical[key] & 0x3F != 0x08:
        print(f"{key.decode('cp866')}\t{historical[key]:02x}")
