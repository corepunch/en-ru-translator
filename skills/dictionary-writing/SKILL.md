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
   | One invariant equivalent | `D` text | `thank you*Dспасибо` |
   | Words that agree or decline with the sentence | `W` + tagged lemmas | `walk home*WVидтиDдомой` |
   | Only standalone or clause-final | boundary subrule | ``you `are``welcome`[*]*$Dпожалуйста\  \`` |
   | Variable pronoun or auxiliary | typed subrule | `how XR[*]*$…` (below) |

   For a new multiword equivalent whose Russian words must agree or decline,
   use `W` with tagged lemmas, case governors and explicit plural tags, including
   `best wishes*WAнаилучшийnпожелание`. Do not put an inflected surface phrase
   after `D`, or try to append tags to a `D` reading. A single invariant word
   can use `D` (`thank you*Dспасибо`); the seven existing multiword fixed
   utterances in `tools/check_phrase_formulas.py` are reviewed exceptions, not
   templates for new entries. This is an **add-on authoring policy**, not a
   restriction of LTGOLD's format: `BASE.DIC` also has literal phrase keys and
   uninflected text inside `W` readings. The build rejects new multiword `D`
   readings and untagged `W` tails in this add-on. The default add-on uses
   sentence-wide casing for `W` readings. A `W` noun without a
   `.RUS` record may still inflect as a masculine (`Добрый Утро`). A
   multiword lemma keeps its space inside one tag
   (`Vиметь дело` → `имеет дело`), but a one-component verb loses the
   imperative (`stay home*Vоставаться дома` → `Оставаться дома`).
3. **Edit** `dictionary/phrases.txt`, then `sh tools/build_dictionary.sh`.
   The build runs `tools/check_phrase_formulas.py`, which rejects frozen
   multiword `D` readings and untagged spaces in `W` readings.
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

## Use patterns when they add useful coverage or context

