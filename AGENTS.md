# AGENTS.md — Guide for AI Coding Assistants

## Project Overview

English-to-Russian translator reverse-engineered from **LinguaTech LTGOLD** (1990-1993 DOS
translation software). The original translation engine was extracted from the DOS EXE and
recreated in Lua.

## Running

```sh
lua init.lua
```

Requires **Lua 5.3+** (uses bitwise operators). Test sentences are hardcoded in
`init.lua:81-97`. Edit those lines to translate different text.

## File Reference

| File | Role |
|------|------|
| `init.lua` | Entry point. Loads dictionaries, tokenizes input, runs parser + compiler |
| `rules.lua` | ~644 pattern-matching rules extracted from LTGOLD.EXE (669 lines, 7 rule sets) |
| `parser.lua` | Applies rules to tokenized English stream, transforms grammatical tags |
| `compiler.lua` | Generates Russian output using morphological paradigms for proper inflection |
| `paradigms.lua` | Russian noun/adjective/verb declension and conjugation tables |
| `load.lua` | Parses LTGOLD `*.DIC`/`*.RUS` dictionary format (CP866 encoded) |
| `utils.lua` | CP866↔UTF8 conversion, tokenization, string helpers |
| `dict.lua` | Dictionary management tool (find/add/list entries) |
| `rus_tool.lua` | RUS paradigm data tool (find/add/list/list paradigms for .RUS files) |
| `lisp.lua` | Unused list utility |
| `data/` | Dictionary and config files (BASE.DIC, BASE.RUS, BUSINESS.DIC, COMPUTER.DIC, etc.) |
| `test/` | Test data (DEMO.TXT, DEMO_REFERENCE.TXT, etc.) |
| `LTGOLD/` | Original DOS EXE, dictionaries, and Python extraction tools (git-ignored) |

## Pattern Syntax (rules.lua)

Rules use a pattern-matching language extracted from the original LTGOLD binary:

| Syntax | Meaning |
|--------|---------|
| `[...]` | Character class — match one of the listed grammatical tags |
| `<...>` | Any-match — match zero or more of listed tags |
| `*` | Sentence boundary — start or end of token stream |
| `~` | Negation — invert the next token's match |
| `` `word` `` | Literal English word |

**Example:** `*Z[?#]*` matches: **start-of-sentence**, then a verb (`Z`), then a number or unknown (`?#`), then **end-of-sentence**. The pattern only fires when it spans the full sentence.

## Grammatical Codes

Single-letter tags attached to words after dictionary lookup.
Source: dic.txt (SARMA 2.0 documentation). Lowercase = derived/already-resolved form.

