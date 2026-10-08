# OpenRussian DIC/RUS proof of concept

OpenRussian is a promising single source for the first issue 9 prototype: its
noun, verb, and adjective CSVs contain English glosses, grammatical metadata,
and named columns for the source-listed Russian forms. The sample preserves
those forms as explicit tables, including irregular forms, alternative forms,
and verb aspect partners. The Lua adapter maps named feature requests to
source slots without LTPRO table IDs.

OpenCorpora through PyMorphy3 is also present as a morphology-only comparison
in `data/morphology-poc/`: it provides compact shared paradigms, lemma stems,
and assignments, but no English senses. OpenRussian is the current end-to-end
POC choice because one licensed snapshot supplies both the bilingual glosses
and the Russian form tables. Its comma/semicolon gloss inversion remains a
quality risk to review before it can seed a larger DIC.

The pinned source is repository commit `50e210c4803237779cb562bc1abcea529066031c`
(2021-08-09), under CC BY-SA 4.0. This is a reproducible snapshot, not a claim
that its data is current: the upstream README says the CSV files are older
backup exports. Before production use, refresh from OpenRussian's current
database and pin those exports separately. See [attribution](ATTRIBUTION.md)
and [source manifest](source-manifest.json).

## Build and run

To extract the sample again from full source CSVs, place the three pinned files
in one directory and run:

```sh
python3 tools/export_openrussian_poc.py --full-snapshot /path/to/openrussian-csvs
lua tools/openrussian_poc.lua
```

The extractor verifies each complete-file SHA-256 before selecting rows. With
the committed small excerpts, regenerate only the DIC/RUS outputs by running:

```sh
python3 tools/export_openrussian_poc.py
lua tools/openrussian_poc.lua
```

`BASE.DIC` is an English-gloss index into RUS lexeme IDs. It keeps the raw
English sense group with each alias. `BASE.RUS` stores one row for each Russian
form variant, with grammatical slot names, lexeme metadata, and both the
original stress-marked spelling and unaccented output. Both files use UTF-8
tab-separated rows with a versioned comment header and quoted fields when
needed. This is a new editable prototype format; it is not binary-compatible
with LTGOLD's legacy files.

The source uses commas between alternative glosses and semicolons between
groups; this inversion is a prototype policy and needs review before bulk
conversion. The Lua adapter reads these files directly and maps named feature
requests to source form slots. Example lookups from the generated sample:

```text
table [sg_gen] -> стола
child [pl_nom] -> дети
read [presfut_sg1] -> читаю
go [presfut_sg1] -> иду
write [presfut_sg1] -> пишу
white [decl_m_gen] -> белого
```

These demonstrate word and form lookup in the POC adapter, not full sentence
translation integration.

Sample coverage includes seven nouns, nine verb lemmas (with both `писать`
homonyms retained), and one adjective. The small source excerpts and generated
tables are CC BY-SA 4.0; the complete upstream CSV snapshots are not copied
into this repository.