Before adding a key, look up each English word's active tag in `BASE.DIC`,
search nearby literal variants and comparable native subrules, and read the
matching operators in [codes.md](references/codes.md#context-patterns-and-actions).
Do not force phrases into templates. Use a literal key for a fixed expression;
use a pattern when one entry usefully covers a real family of expressions or
needs a context check. Merely allowing an unlikely article variant is not a
reason to introduce a pattern. For a variable slot, match the relevant classes
and retain number, person, gender, case and tense where the meaning permits.
Use a lexical backtick for a word whose identity matters within a context rule.
On the Russian side, use a `W` reading with tagged lemmas for words that must
agree or decline. A whole literal key is valid native syntax, but the original
dictionary's repetition and uninflected tails are not an authoring target.

These are **independent examples from BASE.DIC**, decoded from its CP866
records. They show that the original authors already used typed slots, even
though other entries were written out separately:

| Historical entry | What to learn from it |
| --- | --- |
| ``make <TAO>`claim`*$подавать\$`Nиск` `` | Vary article, adjective or determiner before the exact `claim`; replace the noun reading in the context action. |
| ``make <TAO>`decision`*$Vпринимать`` | One entry covers useful variation in the modifiers before `decision`. |
| ``write <TAO>`letter`*$Vписать\$`письмо` `` | A typed span can coexist with a fixed idiom anchor and a context rewrite. |
| ``agreement X`on`*$договор\ `PПо` `` | `X` matches an auxiliary form while `` `on` `` still requires that English word. Check tense variants before reusing this shape. |
| `afford [MR]*$Vпозволять\M\6` | `[MR]` accepts one pronoun of either class. Choose classes from actual tags, not the English spelling alone. |
| ``where R<$>`go`*$куда`` | `R` consumes a personal pronoun; the lexical anchor still requires `go`. |
| ``thank `you`[*]*$Dблагодарю вас\ \`` | Here `you` is deliberately literal and `[*]` requires the boundary; not every English word is a variable slot. |
| ``relieve <TAONw>`of`*$освобождать\`PРот` `` | The intervening span allows exactly the listed classes. It excludes `M`, so it cannot be copied as a rule for `relieve him of …`. |

BASE.DIC also repeats these complete keys with the **same** Russian reading:

```text
come up with a solution*Weприходить к решению
come up with the solution*Weприходить к решению
view a file*WVпросматриватьNфайл
view the file*WVпросматриватьNфайл
aspect of a problem*WNсторона вопроса
aspect of the problem*WNсторона вопроса
```

These are good candidates for an article-class slot when writing a new rule.
The `view` pair also shows a tagged `W` noun; the `come up with` pair has an
uninflected `W` tail that a new rule need not copy. The following BASE.DIC
family is another candidate, this time for a pronoun slot:

```text
teach her a lesson*WVпроучить ее
teach him a lesson*WVпроучить его
teach them a lesson*WVпроучить их
```

Its uninflected Russian pronouns show why the output action must preserve the
correct case. A Lua trace without those literals gives
`her`, `him` and `them` tag `M` there; `teach` then assigns dative. Test a
candidate `M` rule for accusative in both engines before using it.

Generalization is useful, but a placeholder is not automatically equivalent
to every literal it can match. In BASE.DIC, `at a time*Dза один раз` and
`at the time*Jкогда` differ in meaning; `set a limit*eограничивать` and
`set the limit*WVустанавливать предел` also differ. Keep that distinction.
Test positive variants and nearby negative contexts, and check whether an
existing longer literal wins before the subrule runs. If a typed rule cannot
preserve meaning or grammatical fields, keep the necessary literal key and
record the reason.

| English slot | Native code | Scope |
| --- | --- | --- |
| `a`, `the` | `T` (`a*T`, `the*T` in `BASE.DIC`) | `[T]` consumes exactly one article. `<T>` permits a span of zero or more `T` words before a lexical anchor. |
| article, adjective, determiner before a noun | `<TAO>` | `T` is article, `A` adjective, `O` determiner; the whole span may be empty. This is the spelling in BASE.DIC's ``make <TAO>`claim`*$…`` and ``make <TAO>`agreement`*$…``. It is broader than an article slot. |
| `am`, `are`, `is` | `X` | Match the auxiliary class when its form can vary without changing the idiom's meaning; `X` also includes past forms, so test those. |
| personal or object pronoun | `R`, `M`, `[MR]` | Keep person, number and gender; choose from the tags at the matching stage. `how XR[*]` and historical `afford [MR]` show two different slots. |
| exact lexical anchor or sentence end | backticks, `[*]` | Backticks require the named word; `[*]` requires the boundary. They prevent a short idiom from swallowing a longer clause. |

Use the narrowest pattern that covers the meaningful variation. `<TAO>` is not
a magic spelling for `a/the`: the article alone is `T`. A pattern such as
``have <TAO>`day`[*]`` paired with fixed `хороший` would also turn “Have a bad
day” into “Хорошего дня”; retain a variable adjective when its meaning matters.
Likewise,
`X` includes past forms: ``you `are``welcome`[*]`` deliberately excludes “You
were welcome”. The original executable makes a proposed `you X` rule produce
`Пожалуйста` for that past-tense sentence. These are reasons to test a
placeholder's scope, not reasons to avoid placeholders in general.

| Avoid for a productive family | Prefer after verification | Reason |
| --- | --- | --- |
| `best wishes*Dнаилучшие пожелания` or `best wishes*Dнаилучшиеnпожелание` | `best wishes*WAнаилучшийnпожелание` | `W` distributes tagged lemmas; `with` can then govern instrumental: `с наилучшими пожеланиями`. |
| Separate `make a deal`, `make the deal`, `make his deal` keys when one rule handles all three | ``make <TAO>`deal`*$заключать\$`Nсделка`\`` | This T4 rule handles the modifier slot; it is modeled on BASE.DIC's `make <TAO>` subrules. |
| An unrestricted greeting key when a longer sentence has another meaning | ``you `are``welcome`[*]*$Dпожалуйста\  \`` | The boundary is useful even with no variable slot: it excludes “You are welcome here.” |
| Separate `how are you`, `how is he` and `how are they` keys | `how XR[*]*$Dкак\`PР01у``MMWMJ0nдело`\` | `X` and `R` cover the grammatical family and retain the pronoun fields. |
| `what is up*Dкак дела` and `what's up*Dкак дела` | ``what <X>`up`[*]*$DDWDкакnдело\ $ \`` | The auxiliary may be present or removed by question cleanup; the boundary keeps “What is up there?” outside the idiom. |

`~` in a literal key is only an arbitrary one-word gap, not a typed article or
pronoun. `[]` consumes one class choice; `<>` searches a permitted span up to
its following anchor. When considering a pattern, start from a verified
BASE.DIC mechanism, preserve its action spacing, then test variants and
negative contexts with both Lua and LTPRO. If the generalized rule cannot
produce the right grammatical result, retain the literal keys and record why.

### Literal keys, context rules and deletion actions

These are different native record forms; do not mix their separators:

```text
you are welcome*Dпожалуйста
you `are``welcome`[*]*$Dпожалуйста\  \
on ~ behalf*WPРот~Nимя
```

The first is an unrestricted whole-phrase equivalent. The second translates
the same words only at the specified boundary: `you` is the head, the pattern
matches `are`, `welcome` and the boundary, and `Dпожалуйста` rewrites the head.
The two spaces after the first backslash delete `are` and `welcome`; they do
not print spaces. The final backslash begins the optional selector section,
which is empty here. Literal phrase entries consume their words together and
need no such deletion action. BASE.DIC uses the same mechanism in
``in `full`[*]*$Dполностью\ \`` and ``thank `you`[*]*$Dблагодарю вас\ \``.

The third example is an actual BASE.DIC gap phrase. The input `~` captures a
word; the `~` inside the `W` reading reinserts that word with its own reading
and grammar. It is not an empty adjective lemma: do not write `A~` or invent
`A{capture}`. This mechanism can retain an adjective or a determiner, but does
not restrict the input to that class or require sentence end. Check the whole
phrase's case and its behavior in longer sentences before choosing a gap.

The add-on's wishes use an adjective slot and an end boundary together:

```text
have [T]A`day`[*]*$DDWPР\ \
have [T]A`trip`[*]*$DDWPР\ @`Nпуть`\
```

Here `A` retains the actual adjective, so one entry handles `nice`, `good`,
`wonderful`, `bad`, and other adjective readings. `[T]` covers both `a` and
`an`, as in `a nice day` and `an excellent day`. `PР` supplies silent genitive
government; the article is deleted. The day rule leaves the remaining context
untouched; the trip rule uses `@` to keep the adjective and rewrites `trip` as
`Nпуть`. The adjective comes from its own dictionary entry: `good` gives
`хорошего пути`, not the idiomatic substitution `счастливого пути`. Use a fixed
equivalent when that substitution is the intended meaning. This is useful
generalization; merely matching `the nice day` as well as `a nice day` would
not itself be a reason to use a template.

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
| Words of a phrase capitalized (`Большой Спасибо`) | missing phrase-wide casing on a `W` reading | check add-on loading and casing; do not freeze the reading as `D` |
| Noun inflects as masculine (`Добрый Утро`) | no `.RUS` record | add the verified Russian record; keep tagged lemmas |
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
tags, reusable patterns and normal agreement. Avoid hardcoded surface forms
and enumerated grammatical variants when one verified rule can retain the
varying words (one `how XR[*]`, not one rule per pronoun). Do not use `#`
literals or uninflected tails to hide missing support. Recover
LTGOLD's mechanism before changing anything; an apparent missing feature is an
investigation task, not permission to invent an extension.

Test every entry you add or change, with agreement/case variants and a nearby
context that must not be consumed. Every expected line in
`test/translations.txt` is copied from actual `lua init.lua` output. The
original executable is the oracle: use explicit temporary capture paths,
report original and Lua outputs separately, and never alter a capture. Never
turn a known defect into an accepted expectation without saying so.
