# OpenRussian dictionary integration POC

This sample feeds source-listed OpenRussian noun, verb, and adjective forms into
the existing sentence translator. The C builder creates compact binary LTech
dictionary overlays with one-byte CP866-compatible text and rebuilt indexes.
The DIC overlay contains source English aliases absent from `LTGOLD/BASE.DIC`;
aliases already present keep their existing grammatical readings. The RUS
overlay contains source forms and any needed lexeme metadata. Lua loads these
alongside the existing dictionaries and uses the source forms when generating
noun, adjective, and verb forms.

The source records are stored as indexed RUS entries with a `Q` extension:

```text
lemma*Qn*sg_gen*form
lemma*Qa*decl_m_gen*form
lemma*Qv*ipf*presfut_sg1*form
```

They remain ordinary single-byte records inside the LTech binary envelope.
The runtime ignores `Q` records during legacy morphology-code lookup and reads
them by lemma and named form slot. Existing standard RUS codes remain available
for grammar metadata and fallback forms.

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

Build the C database utility and emit binary `.DIC` and `.RUS` images by
merging those excerpts into the original dictionaries:

```sh
cc -std=c11 -Wall -Wextra -Werror tools/openrussian_db.c -o /tmp/openrussian_db -liconv
/tmp/openrussian_db build data/openrussian-poc/source LTGOLD/BASE.DIC LTGOLD/BASE.RUS \
  data/openrussian-poc/BASE.DIC data/openrussian-poc/BASE.RUS
```

The utility supports `info FILE` and `find FILE HEADWORD` for inspecting the
binary database. The source excerpt is UTF-8; the generated overlays use the
engine's one-byte encoding. Lowercase `ё` is normalized to the engine's
CP866-compatible `F0` byte.

Run sentence examples using the generated images:

```sh
lua tools/openrussian_poc.lua
```

```text
The child reads a book. -> Ребенок читает книгу.
I read a book. -> Я читаю книгу.
The table is white. -> Стол{1.таблица} белый.
```

The sample contains seven nouns, nine verb lemmas (including both `писать`
homonyms), and one adjective. The compact binaries contain only OpenRussian
overlay records. The sentence engine retains its existing base dictionaries
and layers these source forms into morphology generation.
