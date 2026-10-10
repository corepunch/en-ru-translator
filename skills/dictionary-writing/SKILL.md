---
name: dictionary-writing
description: "Write and review LTGOLD/SARMA English–Russian dictionary entries for en-ru-translator: phrases in the BASE2 add-on, corrections to LTGOLD's words, grammatical phrase subrules, W readings and function-word tags. Use when adding phrases (how are you, what's up, greetings) or enriching or correcting its .DIC/.RUS dictionaries."
---

# LTGOLD dictionary writing

Work from the en-ru-translator repository root. The normal checkout is
`/Users/igor/Developer/en-ru-translator`; use the current checkout when working
elsewhere. Read its `AGENTS.md`, [how LTGOLD works](../../docs/ltgold.md), the
[authoring reference](references/authoring.md) and the
[code and value reference](references/codes.md) before choosing tags or phrase
syntax. The code reference covers every documented dictionary class, numeric
fields, pattern operators, subrule controls and verified `.RUS` bits. Consult it
rather than guessing what a letter or digit means.

## Where entries go

LTGOLD's own dictionaries are the base. The engine loads the dictionary
directory like Quake 2 loads paks: `BASE.DIC`/`BASE.RUS`, then `BASE2.*`,
`BASE3.*` … until a number is missing, each going ahead of the ones before.
Deleting an add-on file takes it out; `--base-only` leaves all add-ons out.

| File | What it is |
| --- | --- |
| `LTGOLD/BASE.DIC`, `LTGOLD/BASE.RUS` | LTGOLD's dictionaries, unchanged |
| `dictionary/phrases.txt` | **our phrase add-on**: phrases LTGOLD lacks or gets wrong, `key*code` lines |
| `dictionary/phrases-rus.txt` | Russian records the add-on needs (`lemma*C hex…`) |
| `dictionary/BASE2.DIC`, `BASE2.RUS` | built from the two files above: only their records |
| `dictionary/changes.txt`, `changes-rus.txt` | corrections to LTGOLD's own words, built into `dictionary/BASE.*` (`-headword` removes, `headword*code` replaces) |
| `dictionary/BASE.DIC`, `BASE.RUS` | built: LTGOLD's files with `changes*.txt` applied |
| `dictionary/pending*.txt`, `test/pending/` | parked: the `ты` section, `твой`/`льгота` records and two table fixes |
| `LTGOLD/BUSINESS.DIC`, `COMPUTER.DIC` | topic dictionaries, `--topic=BUSINESS` |

A new phrase goes in `phrases.txt`. A wrong reading of an LTGOLD word goes in
`changes.txt`. `sh tools/build_dictionary.sh` builds everything; never
hand-edit a built file (`--verify` catches it). Add only what LTGOLD lacks or
gets wrong: if `lua init.lua --base-only 'Good morning.'` already says
`Доброе утро.`, the phrase does not belong in the add-on. An entry that makes a
translation worse is removed, not tuned around.

## Default, --original and --base-only

The default is the improved translator: LTGOLD plus the add-ons, and Lua fixes
of LTPRO defects (prefixed-word casing, gap phrases, list controls, stacked
contractions, н after a preposition: `у него`, `от него`). `--original` is
LTPRO exactly: no add-ons and LTPRO's own behaviour; `test/original_test.lua`
requires it to match every capture. `--base-only` is the default engine
without add-ons; use it to see what LTGOLD alone does.

## Quick path: add a phrase

1. **What does LTGOLD do now?** `lua init.lua --base-only 'Thank you very much.'`.
   If that is already right, stop. Look up LTGOLD's coding:
   `python3 tools/ltech_dict.py find LTGOLD/BASE.DIC 'thank you'` (also lists
   subrules on the head, `run [TAONIH"'#?]*$Vвыполнять`).
