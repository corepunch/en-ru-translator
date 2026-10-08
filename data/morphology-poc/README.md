# OpenCorpora morphology prototype

This small sample checks whether source-listed Russian noun, verb, and
adjective forms can replace the executable-backed paradigm tables behind a
Lua provider. It contains 17 representative lemmas, including irregular and
suppletive forms. It is a morphology-only sample; English DIC senses remain a
separate source-selection and attribution task.

## Pinned source

- Source: [OpenCorpora Russian morphological dictionary](https://opencorpora.org/?page=downloads), XML format 0.92, dictionary revision 417150.
- Snapshot artifact: `pymorphy3-dicts-ru` 2.4.417150.4580142, built from that OpenCorpora revision.
- Artifact: [PyPI source distribution](https://pypi.org/project/pymorphy3-dicts-ru/2.4.417150.4580142/), SHA-256 `39ab379d4ca905bafed50f5afc3a3de6f9643605776fbcabc4d3088d4ed382b0`.
- Data license: [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). The PyMorphy3 compiler/runtime code is MIT; that code license does not replace the dictionary data license.
- Upstream package metadata records 391,778 source lexemes, 258,607 links, and 3,456 compiled paradigms. Package build timestamp: 2022-01-08; this is a pinned historic snapshot, not the newest OpenCorpora export.

The direct OpenCorpora download endpoint timed out during this investigation.
The PyPI artifact is therefore used as a pinned, checksummed snapshot for the
prototype. Before production adoption, refresh from a current official export
and record its XML checksum and revision.

## Reproduce and use

```sh
python3 -m pip install -r data/morphology-poc/requirements.txt
python3 tools/export_opencorpora_poc.py
lua tools/open_morphology_poc.lua
```

`lexemes.lua` is generated data: it keeps the source's prefix/suffix rows and
the per-lemma paradigm assignment and stem. `core/open_morphology.lua` applies
those rows and selects all forms matching a requested set of grammemes. For
example, `{"NOUN", "gent", "sing"}` asks for singular genitive nouns, while
`{"VERB", "1per", "sing", "pres", "indc"}` asks for a first person singular
present indicative verb. An optional third argument excludes grammemes such as
`Abbr` or `Supr` when a caller needs to omit abbreviations or superlatives.
Requests use OpenCorpora grammeme names directly, avoiding numeric IDs from
LTGOLD.

See [data attribution](ATTRIBUTION.md) and the machine-readable
[source manifest](source-manifest.json) for the share-alike notice and pinned
artifact details.

This source is suitable for the Russian morphology side of issue 9. It does
not provide the English-to-Russian senses needed to replace `BASE.DIC`; that
needs its own pinned, licensed source and a joining policy that preserves
senses and target lexeme IDs. English Wiktionary extracts remain a candidate.