| Code | Meaning |
|------|---------|
| `Z` | Ambiguity V-N-A (verb/noun/adj unresolved) |
| `z` | Ambiguity v-n (3sg-s form: verb or noun) |
| `V` | Main (content) verb (resolved from Z) |
| `v` | Verb -s/-es form (3rd person singular present) |
| `N` | Noun (singular) |
| `n` | Noun (plural form) |
| `A` | Adjective, ordinal numeral |
| `a` | Adjective-adverb ("more", "less") |
| `S` | Demonstrative pronoun (adjectival: "this book") |
| `O` | Demonstrative pronoun (standalone: "this", "that") |
| `D` | Adverb, parenthetical word/phrase |
| `d` | Adverb/adjective ambiguity |
| `E` | -ed forms and irregular past (past participle / simple past) |
| `e` | Ambiguous: infinitive / participle-II / past tense |
| `G` | -ing verb forms (gerund / present participle) |
| `F` | Active present participle — analyzer-generated |
| `f` | Determiner-expression (e.g. "a lot of") |
| `P` | Preposition |
| `p` | Preposition (already resolved) |
| `C` | Conjunction (coordinating/disjunctive) |
| `J` | Conjunction (subordinating), phrase-boundary separator |
| `X` | Auxiliary verb 'be' (is/are/was/were) |
| `x` | Impersonal verb combination ("there is", etc.) |
| `Y` | Auxiliary verb 'have' (possession / perfect) |
| `y` | Auxiliary verb 'have' (existential/copular sense) |
| `B` | Infinitive particle 'to' (before perfective verb) |
| `b` | Infinitive particle 'to' (before imperfective verb) |
| `U` | Modal verb ("must", "can", "shall") |
| `u` | Modal verb combination ("had better", "ought to") |
| `K` | Negative particle 'not' |
| `k` | Negative particle 'no' |
| `R` | Personal pronoun ("I", "you", "he") |
| `r` | Compound personal pronoun ("myself", "yourself") |
| `M` | Indirect/object pronoun ("him", "her", "them") |
| `m` | Compound indirect pronoun ("himself", "themselves") |
| `Q` | Question word |
| `L` | Relative word ', который' (which/who — resolved) |
| `l` | Movable relative 'whose' — analyzer-generated |
| `T` | Determiner (article); outputs empty string |
| `t` | Determiner — segment boundary — analyzer-generated |
| `H` | Digits and numeric combinations |
| `I` | Cardinal numeral |
| `W` | Multi-word phrase marker (not in dic.txt; inferred) |
| `w` | Multi-word/compound modifier flag (inferred) |
| `#` | Untranslatable unit (proper noun, designation) |
| `?` | Unknown / unrecognized word (not in dictionary) |
| `\|` | Fictitious separator (clause boundary in token stream) |

Suffix numbers (e.g. `N001`) encode paradigm indices for inflection lookup.

## Conventions

- **Comment all changes** — when modifying code, add comments explaining what the change does and why
- **No other comments** — existing code has no comments; keep new comments sparse but informative
- **Prefer tables over ifs** — LTGOLD encodes grammar in data tables (rule flags, paradigm indices,
  case tables, constituent-type markers). Avoid hardcoding logic in if-chains when the same
  behavior can be expressed as a lookup, ideally from LTGOLD-extracted tables, or custom tables
  as fallback. Each if added to `compiler.lua` or `parser.lua` should have a comment noting
  which LTGOLD table would replace it.
- **No new dependencies** — pure Lua only, no luarocks
- **Match LTGOLD style** — preserve original rule order, pattern format, and code structure
- **CP866 throughout** — legacy encoding internally, UTF-8 only for display via `utils.decode()`
- **Dictionary format:** `word*codes` per line, `*` as separator, CP866 encoded

## Dictionary Format

Lines in `BASE.DIC` / `BASE.RUS`:

```
word*GRAMMATICAL_CODES
```

Multi-word entries use spaces. The dictionary lookup builds a nested table where
`en_ru[word].__lex` holds the lexical form (packed grammatical tags).

## Dictionary Management (dict.lua)

Standalone tool for searching and adding dictionary entries. No external dependencies.

```sh
lua dict.lua find <word>              # exact search across all dictionaries
lua dict.lua find <word> --partial    # substring search
lua dict.lua find <word> --dict FILE  # search specific dictionary
lua dict.lua add <word> <tags> [ru]   # add entry to BASE.DIC
lua dict.lua add <word> <tags> [ru] --dict FILE  # add to specific dict
lua dict.lua add <word> <tags> [ru] --force      # overwrite if exists
lua dict.lua list [FILE] [--limit N]  # list dictionary contents
lua dict.lua paradigms                # grammatical codes reference
lua dict.lua help                     # full documentation
lua dict.lua help <topic>             # help on: overview, format, add, find, list, tips
```

**Entry format:** `word*TAG русский текст` — the grammatical tag and Russian
translation are concatenated directly after `*` with no separator. Multiple
meanings use `;`: `word*Nсоглашение;договор`.

## RUS Paradigm Management (rus_tool.lua)

Standalone tool for searching and adding entries in .RUS paradigm files.
.RUS files provide morphological metadata (gender, paradigm ID, aspect) that
the compiler uses for proper Russian inflection.

