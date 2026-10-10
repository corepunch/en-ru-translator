---
name: dictionary-writing
description: "Write and review LTGOLD/SARMA English–Russian dictionary entries for en-ru-translator, including grammatical phrase patterns, W readings, and function-word tags. Use when enriching or correcting its .DIC dictionary."
---

# LTGOLD dictionary writing

Work from the en-ru-translator repository root. The normal checkout is
`/Users/igor/Developer/en-ru-translator`; use the current checkout when working
elsewhere. Read its `AGENTS.md`, [authoring reference](references/authoring.md),
and [code and value reference](references/codes.md) before choosing tags or
phrase syntax. The code reference covers every documented dictionary class,
additional Lua/internal tags, numeric fields, pattern operators, subrule controls,
and worked breakdowns of the greeting entries. Consult it rather than guessing
what a letter or digit means; distinguish dictionary codes from runtime tags.

The default English dictionary is `openrussian/BASE.DIC`. All authored
English entries live in `openrussian/dictionary.txt`, under `## function-words`,
`## irregular-verbs`, `## native-readings` and `## phrases`; Russian lemma
attributes (verb government, aspect, на-nouns) in `openrussian/lexemes.tsv` and
English word attributes in `openrussian/words.tsv`. Theme dictionaries are
`openrussian/themes/<name>.txt` (same `key*code` rows), compiled to
`openrussian/<NAME>.DIC` and loaded with `--dic-overlay`. There are no other
sources. Historical `LTGOLD/BASE.DIC` is a separate reference,
not an automatically merged source. English phrase rules belong in `.DIC`;
`.RUS` and `.MORPH` supply Russian morphology.

## Quick path: add a phrase to phrases.txt

Each step takes seconds; do all of them.

1. **Look up evidence.** `python3 tools/ltech_dict.py find LTGOLD/BASE.DIC 'good night'`
   shows the original's coding; the same command on `openrussian/BASE.DIC`
   shows what is installed now, including generated OpenRussian literals.
2. **Pick the shape** (tags: `N` noun, `n` plural noun, `A` adjective, `V` verb,
   `D` adverb/interjection, `K` particle, `R` pronoun, `C` conjunction,
   `P`+case+preposition; cases `И Р Д В Т П`; an empty `PР`/`PТ` only sets case):

   | Expression | Shape | Verified example |
   | --- | --- | --- |
   | One fixed Russian word | `D` | `of course*Dконечно` |
   | Russian words that agree or decline | `W` + tagged lemmas | `good night*WPРAспокойныйNночь`, `happy birthday*WPТсNденьPРNрождение` |
   | Imperative | `WV…` | `get well soon*WVпоправлятьсяDскорее` |
   | Valid only standalone or clause-final | boundary subrule | ``you `are``welcome`[*]*$Dпожалуйста\  \``; `[,*]` also allows a comma; use `[j,*]` after a sentence-initial `p` preposition |
   | Variable pronoun/auxiliary | typed subrule | `how XR[*]*$…` (see codes reference) |

   Never put Russian text after `#`, never freeze a multiword sentence in `D`,
   and lowercase lemmas except proper names (`NРождество`).

   A multiword Russian lemma keeps its space inside one tag. LTGOLD's own
   `deal with*ZVWVиметь делоPТс/N.WNделоPТс` and `dealt*EWEиметь дело\deal`
   use `Vиметь дело` and print the fixed idiom (`имеет дело`, `имел дело`).
   Splitting it into `VиметьNдело` makes `дело` agree with the subject
   (`Он имеет дела`, verified against original LTPRO). Do not "repair" a
   space in a copied LTGOLD record. Tag each word separately only when each
   word must inflect independently (`WAспокойныйNночь`).

   A phrasal verb is its own key. `иметь дело с` is `deal with`, not `deal`.
   Do not hang the preposition's object on the one-word key.

   An idiom is its own key too, and an article in it is a placeholder, not a
   literal word. LTGOLD codes this class as `make <TAO>`agreement`*$заключать`:
   `<TAO>` matches the article (`a`, `the`, `an`) and an optional adjective.
   So `make a deal` is

   ```
   make <TAO>`deal`*$заключать\$`Nсделка`\
   ```

   not `make a deal*WVзаключатьNсделка`. `Russia made a deal` and `They made
   the deal` both give `заключила/заключили сделку`.
3. **Edit** the `## phrases` section of `openrussian/dictionary.txt`. The
   builder emits no multiword literals, so nothing generated can hide a
   subrule. A multiword English phrase is always a `dictionary.txt` row.
