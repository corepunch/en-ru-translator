#!/usr/bin/env python3
"""Export a reproducible UTF-8 lexicon from pinned public datasets."""
import argparse
from collections import defaultdict
from functools import lru_cache
import hashlib
from pathlib import Path
import re
import sqlite3
import unicodedata

import pymorphy3

SOURCES = {
    "wikdict": "0a547256d3868d0eebe38e0b6c4306e70f7dadb12622c3877249ae117de8d7a7",
    "wordnet": "640db279c949a88f61f851dd54ebbb22d003f8b90b85267042ef85a3781d3a52",
}
EN = re.compile(r"[a-z]+(?:[-'][a-z]+)*$")
RU = re.compile(r"[а-яё]+(?:-[а-яё]+)*$")
POS = {"Noun": "n", "Verb": "v", "Adjective": "a", "Adverb": "r"}
RPOS = {"n": {"NOUN", "NPRO"}, "v": {"INFN", "VERB"}, "a": {"ADJF"}, "r": {"ADVB", "PRED"}}
CASES = {"nomn": "n", "gent": "g", "datv": "d", "accs": "a", "ablt": "i", "loct": "l"}
GENDERS = {"masc": "m", "femn": "f", "neut": "n"}
PERSON = {"1per": "1", "2per": "2", "3per": "3"}


def verify(path, digest):
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f"input hash mismatch: {path}")


def clean(value):
    return unicodedata.normalize("NFC", value).replace("\u0301", "").replace("\u0300", "").lower().strip()


def delta(lemma, word):
    i = 0
    while i < len(lemma) and i < len(word) and lemma[i] == word[i]:
        i += 1
    return f"{len(lemma[:i].encode())}:{word[i:]}"


def form_key(tag, pos):
    num = "p" if tag.number == "plur" else "s"
    gender = GENDERS.get(tag.gender, "m")
    case = CASES.get(tag.case)
    if pos == "n" and case:
        return num + case + ("x" if "Af-p" in tag else "")
    if pos == "a" and tag.POS == "ADJF" and case:
        key = (num if num == "p" else gender) + case
        return key + ("+" if tag.animacy == "anim" else "-" if tag.animacy == "inan" else "")
    if pos == "v" and tag.POS == "PRTS" and tag.voice == "pssv":
        return "q" + (num if num == "p" else gender)
    if pos == "v" and tag.POS == "VERB":
        if tag.mood == "impr" and "excl" in tag:
            return "i" + num
        if tag.mood != "indc":
            return None
        if tag.tense == "past":
            return "t" + (num if num == "p" else gender)
        if tag.tense in ("pres", "futr") and tag.person in PERSON:
            return ("f" if tag.tense == "futr" else "p") + num + PERSON[tag.person]
    return None


