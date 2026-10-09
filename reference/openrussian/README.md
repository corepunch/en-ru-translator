# Full OpenRussian dictionary import

The checked-in source tables contain every row from the four public OpenRussian
backup exports: 26,982 nouns, 14,871 verbs, 11,941 adjectives, and 5,031 other
entries (58,825 source rows total). The C builder compiles them into standalone
indexed binary `.DIC` and `.RUS` databases. This snapshot produces 95,552 DIC
records, 53,492 native-format RUS records, and 58,772 compact morphology
records, including 4,978 shared templates.
The checked-in `BASE.DIC` applies 57 reviewed structural word readings from
`function-words.txt` (pronouns, auxiliaries and 45 prepositions), replacing all
records for those exact keys, and 47 phrase entries from `phrases.txt`. It
contains 95,435 DIC records after replacement.

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
python3 tools/ltech_dict.py delete reference/openrussian/BASE.DIC \
  --keys-file reference/openrussian/removed-headwords.txt --in-place
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/function-words.txt --replace --in-place
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/phrases.txt --replace --in-place
```

`removed-headwords.txt` lists generated OpenRussian literal phrases that would
consume input before a curated T4 subrule can see it (for example the builder's
`you are welcome*WDпожалуйста`). A curated subrule has a different key, so
`--replace` cannot remove those literals. Always rebuild from the C builder
output; this sequence reproduces the checked-in `BASE.DIC` byte for byte.

Rows from `others.tsv` have no part of speech. The builder emits each as a
one-component `W` composite with native adverb class `D` (`at all*WDсовсем`),
following LTGOLD's usual `D` coding for such words; the `W` wrapper keeps
reordering from moving these unclassified prepositions and conjunctions. It
formerly emitted `W#…#`, but native `#` marks nontranslated names and reads a
leading с/м/ж as gender, so 542 readings lost their first letter
(`according to` → `огласно`).

`info FILE` reports the binary image size and record count; `find FILE HEADWORD`
shows matching dictionary records. The builder also adds a few high-priority
English function-word and common-verb readings so source homonyms do not
override the translator's basic grammar.

## Prepositions and noun flags

Each preposition in `function-words.txt` is one native record: class `P` or
`p`, the governed case, and the Russian preposition, with packed alternatives
where the original uses them (`for*PРдля`, `of*PР`,
`after*pРпослеDвпоследствииJ2после того, как`). LTGOLD's entries are evidence;
deliberate differences, omitted homographs, and original captures are in
[preposition verification](../../test/ltpro/prepositions/README.md).

Agreement chooses в/на and из/с/от from noun flags in `.RUS`: bit 1 (`0x02`)
marks animates and bit 6 (`0x40`) nouns that take на. The builder sets the
first from OpenRussian `animate` and the second from the curated
[`na-nouns.txt`](na-nouns.txt), read from the source directory's parent. It
previously wrote `0xc0` for every noun.

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
Native rule order still affects `How is it?`: a later sentence-final `it` rule
overrides the composite, producing original `Как У Это?`. Lua preserves the
authored equivalent and generates `Как у него дела?`; the regression also checks
`How's it?`.

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

The complete source has 27 `W` composites, eight native T4 subrules, and ten
single-word `D` equivalents. There are no frozen multiword Russian payloads.
For example, `happy birthday*WPТсNденьPРNрождение` gives instrumental `день`
and genitive `рождение`; `best wishes*WAнаилучшийnпожелание` agrees and declines
after `with`. The structural `with*PТсJс помощью` reading supplies instrumental
government. The builder also adds nominal `спасибо` as a neuter indeclinable
noun, using native no-declension metadata, so `AбольшойNспасибо` agrees normally.

The `you` subrule requires lexical `are`, `welcome`, and a final boundary. It
accepts `You're welcome.` without consuming `You are welcome to stay.` or
`You were welcome.`. Imperatives use normal morphology and the default informal
register: `Извини меня.`, `Будь здоров.`, and `Поправляйся скорее.`. The composed
past greeting spells out its subject: `Мы давно не виделись.`. OpenRussian
normalizes ё to е in generated forms, including `С днем рождения.`.

`test/common_phrases_test.lua` checks every source entry, capitalization,
contractions, punctuation, longest-phrase selection, and protected/partial-word
nonmatches. Original-program evidence, the per-entry review, known differences,
and isolated fixture construction are in
[curated-phrase verification](../../test/ltpro/curated-phrases/README.md).
Some entries deliberately choose historical senses: `by the way` becomes
`между прочим` and `after all` becomes `в конце концов`.

Clause-final idioms are boundary subrules rather than literal keys, so they do
not consume a following construction. `after `all`[j,*]` matches before a comma
or sentence end but leaves “After all the guests left” alone. `not at all` has
two native subrules: standalone `Нисколько.` before `[,*]`, and `совсем не`
otherwise, so “It is not at all easy” keeps its negation. The native
``at `all`[PJj,C*]`` rule covers clause-final “at all”. `my `pleasure`[*]`
answers thanks with `Пожалуйста.` without consuming “My pleasure is great.”
The builder's literal `not at all`, `at all`, and `after all` readings are removed
before import.

Original LTPRO differs from Lua for these subrules in two engine respects. It
marks a matched comma so the next word is glued to it (`Нисколько,благодарности`),
and a later subrule can resurrect a node an earlier subrule deleted in the same
pass (`Нисколько Совсем.`). Lua keeps normal comma spacing and skips deleted
heads. A sentence-initial `p` preposition such as `after` makes the grammar
retag its comma as clause junction `j`, so the rule uses native `[j,*]`
(compare historical ``as `it``is`[j,*)]``); with `[,*]` the original printed
“После все, он знает.”

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