4. **Rebuild:** `sh tools/rebuild_openrussian.sh` (always from source).
5. **Check and record:** `lua init.lua 'Good night.'`, then add lines to
   `test/translations.txt`: `phrase:<exact key> | Good night. => Спокойной ночи.`,
   one variant (capitals, contraction, or another case form), and a `!>` line
   for a nearby sentence the phrase must not consume.
6. **Original program:** `python3 tools/ltpro_try_entries.py --entry '<row>'
   [--delete '<historical key>'] 'Good night.' '<context>'` prints the original
   next to Lua. New syntax must work there; note deliberate differences.
7. **Regressions:** `sh test/run_all.sh`, then `lua tools/dict_compare.lua` and
   review every changed corpus line.
8. Before committing: `sh tools/rebuild_openrussian.sh --verify`.

## Changing the sense of a single word

`BASE.DIC` is generated; a hand edit is lost on rebuild and shows up as a
failing `--verify`. The only durable way to change a word's reading is a row in the
`## native-readings` section of `openrussian/dictionary.txt` (`--replace`).

1. `find` the word in `LTGOLD/BASE.DIC` and in `openrussian/BASE.DIC`. If the
   installed first reading already equals LTGOLD's, add nothing.
2. Copy LTGOLD's record whole: every `.` second sense, `{gloss}` note and
   `;`-separated alternative. A trimmed copy loses the native alternatives
   (`power*NN.мощность{ability;electricity};право{the right}`, not
   `power*Nмощность`; `plant*ZV.устанавливатьN.завод{facility};растение{shrub}`).
3. Deviate only on purpose, state why in the commit, and try both with
   `tools/ltpro_try_entries.py --entry '<row>' '<sentences>'`. Example:
   native `deal*ZVWVиметь дело/Nсделка` makes `a good deal` → `порядком` and
   shadows the `make a deal` idiom, so `deal*Nсделка` is kept and the verb is
   `deal with`.
4. Add a `native-reading:<word>` case to `test/translations.txt` with the
   Lua output, rebuild, and run `--verify`.

## Before pushing a dictionary PR

- `sh tools/rebuild_openrussian.sh --verify` passes (the checked-in `.DIC`
  is exactly what the sources build).
- `sh test/run_all.sh` passes.
- Every expected line in `test/translations.txt` was copied from the actual
  `lua init.lua` output after the final rebuild, never from the PR text.
- The PR body's "after" examples equal those lines and describe the final
  entries, not an earlier attempt.
- Sources stay `upstream/*.tsv` + `lexemes.tsv` + `words.tsv` → builder →
  `dictionary.txt`, plus `themes/*.txt`. No other source files, no post-build
  delete or blocklist step: fix the builder or add a row. Search docs, tools and tests for any
  file name you remove.
- Docstrings and prose you edit still read as complete sentences and runnable
  commands.

## Quick fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| Word printed uninflected or frozen | `D`/fixed text where words should agree | Tagged lemmas in a `W` composite |
| First letter с/м/ж missing | Russian text in a `#` component | `D` or `WD` |
| Idiom swallows a longer sentence (“You are welcome to stay”) | Literal key | Boundary subrule ending `[*]` or `[,*]` |
| Subrule fails only before a comma after a sentence-initial preposition | Comma retagged `j` | `[j,*]` |
| Subrule fails before a comma after a sentence-initial `P` (`at`, `in`) | Comma retagged `;` | `[j;,*]` |
| Single-word key prints a stray case letter (`Рдо`) | `W` reading without an input class | Prefix the class: `goodbye*DDWPРдоNсвидание` |
| Sentence-initial `see …` subrule undone (`Смотри`) | Native T4 rule rewrites initial `see` to `Vсмотри` | Do not author it; the original behaves the same |
| Imperfective verb needed where grammar asks for perfective (future, imperative) | Builder-written `.RUS` partner (`видеть`→`увидеть`) | Name the verb on both sides of `\|`: `Vпоправляться\|поправляться` |
| -s verb form translated as a noun (`Он производство`) | Plural-noun gloss literal shadows suffix analysis | Builder emits native `z` (`works*zработатьnпроизводство\work`); check `find` |
| Ordinary clause replaced by one word or a stray sense (`Rising prices` → `рост`) | A gloss fragment became a key | Fix the builder's gloss parsing (`parse_glosses` in `tools/openrussian_db.c`), not a delete list |
| Basic English word translated as a content word (`this` → `сего`, `us` → `Америка`) | OpenRussian has no closed-class grammar | Add LTGOLD's native reading to `function-words.txt` |
| Subrule on a sentence-final one-word head never fires | Native: no subrules attach at the end | Choose another shape; the original behaves the same |
| Wrong в/на or из/с/от | Noun flags in `.RUS` | Add the noun to `na-nouns.txt`; animacy comes from OpenRussian |
| Capitalized lemma does not decline | Lowercase lemma missing from `.RUS` | `python3 tools/ltech_dict.py find openrussian/BASE.RUS <lemma>` |
| Expected ё, got е | OpenRussian normalizes ё | Expect е |
| A `function-words.txt` row deleted other meanings | `--replace` removes every record for the key | Pack alternatives into the one record, or leave the word out |
| Test would need broken Russian to pass | Unrelated defect around the phrase | Check the owned span with `~>`; never bless the defect |
| Third `\`-section of a subrule does nothing | Only the selector's first character is read | Put the edit in the tail action: `` \$`Dв`$`Dвиду` `` |
| Need a word that only begins phrases | No standalone meaning | Native placeholder `corned*:`; alone it prints the English word |
| Unsure what a code does natively | Unverified syntax | Add a probe to `test/ltpro/dictionary-syntax/probes.json` and capture it |

Honor the requested scope. For a whole-file or batch review, inventory every
entry and complete an entry-by-entry review; fixing the user's example does not
complete the rest. Historical presence and native syntactic validity are
evidence, not proof of a suitable grammatical encoding or correct translation.

Take no shortcuts. Use verified dictionary syntax, grammatical tags, reusable
patterns, and normal agreement and morphology. Do not hardcode surface forms,
enumerate grammatical variants, or use `#` literals or uninflected tails to hide
missing matcher, agreement, morphology, or casing support. Fix and verify the
underlying defect instead. Fixed text must reflect a genuinely fixed expression
and follow the documented format; it is not a workaround for one failing example.
Do not declare success from the target sentence alone.

