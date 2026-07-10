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
| `lisp.lua` | Unused list utility |
| `LTGOLD/` | Original DOS EXE, dictionaries, and Python extraction tools |

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

## Testing

1. Edit test sentences in `init.lua:81-97`
2. Run `lua init.lua`
3. Check output for correct Russian translation and grammatical inflection

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

## Current Work State

**Objective:** 1:1 matching of LTGOLD's DEMO.OUT reference output for all 10 DEMO.TXT sentences.

### What was done

- **W token expansion** (`parser.lua`): Multi-word phrase tokens (e.g. `WAэлектронныйNперевод`) are now expanded into separate `Aэлектронный` + `Nперевод` tokens after all rules run. Sub-resolve fallback skips W tokens to avoid orphaning trailing forms.
- **G→N fallback** (`compiler.lua`): Gerunds after prepositions (e.g. "testing" after "for") fall back to their noun form (`испытания`) instead of the verbal (`тестировать`).
- **Case propagation**: N printer no longer resets `e.form` to accusative, so preposition case (e.g. genitive from "для") propagates through the entire noun chain.
- **X copula**: Sets nominative case for predicate complements (`образца` → `образец`).
- **find_form()**: Rewritten with byte-scanning (CP866-aware) instead of broken gmatch pattern.
- **conventions**: Updated AGENTS.md to require comments on changes, prefer tables over ifs.

### Current status

4/10 DEMO sentences pass comparison. Sentence 1 now substantially matches:
- LUA:  `Это соглашение - образец для испытания программы электронного перевода.`
- LTGOLD: `Это СОГЛАШЕНИЕ - образец{1.выборка} для испытания программы электронного перевода 'ЛТГОЛД'.`

### Verification

```sh
lua compare.lua          # sentence-level comparison against DEMO_REFERENCE.TXT
lua demo_walk.lua        # word-by-word N/M progress through DEMO.TXT
lua init.lua             # original test sentence
```

### Remaining data gaps

- **BUSINESS.DIC, COMPUTER.DIC** — not loaded. Add to init.lua for wider vocabulary coverage.
- **LTGOLD rule flags** — all zeroed in rules.lua. The original EXE has meaningful flag values (0x0000-0x0046) that control constituent typing, passive voice, negation, and word order. Implementing flag parsing in `parser.lua` and consuming the indices in `compiler.lua` would eliminate many hardcoded if-chains.
- **T5/T6 reordering** — `reorder_tokens()` in parser.lua is implemented but correctness against original EXE is unverified. The "33" action duplicates tokens (see `ANN 33` rule).
- **Multi-dictionary chaining** — LTGOLD supported cascading through BUSINESS.DIC, COMPUTER.DIC via `/C` flag. Not implemented.

### Next likely steps

1. Load additional dictionaries (BUSINESS.DIC, COMPUTER.DIC) in init.lua
2. Experiment with LTGOLD rule flags: parse T7/T8 flags in parser, pass constituent-type index through context `e` to compiler
3. Fix T6 reordering: verify `reorder_tokens()` digit actions match original EXE behavior
4. Walk remaining 6 failing DEMO sentences and identify specific failures
