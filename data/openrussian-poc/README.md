# OpenRussian dictionary integration POC

This sample compiles the checked-in OpenRussian TSV excerpts into standalone
binary `.DIC` and `.RUS` files with one-byte CP866-compatible text and rebuilt
indexes. `.DIC` indexes English glosses. `.RUS` stores every imported source
column, unchanged in meaning and keyed by its OpenRussian `source_row` id. The
runtime reads named OpenRussian form columns directly; it does not convert
those forms into LTPRO paradigm records.

The `.RUS` file also has a small set of POS metadata records used to connect the
OpenRussian lexemes to the translator's existing grammar tags. That adapter
does not contain inflection tables. When the source row lacks the exact aspect
the sentence needs, the engine can still use the executable's morphology
tables. The demo passes the generated `.DIC` and `.RUS` as its only dictionary
files.

The standalone DIC also contains a small set of hand-authored English grammar
entries for articles and `I`, plus irregular plural aliases (`people`,
`children`). The `others` table contributes 24 multiword expression rows to
the RUS image and their English glosses to DIC. Fixed expressions use a literal
phrase reading; they remain ordinary binary dictionary records. These keep the
sample sentences parseable without loading the legacy English dictionary. The
selected sample does not aim for general English vocabulary coverage.

## Pinned source

The OpenRussian sample is from repository commit
`50e210c4803237779cb562bc1abcea529066031c` (2021-08-09), licensed CC BY-SA
4.0. Its checked-in CSVs are older backup exports, so refresh the source and
pin new hashes before production adoption. See [attribution](ATTRIBUTION.md)
and [source manifest](source-manifest.json). OpenCorpora through PyMorphy3 is
also retained as a morphology-only comparison in `data/morphology-poc/`.

## Build and inspect

Regenerate the small, checksummed source excerpts when needed:

```sh
python3 tools/export_openrussian_poc.py
```

Build the C database utility and emit standalone binary `.DIC` and `.RUS`
images from the OpenRussian excerpts:

```sh
cc -std=c11 -Wall -Wextra -Werror tools/openrussian_db.c -o /tmp/openrussian_db -liconv
/tmp/openrussian_db build data/openrussian-poc/source \
  data/openrussian-poc/BASE.DIC data/openrussian-poc/BASE.RUS
```

The utility supports `info FILE` and `find FILE HEADWORD` for inspecting the
binary database. The source excerpt is UTF-8; the generated dictionaries use
the engine's one-byte encoding. Lowercase `ё` is normalized to `е` to match
LTPRO's preferred spelling in this parity sample.

Run sentence examples using the generated images:

```sh
lua tools/openrussian_poc.lua
```

The 20 noun/verb sentence cases and their original LTPRO captures are in
`test/ltpro/openrussian-cases.json` and `test/ltpro/openrussian-reference.json`.
Four captured phrase cases are in `test/ltpro/openrussian-phrase-cases.json` and
`test/ltpro/openrussian-phrase-reference.json`. The 20 noun/verb cases and four
phrase cases pass exact paragraph comparison. Other imported expressions can
differ from LTPRO's older English glosses or translations (for example,
OpenRussian's `because` gloss translates as `потому что` while this LTPRO build
uses `поскольку`); this small phrase sample does not claim that every
OpenRussian expression reproduces LTPRO.
Recheck exact parity while forcing the Lua engine to use only these generated
DIC and RUS files:

```sh
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-cases.json \
  --reference test/ltpro/openrussian-reference.json \
  --data LTGOLD \
  --dictionary data/openrussian-poc/BASE.DIC \
  --russian data/openrussian-poc/BASE.RUS
```

The capture reference is produced by the original LTPRO executable and its
supplied assets. The Lua comparison receives the new DIC and RUS paths
explicitly. This POC's sample sentences currently match all 20 captured
translations exactly; it is not a general-purpose English dictionary.

The sample contains seven nouns, nine verb lemmas (including both `писать`
homonyms), one adjective, and 24 multiword expression rows. Sentence
translation still uses the LTPRO executable for its grammar and
sentence-processing tables, but does not load
the legacy `BASE.DIC` or `BASE.RUS` files. To match LTPRO's preferred spelling,
the importer normalizes source `ё` to `е` in the generated tables.