```sh
lua rus_tool.lua find <word>              # exact search across all .RUS files
lua rus_tool.lua find <word> --partial    # substring search
lua rus_tool.lua find <word> --dict FILE  # search specific .RUS file
lua rus_tool.lua add <word> <spec>        # add entry to BASE.RUS
lua rus_tool.lua add <word> <spec> --dict FILE  # add to specific .RUS file
lua rus_tool.lua add <word> <spec> --force      # overwrite if exists
lua rus_tool.lua list [FILE] [--limit N]  # list .RUS entries
lua rus_tool.lua paradigms                # paradigm reference tables
lua rus_tool.lua help                     # full documentation
lua rus_tool.lua help <topic>             # help on: overview, find, add, list, paradigms
```

**Add spec shorthand:** `TAG:GENDER:PARADIGM`
- `N:m:0` — noun, male, paradigm 0 (consonant stem: тролль)
- `N:f:14` — noun, female, paradigm 14 (-а ending: свеча)
- `N:n:7` — noun, neutral, paradigm 7 (-о ending: окно)
- `V:i:3` — verb, imperfective, paradigm 3
- `V:p:31` — verb, perfective, paradigm 31
- `A:m:5` — adjective, male, paradigm 5

**Tags:** `N`=noun, `V`=verb, `A`=adjective
**Genders:** `m`=male, `f`=female, `n`=neutral (nouns/adjectives only)
**Paradigm:** 0–127, indexes `paradigms.nouns`/`paradigms.verbs`/`paradigms.adjectives`

## Adding Entries

### Adding new words to BASE.DIC

Use `dict.lua` to add entries that don't exist in the base dictionary:

```sh
lua demo/dict.lua add "boarded" "A" "обшитый досками"
lua demo/dict.lua add "orc" "N" "орк"
lua demo/dict.lua add "west of" "P" "к западу от"  # multi-word phrase
```

**Multi-word phrases** use spaces in the word part and appropriate tags:

```
west of*PРк западу от         # preposition phrase (P) with genitive case (Р)
front door*NNWAпередняяNдверь  # compound noun (W-phrase format)
```

### Adding nouns and verbs to .RUS files

DIC entries map English words to Russian lemmas with grammatical tags. RUS files
provide the morphological metadata (gender, paradigm ID, aspect) that the
compiler uses for proper Russian inflection. Without a matching .RUS entry, the
compiler cannot decline nouns or conjugate verbs — it falls back to the raw
lemma string.

**When you need a .RUS entry:**
- Adding a new noun (tag `N`) — needs gender + declension paradigm
- Adding a new verb (tag `V`) — needs conjugation paradigm + aspect flag
- Adding a new adjective (tag `A`) — needs gender + declension paradigm

**When you do NOT need a .RUS entry:**
- Tags like `D` (adverb), `P` (preposition), `C` (conjunction), `I` (numeral),
  `R` (pronoun), `#` (proper noun) — these are uninflected or handled by
  special-case code in the compiler

#### .RUS file format

Each line: `Russian_word*<binary_code>` (CP866 encoded, `*` = 0x2A separator).

The binary code after `*` is a sequence of bytes:

| Byte | Meaning |
|------|---------|
| 1 | Tag: `0x4E`=N (noun), `0x56`=V (verb), `0x41`=A (adjective) |
| 2 | Flags (bit 1 = perfective aspect for verbs) |
| 3 | Gender (nouns/adjectives): `0`=neutral, `1`=male, `2`=female |
| 4 | Paradigm ID (0-based, matches `paradigms.nouns`/`paradigms.verbs` index) |
| 5+ | (verbs only) Imperfective stem — CP866 Russian infinitive of paired aspect |

**Examples from `data/DUNGEON.RUS`:**