def write_shards(out, prefix, rows, manifest):
    payload = bytearray()
    count = 0
    def flush():
        nonlocal count
        if not payload:
            return
        count += 1
        name = f"{prefix}-{count:02}.tsv"
        (out / name).write_bytes(payload)
        manifest.append(f"{prefix}\t{name}")
        payload.clear()
    for row in rows:
        raw = (row.rstrip("\t") + "\n").encode()
        if len(payload) + len(raw) > 180000:
            flush()
        payload.extend(raw)
    flush()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("wikdict", type=Path)
    p.add_argument("wordnet_archive", type=Path)
    p.add_argument("output", type=Path)
    args = p.parse_args()
    for source, path in (("wikdict", args.wikdict), ("wordnet", args.wordnet_archive)):
        verify(path, SOURCES[source])
    import tarfile
    with tarfile.open(args.wordnet_archive, "r:gz") as tar:
        exceptions = {pos: tar.extractfile(f"WordNet-3.0/dict/{name}.exc").read().decode("ascii")
                      for name, pos in (("noun", "n"), ("verb", "v"), ("adj", "a"), ("adv", "r"))}
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    morph = pymorphy3.MorphAnalyzer()
    if morph.dictionary.meta["source_revision"] != "417150":
        raise ValueError("expected OpenCorpora revision 417150")
    curated = (Path(__file__).resolve().parents[1] / "dictionary" / "vocabulary.tsv").read_text(encoding="utf-8")
    fields = [line.split("\t") for line in curated.splitlines() if line and not line.startswith("#")]

    @lru_cache(maxsize=None)
    def parse(word, pos):
        for item in morph.parse(word):
            if item.tag.POS in RPOS[pos] and item.is_known and "Abbr" not in item.tag:
                return item
        return None

    rows = defaultdict(list)
    c = sqlite3.connect(args.wikdict.resolve().as_uri() + "?mode=ro", uri=True)
    query = """SELECT lower(written_rep),lexentry,trans_list FROM translation
               WHERE lexentry IS NOT NULL AND trans_list IS NOT NULL
               ORDER BY importance DESC, is_good DESC, score DESC, lexentry, trans_list"""
    for en, uri, translations in c.execute(query):
        k = re.search(r"__([A-Za-z_]+)__[0-9]+$", uri)
        pos = POS.get(k[1]) if k else None
        if not pos or not EN.fullmatch(en):
            continue  # Never import multiword translations or phrases.
        targets = rows[(en, pos)]
        if len(targets) >= 2:
            continue
        for raw in translations.split(" | "):
            word = clean(raw)
            if not RU.fullmatch(word):
                continue
            item = parse(word, pos)
            if item and RU.fullmatch(item.normal_form) and item.normal_form not in targets:
                targets.append(item.normal_form)
                if len(targets) == 2:
                    break
    # Independently authored lexical frames are kept separate from the export.
    used = {(ru, pos) for (_, pos), targets in rows.items() for ru in targets if pos != "r"}
    used |= {(f[2], f[1]) for f in fields if f[1] in ("n", "v", "a")}
    forms = []
    for word, pos in sorted(used):
        item = parse(word, pos)
        if not item:
            continue
        tag = item.tag
        flags = (GENDERS.get(tag.gender, "m") + ("+" if tag.animacy == "anim" else "-") +
                 ("t" if tag.transitivity == "tran" else "i" if tag.transitivity == "intr" else "-") +
                 ("f" if tag.aspect == "perf" else "-"))
        values = {}
        for inf in item.lexeme:
            if {"Infr", "Arch", "V-oy", "V-ey"} & inf.tag.grammemes:
                continue
            key = form_key(inf.tag, pos)
            if key and key not in values and inf.word != word and RU.fullmatch(inf.word):
                values[key] = delta(word, inf.word)
            elif key and key not in values and inf.word == word:
                values[key] = "="
        forms.append("\t".join((word, pos, flags, ",".join(k + "=" + v for k, v in sorted(values.items()) if v != "="))))

    lex = ["\t".join((en, pos, "|".join(targets))) for (en, pos), targets in sorted(rows.items()) if targets]
    known = {key for key, val in rows.items() if val} | {(f[0],f[1]) for f in fields}
    exc_rows = []
    for pos, raw in exceptions.items():
        for line in raw.splitlines():
            form, *lemmas = line.split()
            useful = [word for word in lemmas if (word, pos) in known]
            if EN.fullmatch(form) and useful:
                exc_rows.append("\t".join((form, pos, "|".join(useful))))
    for pattern in ("lex-*.tsv", "forms-*.tsv", "exceptions-*.tsv"):
        for old in out.glob(pattern):
            old.unlink()
    manifest = []
    write_shards(out, "lex", lex, manifest)
    write_shards(out, "forms", forms, manifest)
    write_shards(out, "exceptions", sorted(exc_rows), manifest)
    (out / "assets.tsv").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    print(f"{len(lex)} English lemma/POS combinations, {len(forms)} Russian paradigms, {len(exc_rows)} English exception rows")


if __name__ == "__main__":
    main()
