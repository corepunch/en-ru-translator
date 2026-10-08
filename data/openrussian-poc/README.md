# Full OpenRussian dictionary import

The checked-in source tables contain every row from the four public OpenRussian
backup exports: 26,982 nouns, 14,871 verbs, 11,941 adjectives, and 5,031 other
entries (58,825 source rows total). The C builder compiles them into standalone
indexed binary `.DIC` and `.RUS` databases. This snapshot produces 95,552 DIC
records, 53,491 native-format RUS records, and 58,772 compact morphology
records, including 4,978 shared templates.

`.DIC` maps English glosses to Russian lexemes and literal expressions. `.RUS`
keeps the original indexed LTech format, with one-byte CP866 headwords and
native binary POS codes. The sibling `BASE.MORPH` carries OpenRussian morphology
references and shared templates. Each form is represented as a byte count to
trim from its headword and a one-byte CP866 suffix. Noun case slots and verb
tense, person, and imperative slots stay distinct; the runtime imperative flag
selects those imperative slots. The template records contain no copied source
columns, glosses, field names, or row IDs. For example, `people` maps directly
to `люди`, which keeps LTPRO's original plural-only noun code and paradigm 30.

## Source and encoding

The data is from repository commit
[`50e210c4803237779cb562bc1abcea529066031c`](https://github.com/Badestrand/russian-dictionary/commit/50e210c4803237779cb562bc1abcea529066031c),
licensed CC BY-SA 4.0. The upstream repository says these checked-in CSVs are
older backup exports; this import covers every row in those four files, not a
claim that the 2021 backup is the latest live OpenRussian database. The source
URLs and SHA-256 hashes are pinned in `source-manifest.json`; see
`ATTRIBUTION.md` for attribution details.

The source TSVs are UTF-8. Headwords and template suffixes remain one-byte
CP866 for the current Lua runtime. The importer removes combining stress marks
and transliterates characters CP866 cannot represent; 109 unsupported
codepoints in stored dictionary text were replaced in this snapshot. The
checked-in TSVs retain the complete UTF-8 source values.

## Download, build, and inspect

Clone the upstream data with GitHub CLI, verify its pinned CSV hashes, and
regenerate the complete TSV tables:

```sh
gh repo clone Badestrand/russian-dictionary /tmp/openrussian-source
python3 tools/export_openrussian_poc.py --full-snapshot /tmp/openrussian-source
```

Build the binary databases:

```sh
cc -std=c11 -Wall -Wextra -Werror tools/openrussian_db.c -o /tmp/openrussian_db -liconv
/tmp/openrussian_db build data/openrussian-poc/source \
  data/openrussian-poc/BASE.DIC data/openrussian-poc/BASE.RUS \
  data/openrussian-poc/BASE.MORPH
```

`info FILE` reports the binary image size and record count; `find FILE HEADWORD`
shows matching dictionary records. The builder also adds a few high-priority
English function-word and common-verb readings so source homonyms do not
override the translator's basic grammar.

## Parity examples

The original LTPRO captures and exact comparison cases are checked in:

- 20 noun/verb sentences: `test/ltpro/openrussian-cases.json` and
  `test/ltpro/openrussian-reference.json`
- Four phrases: `test/ltpro/openrussian-phrase-cases.json` and
  `test/ltpro/openrussian-phrase-reference.json`
- Five additional words and sentences from the full tables:
  `test/ltpro/openrussian-full-cases.json` and
  `test/ltpro/openrussian-full-reference.json`

All 29 cases pass exact paragraph comparison with the generated full tables.
This verifies those examples, not every English gloss or expression. OpenRussian
word senses can differ from LTPRO's older choices; for example, OpenRussian
maps `because` to `потому что`, while this LTPRO build uses `поскольку`.
Exploratory full-vocabulary checks also exposed unresolved ambiguity and word
order cases: `City.` currently selects `городской`, and `Cold water.` is
reordered. These remain translation-quality issues despite the complete import.

```sh
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-cases.json \
  --reference test/ltpro/openrussian-reference.json \
  --data LTGOLD \
  --dictionary data/openrussian-poc/BASE.DIC \
  --russian data/openrussian-poc/BASE.RUS
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-phrase-cases.json \
  --reference test/ltpro/openrussian-phrase-reference.json \
  --data LTGOLD \
  --dictionary data/openrussian-poc/BASE.DIC \
  --russian data/openrussian-poc/BASE.RUS
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-full-cases.json \
  --reference test/ltpro/openrussian-full-reference.json \
  --data LTGOLD \
  --dictionary data/openrussian-poc/BASE.DIC \
  --russian data/openrussian-poc/BASE.RUS
```