```
тролль = 4E A0 81 81     # tag=N, flags=0xA0, gender=1(male), paradigm=0
свеча  = 4E C0 82 8E     # tag=N, flags=0xC0, gender=2(female), paradigm=14
гроб   = 4E 80 80 87     # tag=N, flags=0x80, gender=0(neutral), paradigm=7
```

#### Noun paradigm lookup

`paradigms.nouns[gender+1][paradigm_id+1]` — each entry is:

```lua
{cut_length, "nom.gen.dat.acc.ins.loc nom.pl gen.pl dat.pl acc.pl ins.pl loc.pl"}
```

- `cut_length`: bytes to strip from the stem before appending suffix
- 11 space-separated suffixes: singular cases 1–6, then plural cases 1–6 (skipping
  repeated nominative)

**Gender ↔ paradigm mapping (common patterns):**

| Gender | Paradigm 0 | Suffix pattern (sing. nom–loc) |
|--------|-----------|-------------------------------|
| Male (1) | consonant stem | `а у = ом е` (e.g. тролль → тролля, троллю, ...) |
| Female (2) | -а ending | `и е у ей е` (e.g. свеча → свечи, свече, ...) |
| Neutral (0) | -о ending | `а у о ом е` (e.g. лезвие → лезвия, ...) |

#### Verb paradigm lookup

`paradigms.verbs[paradigm_id+1]` — each entry is:

```lua
{cut_length, "1sg 2sg 3sg 1pl 2pl 3pl imp past_m past_gerund active_passive past_full past_participle"}
```

- 13 suffixes: present/future (6 persons), imperative, past (base), gerund,
  active participle, passive participle, past participle, passive participle (full)

**Binary code byte 2 — aspect flag:**
- Bit 1 (`byte2 & 2 == 0`): perfective verb
- Bit 1 (`byte2 & 2 ~= 0`): imperfective verb

The compiler reads this to determine aspect for future-tense conjugation
(`q` marker in parser output).

#### How to add a noun

**Step 1: Add DIC entry** (English → Russian lemma + tag):

```sh
lua demo/dict.lua add "orc" "N" "орк"
# → orc*Nорк in BASE.DIC
```

**Step 2: Add RUS entry** (Russian lemma → binary paradigm code):

Use `rus_tool.lua` with the shorthand `N:gender:paradigm`:

```sh
lua rus_tool.lua add "орк" "N:m:0"              # noun, male, paradigm 0
lua rus_tool.lua add "свечка" "N:f:0"           # noun, female, paradigm 0
lua rus_tool.lua add "окошко" "N:n:7"           # noun, neutral, paradigm 7
lua rus_tool.lua add "ларец" "N:m:0" --dict DUNGEON.RUS  # overlay file
```

**Practical approach:** Find an existing noun with the same gender and ending
pattern, then use the same paradigm ID:

```sh
lua rus_tool.lua find свеча          # → paradigm 0, female
lua rus_tool.lua add "свечка" "N:f:0"  # same paradigm
```

#### How to add a verb

**Step 1: Add DIC entry** (English → Russian lemma + tag):

```sh
lua demo/dict.lua add "to fight" "V" "сражаться"
# → to fight*Vсражаться in BASE.DIC
```

**Step 2: Add RUS entry** (Russian lemma → binary paradigm code):

Use `rus_tool.lua` with the shorthand `V:aspect:paradigm`:

```sh
lua rus_tool.lua add "сражаться" "V:i:3"        # imperfective, paradigm 3
lua rus_tool.lua add "написать" "V:p:3"          # perfective, paradigm 3
```

**Practical approach:** Find a verb with similar conjugation, then use the
same paradigm ID:

```sh
lua rus_tool.lua find писать         # → paradigm 3
lua rus_tool.lua add "сражаться" "V:i:3"  # same paradigm
```

For perfective verbs with an imperfective paired stem, the stem bytes must be
added manually to the .RUS file after the 4-byte header.

### Domain-specific dictionaries

For specialized text (adventure games, business, computing), create overlay
dictionaries that load after BASE.DIC. These can:

