#!/usr/bin/env python3
"""Reject frozen multiword translations in the authored phrase add-on."""

from pathlib import Path
import re
import sys


# Fixed utterances whose whole Russian form is intentional. Keep this list
# narrow: case-bearing wishes, noun phrases and prepositional phrases need W
# components so the surrounding sentence can govern and inflect them.
FIXED = {
    "goodbye": "Dдо свидания",
    "nice to meet you": "Dприятно познакомиться",
    "pleased to meet you": "Dприятно познакомиться",
    "long time no see": "Dдавно не виделись",
    "wait a minute": "Dподождите минутку",
    "bless you": "Dбудьте здоровы",
    "get well soon": "Dпоправляйтесь скорее",
}


def check(path: Path) -> list[str]:
    errors = []
    seen = set()
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "*" not in line:
            errors.append(f"{path}:{number}: missing key*reading separator")
            continue
        key, reading = line.split("*", 1)
        if key in seen:
            errors.append(f"{path}:{number}: duplicate key {key!r}")
        seen.add(key)
        if key in FIXED and reading != FIXED[key]:
            errors.append(f"{path}:{number}: reviewed fixed formula changed: {key}")
        if "*$" in line:
            continue  # T4 action spaces are executable syntax, not W tails.
        if reading.startswith("D") and any(c.isspace() for c in reading[1:]) and FIXED.get(key) != reading:
            errors.append(f"{path}:{number}: frozen multiword D reading: {key}")
        if reading.startswith("D") and re.search(r"[A-Za-z]", reading[1:]):
            errors.append(f"{path}:{number}: tagged components require a W reading: {key}")
        if reading.startswith("W") and any(c.isspace() for c in reading):
            errors.append(f"{path}:{number}: untagged space in W reading: {key}")
    return errors


if __name__ == "__main__":
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dictionary/phrases.txt")
    problems = check(source)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    print(f"phrase formulas valid: {source}")