For multiword Russian equivalents, use tagged lemma components with agreement
and case government, including conventional greetings such as “happy birthday”.
Do not label an entire sentence `D` merely because it is a familiar expression,
or mechanically wrap frozen text in `W`. A single-word `D` equivalent or truly
fixed text can be appropriate; record the grammatical reason. Preserve intended
meaning and register, and explain deliberate changes. See the authoring
reference's [whole-file review lessons](references/authoring.md#whole-file-phrase-review-lessons)
for verified examples and diagnostic pitfalls.

Recover the native LTGOLD mechanism before changing the translator. Search
`BASE.DIC` for comparable entries, trace the relevant pipeline stage, and test
candidate syntax in the original executable. Do not introduce Lua-specific
syntax or matching behavior to compensate for an incomplete understanding of
LTGOLD. An apparent missing feature is an investigation task, not permission to
invent an extension. Native short-expression rules already use `[*]` boundaries.

For a phrase family, identify the invariant meaning and the variable grammatical
classes. Prefer one native typed pattern that preserves the original nodes'
grammatical fields when that expresses the family. For example, auxiliaries `am/are/is` are **X**, personal
pronouns are **R**, **P** means preposition, and **B/b** mean infinitival `to`.
Do not guess tags from initials or enumerate pronoun variants of one grammatical
construction. Use literal entries for genuinely fixed expressions.

Search existing entries and the LTGOLD manual before adding a rule. Inspect the
active lexical tags as well as the dictionary text: a fixed `W#ты#` reading
cannot serve as an `R` pronoun. Fix missing structural readings or engine support
when necessary; preserve lexical metadata through captures and let normal
agreement/generation decline the word. Document verified native behavior and
remaining port defects separately; do not assume absent native support.

Test every entry you add or change, including structural function-word readings;
do not sample a batch or infer coverage from another entry's passing result.
Keep an explicit entry-to-case mapping and persistent regression cases. Verify
the rebuilt default dictionary through the actual engine, and verify authored
syntax in the original executable with the capture workflow below. Capture
experimental dictionaries separately from untouched historical assets. Inspect
each result; executing successfully or reproducing a frozen expected string
does not establish correct grammar. For each inflecting or variable entry, test
agreement/case or person/number variants and a nearby context that must not be
consumed. Record the reason for retaining any genuinely fixed expression.
An entry with failing or missing verification is unfinished; report it explicitly
instead of declaring the whole file complete.

Rebuild from the C builder output (never by importing into an existing
`BASE.DIC`) and confirm the documented sequence reproduces the checked-in files.
Put each translation check on one line in `test/translations.txt`, tagged with
its source entry, and run `sh test/run_all.sh`. Before accepting a builder
change or a new class of entries, compare old and new translations of the whole
captured corpus and review every changed line. Cover grammatical variants,
contractions, capitalization, and nearby contexts the rule must not consume.
For variable words, also exercise an additional lexical reading to establish
that matching depends on tags rather than an English spelling list. Run the
standard regression suite after engine changes.