1. **Add new words** not in BASE.DIC (preferred)
2. **Override existing words** for domain-specific meaning (use sparingly)

**Example: `data/DUNGEON.DIC`**

```
# New entries (not in BASE.DIC):
orc*Nорк                           # adventure vocabulary
west of*PРк западу от              # multi-word phrase
front door*NNWAпередняяNдверь      # compound noun

# Overrides (domain-specific meaning):
field*Nполе                        # adventure: "open field" not "abstract domain"
boarded*Aзаколоченный              # adventure: "boarded up" not "covered with boards"
west*Dна западе                    # tag fix: N+A+D → D to avoid token duplication
```

**When to override:**
- BASE.DIC has abstract/general meaning, domain needs concrete/specific
  - `field`: область (abstract) → поле (physical ground)
  - `boarded`: обшитый досками (multi-word) → заколоченный (single adj)
- BASE.DIC has complex tags that cause parser issues
  - `west`: N+A+D (noun+adj+adverb) → D (adverb only)

**When NOT to override:**
- BASE.DIC has multiple meanings you want to preserve
  - `door`: NN.дверь{physical door};вход{entrance} — keep both meanings
  - `key`: NN.ключ{lock};клавиша{keyboard} — keep both meanings
- Domain meaning is same as base meaning — no override needed

**Loading order:**
```sh
lua init.lua "text" --dict=data/DUNGEON.DIC
# 1. BASE.DIC loaded first
# 2. DUNGEON.DIC loaded after, overrides apply
```

### Checking for conflicts

Before adding overrides, check if BASE.DIC already has the word:

```sh
lua demo/dict.lua find field           # shows: Nобласть
lua demo/dict.lua find field --partial  # shows all "field" entries
```

If the entry exists and you need domain-specific meaning, override with `--force`.
If the entry doesn't exist, just add it normally.

## Testing

Primary test instructions are in `TESTING.md`.

Quick run:

```sh
./test/run_all.sh
```

LTGOLD compatibility checks (DOSBox/LTPRO) are also documented there.

## Debug and Diagnostics

### Debug levels (stdout detail)

```sh
lua init.lua --debug          # level 1: rule + compiler output
lua init.lua --debug=2        # level 2: +match attempts, context
lua init.lua --debug=3        # level 3: +hex dumps, all internals
```

### Diagnostic categories (named channels)

Toggle specific diagnostic channels independently of debug level:

```sh
lua init.lua --diag=multi,tag,word    # enable named categories (comma-sep)
lua init.lua --diag-file=DIAG.OUT     # redirect diagnostics to file
lua init.lua --config=DEBUG.CNF       # load config file
```

| Category | What it shows |
|----------|---------------|
| `multi`  | Multi-form nouns/verbs leaking all dictionary variants |
| `tag`    | Tag-resolution decisions (e.g. Z→V, Q→L) |
| `word`   | Unknown/unrecognized words and tags |

### Config file (DEBUG.CNF)

```
diag = multi, tag, word
diag_file = DIAG.OUT
debug = 0
```

Boolean flags (`--diag`) override config file values.

## Decompilation & Reverse Engineering Artifacts

When decompiling or annotating parts of `LTPRO.EXE`, store results in
`LTGOLD/decompiled/` for future reference:

```
LTGOLD/decompiled/
├── README.md              # Index of decompiled functions and their purposes
├── dict_load.asm          # Dictionary loading/parsing (WA...N... format)
├── rule_engine.asm        # T1-T8 pattern matcher (0xb0ff, 7502 bytes)
├── morph_engine.asm       # Segment-1 morphological output engine
├── t1_dispatch.asm        # T1 table init and dispatch
├── t2_dispatch.asm        # T2 table init and dispatch
├── ...
```

**Naming convention:** `<function_name>.asm` with annotated disassembly.
Each file should include:
- Function address (r2 vaddr and file offset)
- Known constants and table references
- Cross-references to other functions
- Plain-English description of what the code does