2. **Pick the shape** (tags: `N` noun, `n` plural noun, `A` adjective, `V` verb,
   `D` adverb/interjection, `K` particle, `R` pronoun, `C` conjunction,
   `P`+case+preposition; cases `И Р Д В Т П`):

   | Expression | Shape | Example |
   | --- | --- | --- |
   | Fixed formula, nothing agrees | `D` text | `thank you very much*Dбольшое спасибо` |
   | Words that agree or decline with the sentence | `W` + tagged lemmas | `walk home*WVидтиDдомой` |
   | Only standalone or clause-final | boundary subrule | ``you `are``welcome`[*]*$Dпожалуйста\  \`` |
   | Variable pronoun or auxiliary | typed subrule | `how XR[*]*$…` (below) |

   Use `D` for every fixed greeting or formula. A `W` composite at the start of
   a sentence is printed with every component capitalized (`Большой Спасибо`,
   `Как Жаль`), and a `W` noun without a `.RUS` record inflects as a masculine
   (`Добрый Утро`). A multiword lemma keeps its space inside one tag
   (`Vиметь дело` → `имеет дело`), but a one-component verb loses the
   imperative (`stay home*Vоставаться дома` → `Оставаться дома`).
3. **Edit** `dictionary/phrases.txt`, then `sh tools/build_dictionary.sh`.
4. **Check and record** with `lua init.lua`, then add to `test/translations.txt`
   a `phrase:<exact key> | Sentence. => …` line copied from the actual output,
   a variant (capitals, contraction, another case form) and a `!>` line for a
   nearby sentence the phrase must not consume. `common_phrases_test.lua` fails
   for an entry without a `phrase:` line.
5. **Original program**, for any new syntax:
   `python3 tools/ltpro_try_entries.py --entry '<row>' 'Sentence.'` prints what
   LTPRO makes of the entry. Its "lua" column ignores the entry; compare with
   `lua init.lua --dic <scratch BASE.DIC>` built by
   `python3 tools/ltech_dict.py import <copy> --entries <file> --replace --in-place`.
6. `sh test/run_all.sh` and `sh tools/build_dictionary.sh --verify`.

## Worked example: how are you, what's up

```text
how XR[*]*$Dкак\`PР01у``MMWMJ0nдело`\
what <X>`up`[*]*$DDWDкакnдело\ $ \
how `is``it`[*]*$Dкак дела\  \
how `is``it``going`[*]*$Dкак дела\   \
```

- `how XR[*]` is one grammatical rule for every pronoun: `X` is the auxiliary
  (am/are/is), `R` the pronoun, `[*]` the sentence end, so `How are you
  feeling?` is untouched. The head becomes `как`; the auxiliary becomes `у` +
  genitive; the pronoun keeps its person, number and gender and generates
  `Вас`, `него`, `нее`, `них`, `меня`; `nдело` gives `дела`. The fragment table
  is in [codes.md](references/codes.md#greeting-entries).
  Output: `Как у Вас дела?` (LTGOLD's `you` is `Вы`), `Как у него дела?`.
- `How's he?` reaches the same rule: by default `'s` after how, where, when
  and why is `is`.
- `it` is reread as `это` by a later rule, so `How is it?` has its own
  boundary rules giving fixed `Как дела`. The number of spaces in the tail
  action is the number of context words deleted.
- `what <X>`up`[*]` works with a question mark (`What's up?`, `What is up?`).
  With `.`, `!` or no mark LTGOLD's own `what [RSXU]` subrule wins and the
  output stays `Что - по.`, in LTPRO too: a known limitation, not a reason for
  a literal `what is up` key, which would also swallow `What is up there?`.
- Tests: `greeting` lines in `test/translations.txt`; `greetings_test.lua`
  checks that the native rule fired and the pronoun fields survived.

## Native behaviour to plan for

- **Gaps.** `~` in a key holds at most one word, and none when the word there
  already equals the next key word. A key ending in `~` never matches. After a
  key matches, LTPRO tries every longer key extending it, and each attempt
  forgets the gap word, so `take ~ photographs` loses its gap word when
  `take ~ photographs of` exists (`--original` reproduces that; the default
  keeps it). A reading led by a class letter instead of `W` prints `~` as
  text. The gap word is cased as part of the phrase (`за счет Покупателей`).
- **Precedence.** A literal multiword key takes its words before any subrule
  runs; of a word's subrules T4 applies the one whose match ends soonest, so a
  new subrule loses to an LTGOLD one-word pattern on the same head
  (`what [RSXU]`). A longer LTGOLD key beats ours (`thank you very much for`).
- **Pronoun forms.** `M` codes carry number, person and gender only; there is
  no flag for the н- of `него`. The default engine adds it after a printing
  preposition (not after `согласно`, `благодаря` …); LTPRO only after с, о …
