#!/usr/bin/env python3
"""Build the small DIC/RUS proof of concept from a pinned OpenRussian snapshot.

Given all three upstream CSVs in a directory, run:

    python3 tools/export_openrussian_poc.py --full-snapshot /path/to/csvs

This checks the pinned full-file hashes and extracts only representative
source rows. The C importer builds indexed CP866 BASE.DIC and BASE.RUS images
from those excerpts and the repository's existing LTech base dictionaries.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/openrussian-poc"
SOURCE = DATA / "source"
MANIFEST_PATH = DATA / "source-manifest.json"
SAMPLE_WORDS = {
    "nouns": ["стол", "книга", "окно", "человек", "ребёнок", "время", "путь"],
    "verbs": ["читать", "писать", "идти", "быть", "дать", "есть", "хотеть", "мочь", "учиться"],
    "adjectives": ["белый"],
}
NOUN_SLOTS = ["sg_nom", "sg_gen", "sg_dat", "sg_acc", "sg_inst", "sg_prep",
              "pl_nom", "pl_gen", "pl_dat", "pl_acc", "pl_inst", "pl_prep"]
VERB_SLOTS = ["imperative_sg", "imperative_pl", "past_m", "past_f", "past_n", "past_pl",
              "presfut_sg1", "presfut_sg2", "presfut_sg3",
              "presfut_pl1", "presfut_pl2", "presfut_pl3"]
ADJECTIVE_SLOTS = ["comparative", "superlative", "short_m", "short_f", "short_n", "short_pl"] + [
    f"decl_{g}_{c}" for g in ("m", "f", "n", "pl")
    for c in ("nom", "gen", "dat", "acc", "inst", "prep")
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"Missing TSV header in {path}")
        return list(reader.fieldnames), list(reader)


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def extract_snapshot(source_dir: Path, expected: dict) -> None:
    for name in SAMPLE_WORDS:
        path = source_dir / f"{name}.csv"
        if not path.is_file():
            raise SystemExit(f"Missing pinned source file: {path}")
        want = expected[name]["sha256"]
        got = sha256(path)
        if got != want:
            raise SystemExit(f"Checksum mismatch for {path.name}: expected {want}, got {got}")
        fields, rows = read_tsv(path)
        selected = []
        for line, row in enumerate(rows, start=2):
            if row.get("bare") in SAMPLE_WORDS[name]:
                selected.append({**row, "source_row": str(line)})
        absent = sorted(set(SAMPLE_WORDS[name]) - {row["bare"] for row in selected})
        if absent:
            raise SystemExit(f"Pinned {name}.csv is missing sample lemmas: {', '.join(absent)}")
        write_tsv(SOURCE / f"{name}.tsv", fields + ["source_row"], selected)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-snapshot", type=Path,
                        help="directory containing pinned nouns.csv, verbs.csv, adjectives.csv")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if args.full_snapshot:
        extract_snapshot(args.full_snapshot, manifest["files"])

    sample_hashes = {}
    for name in SAMPLE_WORDS:
        path = SOURCE / f"{name}.tsv"
        if not path.is_file():
            raise SystemExit(f"Missing sample source excerpt: {path}")
        sample_hashes[name] = {"sha256": sha256(path), "bytes": path.stat().st_size}
    if args.full_snapshot:
        manifest["sample_files"] = sample_hashes
        MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    elif manifest.get("sample_files") != sample_hashes:
        raise SystemExit("Sample source excerpt checksum differs from source-manifest.json")

    for name in SAMPLE_WORDS:
        path = SOURCE / f"{name}.tsv"
        if not path.is_file():
            raise SystemExit(f"Missing sample source excerpt: {path}")
        _fields, rows = read_tsv(path)
        absent = sorted(set(SAMPLE_WORDS[name]) - {row["bare"] for row in rows})
        if absent:
            raise SystemExit(f"Sample excerpt lacks {name}: {', '.join(absent)}")

    print("OpenRussian source excerpts are ready for the C binary dictionary builder")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
