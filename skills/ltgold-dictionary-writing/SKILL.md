---
name: ltgold-dictionary-writing
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

The default English dictionary is `reference/openrussian/BASE.DIC`. Keep reviewed
UTF-8 entries in `reference/openrussian/phrases.txt` and structural word readings
in `reference/openrussian/function-words.txt`; import them with
`tools/ltech_dict.py`. Historical `LTGOLD/BASE.DIC` is a separate reference,
not an automatically merged source. English phrase rules belong in `.DIC`;
`.RUS` and `.MORPH` supply Russian morphology.

## Quick path: add a phrase to phrases.txt

Each step takes seconds; do all of them.

1. **Look up evidence.** `python3 tools/ltech_dict.py find LTGOLD/BASE.DIC 'good night'`
   shows the original's coding; the same command on `reference/openrussian/BASE.DIC`
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
3. **Edit** `reference/openrussian/phrases.txt`. If step 1 showed a generated
   literal starting with the same words, add its key to
   `reference/openrussian/removed-headwords.txt`, or it will hide a subrule.
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

## Quick fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| Word printed uninflected or frozen | `D`/fixed text where words should agree | Tagged lemmas in a `W` composite |
| First letter с/м/ж missing | Russian text in a `#` component | `D` or `WD` |
| Idiom swallows a longer sentence (“You are welcome to stay”) | Literal key | Boundary subrule ending `[*]` or `[,*]` |
| Subrule never fires | Literal with the same first words wins lexically | Add that key to `removed-headwords.txt` |
| Subrule fails only before a comma after a sentence-initial preposition | Comma retagged `j` | `[j,*]` |
| Subrule on a sentence-final one-word head never fires | Native: no subrules attach at the end | Choose another shape; the original behaves the same |
| Wrong в/на or из/с/от | Noun flags in `.RUS` | Add the noun to `na-nouns.txt`; animacy comes from OpenRussian |
| Capitalized lemma does not decline | Lowercase lemma missing from `.RUS` | `python3 tools/ltech_dict.py find reference/openrussian/BASE.RUS <lemma>` |
| Expected ё, got е | OpenRussian normalizes ё | Expect е |
| A `function-words.txt` row deleted other meanings | `--replace` removes every record for the key | Pack alternatives into the one record, or leave the word out |
| Test would need broken Russian to pass | Unrelated defect around the phrase | Check the owned span with `~>`; never bless the defect |

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
