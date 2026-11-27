#!/usr/bin/env python3
"""Run the public document translator on publisher-wrapped UTF-8 prose."""
from argparse import ArgumentParser
from pathlib import Path
import re
import subprocess
import sys


def prepare(text, start_at, paragraphs):
    # Gutenberg plain-text editions include license/header material.
    text = re.sub(r"\A.*?^\*\*\* START OF .*?\*\*\*[^\n]*\n",
                  "", text, count=1, flags=re.MULTILINE | re.DOTALL)
    text = re.split(r"^\*\*\* END OF ", text, maxsplit=1, flags=re.MULTILINE)[0]
    if start_at:
        index = text.find(start_at)
        if index < 0:
            raise ValueError(f"opening marker not found: {start_at}")
        text = text[index:]
    blocks = [re.sub(r"[ \t]*\n[ \t]*", " ", part.strip())
              for part in re.split(r"\n(?:[ \t]*\n)+", text) if part.strip()]
    if not blocks:
        raise ValueError("input contains no prose")
    blocks = blocks[:paragraphs]
    return "\n\n".join(blocks) + "\n", len(blocks)


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--start-at", help="start at this exact text marker")
    parser.add_argument("--paragraphs", type=int, help="maximum paragraph count")
    parser.add_argument("--lua", default="lua")
    args = parser.parse_args()
    if args.paragraphs is not None and args.paragraphs < 1:
        parser.error("--paragraphs must be positive")
    try:
        prepared, count = prepare(args.source.read_text(encoding="utf-8-sig"),
                                  args.start_at, args.paragraphs)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    root = Path(__file__).resolve().parent.parent
    print(f"{args.source.name}: {count} paragraphs, {len(prepared.split())} words",
          file=sys.stderr)
    return subprocess.run([args.lua, "init.lua", "--document"],
                          cwd=root, input=prepared.encode("utf-8")).returncode


if __name__ == "__main__":
    raise SystemExit(main())
