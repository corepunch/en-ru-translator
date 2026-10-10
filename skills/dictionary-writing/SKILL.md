---
name: dictionary-writing
description: "Write and review LTGOLD/SARMA English–Russian dictionary entries for en-ru-translator, including grammatical phrase patterns, W readings, and function-word tags. Use when enriching or correcting its .DIC/.RUS dictionaries."
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

## Sources

LTGOLD's own dictionaries are the base. Our work is a diff on top of them:

| File | What it is |
| --- | --- |
| `LTGOLD/BASE.DIC`, `LTGOLD/BASE.RUS` | LTGOLD's dictionaries, unchanged |
| `dictionary/changes.txt` | our English changes: `-headword` removes LTGOLD's records, `headword*code` adds or replaces |
| `dictionary/changes-rus.txt` | our Russian changes: `-lemma`, or `lemma*C hex…` (`утро*N 80 80 80`) |
| `dictionary/pending.txt`, `test/pending-translations.txt` | phrases from the OpenRussian period waiting to be checked and moved into `changes.txt` with their tests |
| `dictionary/paradigms.txt` | LTPRO's inflection tables as text with two fixes (Latin `e`, бежать's missing жим) |
| `dictionary/BASE.DIC`, `dictionary/BASE.RUS` | built by `sh tools/build_dictionary.sh`; the default dictionaries |
| `LTGOLD/BUSINESS.DIC`, `LTGOLD/COMPUTER.DIC` | theme dictionaries, `--dic-overlay` |

There are no other sources. Never hand-edit a built file; `--verify` catches it.
Add only what LTGOLD lacks or gets wrong, and nothing LTGOLD already has.

## Quick path: add a phrase

1. **Look up evidence.** `python3 tools/ltech_dict.py find LTGOLD/BASE.DIC 'good night'`
   shows LTGOLD's coding, including subrules on the head word
   (`run [TAONIH"'#?]*$Vвыполнять`). Use LTGOLD's record when it exists.
2. **Pick the shape** (tags: `N` noun, `n` plural noun, `A` adjective, `V` verb,
   `D` adverb/interjection, `K` particle, `R` pronoun, `C` conjunction,
   `P`+case+preposition; cases `И Р Д В Т П`):

   | Expression | Shape | Example |
   | --- | --- | --- |
   | Fixed Russian text, nothing agrees | `D` | `of course*Dконечно` |
   | Russian words that agree or decline | `W` + tagged lemmas | `happy birthday*WPТсNденьPРNрождение` |
   | Valid only standalone or clause-final | boundary subrule | ``you `are``welcome`[*]*$Dпожалуйста\  \`` |
   | Variable pronoun/auxiliary | typed subrule | `how XR[*]*$…` |

   Native behaviour to plan for:
   - A `W` composite at the start of a sentence is printed with every
     component capitalized (`Рыбная Мука`, `Длинная Волна`), as LTPRO does.
     A fixed greeting that agrees with nothing is `D` text instead.
   - A literal multiword key takes its words before any subrule runs, and of a
     word's subrules T4 applies the one whose match ends soonest. A new subrule
     loses to an LTGOLD one-word pattern on the same head (`what [RSXU]`).
   - LTGOLD's `you` is the polite `Вы`.
   - A Russian word LTGOLD has no `.RUS` record for inflects as a masculine
     row-0 noun; give it a record in `changes-rus.txt` when that is wrong.

   A multiword Russian lemma keeps its space inside one tag
   (`Vиметь дело` prints `имеет дело`; `VиметьNдело` makes `дело` agree).
   A phrasal verb or an idiom is its own key, and an article in an idiom is a
   placeholder (`make <TAO>`deal`*$заключать\$`Nсделка`\`).
3. **Edit** `dictionary/changes.txt`, then `sh tools/build_dictionary.sh`.
4. **Check and record:** `lua init.lua 'Good night.'`, then add lines to
   `test/translations.txt`: `phrase:<exact key> | Good night. => …`, one
   variant (capitals, contraction or another case form), and a `!>` line for a
   nearby sentence the phrase must not consume.
5. **Original program:** `python3 tools/ltpro_try_entries.py --entry '<row>'
   'Good night.' '<context>'` prints the original next to Lua with the entry
   installed. New syntax must work there.
6. `sh test/run_all.sh` and `sh tools/build_dictionary.sh --verify`.

## Changing a word

To change LTGOLD's reading of a word, put the whole replacement record in
`changes.txt`: every segment, `{gloss}` note and `;` alternative LTGOLD has
(`power*NN.мощность{ability;electricity};право{the right}`, not
`power*Nмощность`). `-word` removes the word entirely. State the reason in the
commit and test the word in context.

## The engine is LTGOLD

The Lua engine reproduces the original program on LTGOLD's dictionaries:
77/77 on the main corpus, 355/386 on `review-2026-10-08` (the rest are reviewed
differences). Never change the engine to make a dictionary entry work, and never
add a Lua-only behaviour by default; an option such as `--names` (transliterate
unknown capitalized words) is the only way to add one. Before and after an
engine change run the parity probes in [docs/ltgold.md](../../docs/ltgold.md#verifying).

## Fast path for a sentence that translates badly

1. **Trace before editing.** `lua init.lua --trace 'sentence'` writes the
   translation to stdout and a token/rule trace to stderr: live tags,
   readings, every T1–T4 rule that matched (`sub` marks a phrase subrule).
2. **Compare with the original** for the same sentences in one
   `tools/ltpro_capture.py` run (see `AGENTS.md`). If the original says the
   same thing, the cause is in LTGOLD's data, not the engine.
3. **Look the word up** in `LTGOLD/BASE.DIC` and `LTGOLD/BASE.RUS`. Search raw
   bytes (`d.find('свыше'.encode('cp866'))` across `LTGOLD/*`) to find which
   record produces an unexplained word.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Words of a phrase capitalized (`Добрый День`) | native casing of a sentence-initial `W` composite | `D` for fixed text |
| Subrule never fires | an LTGOLD literal or a shorter LTGOLD subrule wins | `-` the conflicting record if ours is better, and test both |
| Noun inflects as masculine (`Добрый утро`) | no `.RUS` record | add one to `changes-rus.txt` |
| First letter с/м/ж missing | Russian text in a `#` component | `D` or `WD` |
| Idiom swallows a longer sentence | literal key | boundary subrule ending `[*]` or `[,*]` |
| Subrule fails before a comma after a sentence-initial preposition | comma retagged `j` or `;` | `[j,*]`, `[j;,*]` |
| Single-word key prints a stray case letter (`Рдо`) | `W` reading without an input class | `goodbye*DDWPРдоNсвидание` |
| Third `\`-section of a subrule does nothing | only the selector's first character is read | put the edit in the tail action |
| Unsure what a code does natively | unverified syntax | add a probe to `test/ltpro/dictionary-syntax/probes.json` and capture it |

## Principles

Honor the requested scope; for a batch, review every entry. Use verified
dictionary syntax, grammatical tags, reusable patterns and normal agreement.
Do not hardcode surface forms, enumerate grammatical variants, or use `#`
literals or uninflected tails to hide missing support. Recover LTGOLD's
mechanism before changing anything; an apparent missing feature is an
investigation task, not permission to invent an extension.

Test every entry you add or change, with agreement/case variants and a nearby
context that must not be consumed. Every expected line in
`test/translations.txt` is copied from actual `lua init.lua` output. The
original executable is the oracle: use explicit temporary capture paths,
report original and Lua outputs separately, and never alter a capture. Never
turn a known defect into an accepted expectation without saying so.