- **Russian records.** A Russian word LTGOLD has no `.RUS` record for inflects
  as a masculine row-0 noun; add one to `phrases-rus.txt` (or `changes-rus.txt`
  for LTGOLD's own words) when that is wrong.
- **Address.** LTGOLD says `Вы`; the `ты` section is parked in
  `dictionary/pending.txt`.

## Changing a word

To change LTGOLD's reading of a word, put the whole replacement record in
`changes.txt`: every segment, `{gloss}` note and `;` alternative LTGOLD has
(`power*NN.мощность{ability;electricity};право{the right}`, not
`power*Nмощность`). `-word` removes the word entirely. State the reason in the
commit and test the word in context.

## The engine is LTGOLD

The Lua engine reproduces the original program on LTGOLD's dictionaries: with
`--original`, all 834 captured translations and the whole `DEMO.TXT`
(`lua init.lua --document LTGOLD/DEMO.TXT`) byte for byte; by default it
differs only by the reviewed fixes listed in
`test/ltpro/review-2026-10-08/reviewed-differences.json`. Never change the
engine to make one dictionary entry work. A general fix of an LTPRO defect
goes in by default with LTPRO's behaviour kept under `--original`, a reviewed
difference recorded, and `original_test.lua` still passing. Run the parity
checks in [docs/ltgold.md](../../docs/ltgold.md#verifying) before and after.

## Fast path for a sentence that translates badly

1. **Trace before editing.** `lua init.lua --trace 'sentence'` writes the
   translation to stdout and a token/rule trace to stderr: live tags,
   readings, every T1–T4 rule that matched (`sub` marks a phrase subrule).
2. **Compare** `--base-only` (LTGOLD alone) and `--original` (LTPRO), and the
   original program for the same sentences in one `tools/ltpro_capture.py`
   run (see `AGENTS.md`). If the original says the same thing, the cause is in
   LTGOLD's data, not the engine.
3. **Look the word up** in `LTGOLD/BASE.DIC` and `LTGOLD/BASE.RUS`. Search raw
   bytes (`d.find('свыше'.encode('cp866'))` across `LTGOLD/*`) to find which
   record produces an unexplained word.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Words of a phrase capitalized (`Большой Спасибо`) | sentence-initial `W` composite | `D` text |
| Noun inflects as masculine (`Добрый Утро`) | no `.RUS` record | add one, or `D` text |
| Subrule never fires | an LTGOLD literal or a shorter LTGOLD subrule wins | check with `--trace`; `-` the conflicting record only if ours is better, and test both |
| Gap word missing | a longer key extends the matched one, or the reading is not `W`-led | rewrite the key or the reading |
| `у его`, `от его` | LTPRO's н- rule (`--original`) | default output has `у него` |
| First letter с/м/ж missing | Russian text in a `#` component | `D` or `WD` |
| Idiom swallows a longer sentence | literal key | boundary subrule ending `[*]` or `[,*]` |
| Subrule fails before a comma after a sentence-initial preposition | comma retagged `j` or `;` | `[j,*]`, `[j;,*]` |
| Single-word key prints a stray case letter (`Рдо`) | `W` reading without an input class | `goodbye*Dдо свидания` |
| Third `\`-section of a subrule does nothing | only the selector's first character is read | put the edit in the tail action |
| Unsure what a code does natively | unverified syntax | add a probe to `test/ltpro/dictionary-syntax/probes.json` and capture it |

## Principles

Honor the requested scope; for a batch, review every entry, and keep only
entries that improve on LTGOLD. Use verified dictionary syntax, grammatical
tags, reusable patterns and normal agreement. Do not hardcode surface forms,
enumerate grammatical variants (one `how XR[*]`, not one rule per pronoun), or
use `#` literals or uninflected tails to hide missing support. Recover
LTGOLD's mechanism before changing anything; an apparent missing feature is an
investigation task, not permission to invent an extension.

Test every entry you add or change, with agreement/case variants and a nearby
context that must not be consumed. Every expected line in
`test/translations.txt` is copied from actual `lua init.lua` output. The
original executable is the oracle: use explicit temporary capture paths,
report original and Lua outputs separately, and never alter a capture. Never
turn a known defect into an accepted expectation without saying so.
