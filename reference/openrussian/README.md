# Full OpenRussian dictionary import

The checked-in source tables contain every row from the four public OpenRussian
backup exports: 26,982 nouns, 14,871 verbs, 11,941 adjectives, and 5,031 other
entries (58,825 source rows total). The C builder compiles them into standalone
indexed binary `.DIC` and `.RUS` databases. This snapshot produces 95,552 DIC
records, 53,491 native-format RUS records, and 58,772 compact morphology
records, including 4,978 shared templates.
The checked-in `BASE.DIC` applies twelve reviewed structural word readings from
`function-words.txt`, replacing all records for those exact keys, and adds two
phrase rules from `phrases.txt`. It contains 95,521 DIC records after replacement.

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
/tmp/openrussian_db build reference/openrussian/source \
  reference/openrussian/BASE.DIC reference/openrussian/BASE.RUS \
  reference/openrussian/BASE.MORPH
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/function-words.txt --replace --in-place
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/phrases.txt --replace --in-place
```

`info FILE` reports the binary image size and record count; `find FILE HEADWORD`
shows matching dictionary records. The builder also adds a few high-priority
English function-word and common-verb readings so source homonyms do not
override the translator's basic grammar.

## Curated phrases

Keep reviewed UTF-8 `english key*reading` rows in `phrases.txt`; keep structural
function-word readings in `function-words.txt`. Apply both batches after the C
build. Import converts to CP866, replaces exact keys, and rebuilds the `.DIC`
index. Repeating an import is safe. `.RUS` and `.MORPH` contain Russian
morphology; English-to-Russian phrases belong in `.DIC`.

```text
how XR[*]*$Dкак\`PР01у``MMWMJ0nдело`\
what <X>`up`[*]*$DDWDкакnдело\ $ \
```

Both entries use native T4 dictionary subrules, tested in original LTPRO.
The first is one grammatical family: auxiliary **X**, personal pronoun **R**,
and sentence boundary `[*]`. **P** means preposition; **B/b** mean infinitival
`to`. The head becomes `Dкак`. Backticked context actions supply `PР01у` and
change the pronoun to an `M` composite reading while preserving its node's
number/person/gender. The empty `M` component uses those fields for normal
oblique pronoun generation. `J0` closes the prepositional group before plural
`nдело`, so morphology generates nominative `дела`. The default `you` is informal
singular. The custom pre-T1 retained-slot execution path has been removed.

Original LTPRO executes this construction but produces `у его/ее/их` in the third
person. Lua's agreement/generation fixes give `у него/неё/них`. The translations
intentionally improve those forms and phrase casing while using native syntax.
A remaining native rule-order interaction affects `How is it?`: a later
sentence-final `it` rule overrides the composite, producing original `Как У Это?`
and Lua `Как у это?`.

The imported default readings previously classified `are` as a noun, `is` as a
lexical verb, and `you` as fixed `W` text. Those readings could not satisfy the
`X/R` pattern. The reviewed function-word batch supplies real auxiliary and
pronoun readings, also available to ordinary grammatical rules outside greetings.
It avoids auxiliary backreferences into imported stem idioms such as the
unrelated `be in` gloss. The historical LTGOLD dictionaries remain unchanged.

`How's` expands to `how is`; smart apostrophes normalize at the encoding boundary.
`[*]` excludes `How are you feeling?` and similar longer clauses. The grammatical
rule also accepts a period, exclamation mark, or no final punctuation. The
`what` idiom uses a native T4 context rule: `<X>` allows the auxiliary to remain
or have been removed by question cleanup, lexical `up` identifies the idiom,
and `[*]` requires sentence end. The native tail action removes its context
words. `What's up there?` is excluded. Final punctuation is emitted separately;
the former Lua-only punctuation-key matcher has been removed.

`test/greetings_test.lua` checks the default dictionary, retained metadata,
additional lexical pronoun readings, contractions, case generation, casing, and
nearby inputs. These phrases intentionally improve on the original translator;
original captures remain separate. The
[dictionary-writing skill](../../skills/ltgold-dictionary-writing/SKILL.md)
records manual references and the authoring workflow.

## Parity examples

The original LTPRO captures and exact comparison cases are checked in:

- 20 noun/verb sentences: `test/ltpro/openrussian-cases.json` and
  `test/ltpro/openrussian-reference.json`
- Four phrases: `test/ltpro/openrussian-phrase-cases.json` and
  `test/ltpro/openrussian-phrase-reference.json`
- Five additional words and sentences from the full tables:
  `test/ltpro/openrussian-full-cases.json` and
  `test/ltpro/openrussian-full-reference.json`

These 29 captures describe the generated full tables before the curated
function-word corrections. They remain historical evidence; changes to closed
classes can intentionally change their Lua results. They do not verify every
English gloss or expression. OpenRussian
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
  --dictionary reference/openrussian/BASE.DIC \
  --russian reference/openrussian/BASE.RUS
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-phrase-cases.json \
  --reference test/ltpro/openrussian-phrase-reference.json \
  --data LTGOLD \
  --dictionary reference/openrussian/BASE.DIC \
  --russian reference/openrussian/BASE.RUS
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-full-cases.json \
  --reference test/ltpro/openrussian-full-reference.json \
  --data LTGOLD \
  --dictionary reference/openrussian/BASE.DIC \
  --russian reference/openrussian/BASE.RUS
```
