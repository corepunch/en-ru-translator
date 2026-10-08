# OpenRussian dictionary integration POC

This sample feeds source-listed OpenRussian noun, verb, and adjective forms into
the sentence translator. The C builder creates standalone binary LTech
dictionaries with one-byte CP866-compatible text and rebuilt indexes. It reads
only the checked-in OpenRussian TSV excerpts: the DIC maps English glosses to
Russian lemmas, and the RUS stores Russian lexeme metadata and named forms.
The demo passes these files as its only DIC and RUS inputs.

The source records are stored as indexed RUS entries with a `Q` extension:

```text
lemma*Qn*sg_gen*form
lemma*Qa*decl_m_gen*form
lemma*Qv*ipf*presfut_sg1*form
```

They remain ordinary single-byte records inside the LTech binary envelope.
The runtime reads them by lemma and named form slot. Standard RUS lexeme
metadata is generated into the same standalone RUS file.

The standalone DIC also contains a small set of hand-authored English grammar
entries for articles and `I`, plus irregular plural aliases (`people`,
`children`). Those keep the sample sentences parseable without loading the
legacy English dictionary. The selected sample does not aim for general English
vocabulary coverage.

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

The 20 sentence cases and their original LTPRO captures are in
`test/ltpro/openrussian-cases.json` and `test/ltpro/openrussian-reference.json`.
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
homonyms), and one adjective. Sentence translation still uses the LTPRO
executable for its grammar and sentence-processing tables, but does not load
the legacy `BASE.DIC` or `BASE.RUS` files. To match LTPRO's preferred spelling,
the importer normalizes source `ё` to `е` in the generated tables.