**Tools:** Use `r2` disassembly (SLEIGH/r2ghidra not available for 16-bit x86).
See `LTGOLD/r2_tools.py` for pre-built analysis commands.

## Current Work State

**Objective:** 1:1 matching of LTGOLD's DEMO.OUT reference output for all 10 DEMO.TXT sentences.

### What was done

**Previous session:**
- W token expansion, G→N fallback, case propagation, X copula, find_form() rewrite.

**This session (T8-NEG/T8-COORD grammar pass):**
- **F printer Y scan past negation** (`compiler.lua`): Changed `is_perfect` check to scan backward past K/k tokens for Y auxiliary (e.g. "has not seen" → Y+K+F). Fixes "She has not seen him." — "увидeла" (past tense) not "увидена" (participle).
- **X1 past-tense propagation via V= marker** (`parser.lua`, `compiler.lua`): Added shared `x1_past_context` flag set when X1 ("did") is consumed by ` ` action. The V action handler now uses V= (simple past, no perfective switch) instead of V! (which triggers switch). Compiler V printer handles V= to set e.past but suppress perfective switch via `e.simple_past`. Fixes "He did not write the report." — "писал" (imperfective past) not "написал" (perfective past).
- **y1 genitive government** (`compiler.lua`): y1 ("нет" = there is no) now sets `e.form = case["Р"]` (genitive) on the governed noun. Fixes "There is no problem here." — "проблемы" (genitive) not "проблема" (nominative).
- **V1 aspect preservation under modals** (`compiler.lua`): Z printer infinitive path now checks `t:match('^V1')` — V1 tokens (dictionary-stored present-tense surface forms like понимать) keep their original imperfective aspect under modals instead of switching to perfective. Fixes "She can read and understand it." — "понимать" not "понять".
- **e-tag tense default** (`compiler.lua`): Lowercase `e` (ambiguous infinitive/past/participle) no longer defaults to past tense; only uppercase `E` (definite past) forces e.past. Fixes "He put it on the table." — "устанавливает" (present) not "установил" (past).
- **E printer verb_frame support** (`compiler.lua`): E printer now sets `e.verb_frame` so preposition case overrides work for e-tagged verbs. Added "устанавливать" frame (accusative with "на"). Fixes "He put it on the table." — "на стол" (accusative) not "на столе" (prepositional).
- **P printer particle absorption** (`compiler.lua`): P tokens with a D (adverb) alternative following a verb and without a following noun are now suppressed (absorbed by the verb). Fixes "A small red ball fell down." — removes extra "вниз по".
- **E printer perfective switch guard** (`compiler.lua`): The E printer's perfective switch now requires `e.past` to be true, preventing unwanted aspect changes for e-tagged verbs.

### Verification

```sh
lua compare.lua          # sentence-level comparison against DEMO_REFERENCE.TXT
lua demo_walk.lua        # word-by-word N/M progress through DEMO.TXT
lua init.lua             # original test sentence
```

### Remaining data gaps

- **LTGOLD flag semantics** — flags are extracted in `rules.lua`, but many constituent-type values still lack general runtime semantics.
- **Verb-frame coverage** — `compiler.lua` has a table-driven frame mechanism, but only frames required by the verified DEMO sentences are populated.
- **Analyzer stem search** — all 43 suffix records come from `LTGOLD.dat`; the executable's complete spelling-change algorithm is only partially reproduced by generic stem candidates.
- **T5/T6 constituent indices** — numeric actions still use the legacy reorder implementation except for W verb constituents, whose head class now prevents the invalid `NW` reorder.

### Next likely steps

1. Decode the remaining LTGOLD constituent flag values and replace fallback context scans with stored constituent metadata
2. Extract or decompile the analyzer's complete stem-candidate algorithm around the suffix table at offset 2136
3. Expand verb-frame coverage from LTGOLD dictionary/table evidence
4. Add a broader corpus regression suite beyond the ten DEMO sentences