When checking original behavior or translation parity, follow the repository's
capture instructions: the original executable is the oracle. Use explicit
temporary cases/output paths, preserve captured text, and report original and
Lua outputs separately. A better Lua translation can intentionally differ;
never alter a capture to make it agree.
Report entry coverage, grammatical regression results, and exact native parity
separately. A reviewed native difference is not an exact match; a negative
matching test does not certify the surrounding translation. Never turn a known
grammatical defect into an accepted expectation just to make tests pass.

## Fast path for a sentence that translates badly

Diagnose by class of defect, not by sentence. Each failure below was a shared
data or engine gap that fixed many sentences at once.

1. **Trace before editing.** `lua init.lua --trace 'sentence'` writes the
   translation to stdout and a token/rule trace to stderr. Read the trace
   before adding a dictionary entry or a phrase. Do not invent a `D` clause
   to hide a tag the trace already explains.

   ```sh
   lua init.lua --trace 'He has to stop.'
   ```

   stderr is tab-separated:

   ```text
   translation:    Он должен остановиться.
   # tokens
   2    source=He    tag=R    kind=W    reading=он    text=Он    person=3
   3    source=has    tag=U    kind=W    reading=должен
   4    source=stop    tag=V    kind=W    text=остановиться
   # rules
   T2    #21    nodes=3-4    handler=0    pattern=U<KdD>Z    action=@$V
   # tags    *RUV*
   ```

   `tag` is the live class after the grammar tables. `lookup` is the
   dictionary headword when one matched; a capitalized word with no `lookup`
   was transliterated, not missing a name entry. `# rules` lists every T1–T4
   record that matched, with its pattern and action. A phrase subrule is
   marked `sub`. No DOSBox and no LTPRO capture.
2. **Probe in one call.** Run every sub-phrase together
   (`while read s; do lua init.lua --trace "$s"; done < list`) and capture the
   original for the same list in one `tools/ltpro_capture.py` run. Do not
   probe one sentence per command.
3. **Look the word up in both dictionaries first**
   (`tools/ltech_dict.py find LTGOLD/BASE.DIC w` and `openrussian/BASE.DIC w`).
   A native record that the OpenRussian build lacks is a data fix, not a
   rule. Search raw bytes (`d.find('свыше'.encode('cp866'))` across `LTGOLD/*`)
   to find which native rule produces an unexplained original word.
4. **Symptom to cause table** (all verified here):

   | Symptom | Cause | Fix |
   | --- | --- | --- |
   | `He opened` → `открыто`, `is reading` → noun | `-ed`/`-ing` gloss hides the verb | builder `add_inflected_homographs` |
   | `called/killed/lied` untranslated | native suffix rule undoes doubled letter / `-ied` | builder `add_native_suffix_gaps` |
   | `will always supply` reads supply as noun | adverb in a `W` composite | `plain-adverbs.txt` |
   | `Russia announced` → neuter verb | capitalized `.RUS` headword | builder lowers headwords |
   | `main factor` → `Главное фактор` | empty gender column | builder infers from lemma ending |
   | `Help me` → `Помоги меня` | no valency in OpenRussian | `verb-government.txt` |
   | `know that X` → `знают этой X` | frame digit 0 (T3 rule 78) | `verb-frames.txt` |
   | `закрына`, `опреобранные` | native participle tables need a paradigm | `generation.lua` derives from forms |
   | wrong sense of a content word | OpenRussian ranks it | `native-readings.txt` (copy LTGOLD's record) |
   | `made`/`opened`/`struck` stays a participle | no `N`/`R` subject in front of `E` | not an `-ed` defect. `R<dD?#>E` and `[NR]ET` promote `E` to finite `V` (`He opened` → `открыл`, `Russia made a deal` → `рядилась`). If the subject is tagged `V` (`Trump` → `козырь`) the rule never sees it |

5. **Never add name entries.** Capitalized unknown words are transliterated
   by the engine (`lexicon.name_unknown`).
6. **Iterate cheaply.** `sh tools/rebuild_openrussian.sh` and `sh test/run_all.sh`
   are fast; `lua tools/dict_compare.lua` takes about two minutes, so run it
   once per batch in the background (`... > /tmp/dc.txt &`) and read it when it
   finishes. Commit after each fix class, not at the end.
7. **Before pushing a rebuilt branch**, check `git merge-base` with `main`; a
   branch cut before a data move must be restarted from `main`.
