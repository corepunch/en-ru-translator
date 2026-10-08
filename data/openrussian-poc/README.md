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
the engine's one-byte encoding. Lowercase `ё` is normalized to the engine's
CP866-compatible `F0` byte.

Run sentence examples using the generated images:

```sh
lua tools/openrussian_poc.lua
```

The standalone sample intentionally contains only the selected OpenRussian
content. Function words such as articles and pronouns are outside this sample,
so the current demo leaves some English words untranslated and sentence-level
case handling is incomplete.

The sample contains seven nouns, nine verb lemmas (including both `писать`
homonyms), and one adjective. Sentence translation still uses the LTPRO
executable for its grammar and sentence-processing tables, but does not load
the legacy `BASE.DIC` or `BASE.RUS` files.
