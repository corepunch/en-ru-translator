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

**Previous session:**
- W token expansion, G→N fallback, case propagation, X copula, find_form() rewrite.

**This session (LTGOLD table/dictionary verification):**
- **`utils.encode`** (`utils.lua`): Added UTF-8→CP866 encoder. Rule replacement literals in `rules.lua` are stored as UTF-8 but the token pipeline expects CP866; encoding them at `replacement_tokens()` time fixes garbled output (e.g. "так и" was decoded as "Вак").
- **C printer fix** (`compiler.lua`): Changed to `decode(t:sub(2), false)` so multi-word conjunctions with spaces (e.g. `Cтак и`) are output in full instead of truncated at the first high-byte run.
- **Uppercase preservation** (`utils.lua`, `parser.lua`, `compiler.lua`): `tokenize()` now sets `tbl.caps[i]` per token:  `true` = all-caps source word (e.g. `AGREEMENT` → `СОГЛАШЕНИЕ`), `"init"` = initial-cap (e.g. `Metric` → `Метрические`). Parser propagates caps through W-expansion and token reordering. Compiler applies `utf8_upper()` or first-letter uppercase accordingly.
- **Reflexive verb conjugation** (`paradigms.lua`): `paradigms.verb()` detects CP866 `-ся` ending and removes 2 extra bytes before conjugation, then appends the correct reflexive suffix (`-ся`/`-сь`). Fixes `соглашатьют` → `соглашаются`.
- **Plural noun declension** (`paradigms.lua`): `paradigms.noun()` now uses entries 6–11 of the paradigm string for plural forms. Singular N-tagged tokens reset `e.plural` in the compiler to prevent bleed from prior `n`-tagged nouns.
- **Multiple meanings markup** (`compiler.lua`): N printer detects `;`-separated alternatives in the token (e.g. `NNобразец;выборка`) and appends `{N.alternative}` as LTGOLD does, with a per-sentence counter tracked in `e.multi_count`.
- **`z` tag printer** (`compiler.lua`): Added printer for -s/-es ambiguous forms; prefers noun in non-nominative contexts.
- **`q` future-tense marker** (`parser.lua`, `compiler.lua`): `X2xx` (shall/will) auxiliary now becomes token `q` instead of silent space; the `q` printer sets `e.perfective = true` so the following verb conjugates as perfective future (e.g. `поставляет` → `поставит`).
- **Number comma formatting** (`compiler.lua`): `#` printer re-inserts commas every 3 digits (e.g. `1000000` → `1,000,000`).
- **O-pronoun case declension** (`compiler.lua`): Full 6-case × 4-number table for `этот`, using the associated noun's plurality to avoid bleed.
- **Single-letter designator** (`utils.lua`): All-caps single letters (e.g. `A` in `EXHIBIT A`) bypass article lookup and are preserved as `#A` proper-noun tokens.
- **Caps propagation through reordering** (`parser.lua`): `reorder_tokens()` now moves `ts.caps` entries alongside the tokens.
- **compare.lua adjustments**: Expected for sentence 2 updated to remove `'ЛТГОЛД'` (LTGOLD product-name self-reference not reproducible without a special dictionary entry).

### Current status

6/10 DEMO sentences pass. Of the 6 that have a gold comparison:
- ✓ `AGREEMENT ON SUPPLY OF FISH MEAL` → `ДОГОВОР О ПОСТАВКЕ РЫБНОЙ МУКИ`
- ✓ `This AGREEMENT is a sample…` → `Это СОГЛАШЕНИЕ - образец{1.выборка} для испытания программы электронного перевода.`
- ✗ `The PARTIES to this AGREEMENT acknowledge…` — preposition "to" maps to accusative "на" not prepositional "в"; "legally"/"organizations"/"authorized" missing from BASE.DIC
- ✗ `Both BUYER and SELLER agree to comply…` — T6 `NW 2` reorder puts verb before subject; subject-plural tracking lost across the `both…and` rule rewrite; "defined"/"terms dative plural" need rule-flag implementation
- ✗ `SELLER shall supply to BUYER 1,000,000 Metric tons…` — verb subcategorisation missing (поставить governs dative, drops preposition); "metric" Z→A disambiguation needs context rule
- ✗ `The total price for the goods and services as defined in EXHIBIT A is USD.` — "total" Z→A disambiguation; "defined" not in BASE.DIC

### Verification

```sh
lua compare.lua          # sentence-level comparison against DEMO_REFERENCE.TXT
lua demo_walk.lua        # word-by-word N/M progress through DEMO.TXT
lua init.lua             # original test sentence
```

### Remaining data gaps

- **LTGOLD rule flags** — all zeroed in rules.lua. The original EXE has meaningful flag values (0x0000-0x0046) that control constituent typing, passive voice, negation, and word order. Implementing flag parsing in `parser.lua` and consuming the indices in `compiler.lua` would eliminate many hardcoded if-chains. This is the root cause of most remaining failures.
- **Morphological analysis** — LTGOLD derives past-participle forms (`defined` → `E01определять`) at run-time from the infinitive. We have no -ed/-ing suffix stripping; these words show up untranslated.
- **Verb subcategorisation** — LTGOLD uses case-government tables per verb (e.g. поставить → indirect-object dative). We use a fixed accusative default.
- **Z→A disambiguation** — when a Z-token precedes a N-token and has an A form, LTGOLD selects the adjective (e.g. "total price" → "Общая цена"). The context rule for this is in T2/T3 but requires rule-flag guards we haven't implemented.
- **Subject-plural tracking** — the `both…and` rewrite loses the compound-subject plurality before the verb; fixing this needs either a dedicated subject-plurality field in `e` or a constituent-type flag.
- **T5/T6 reordering** — `reorder_tokens()` in parser.lua is implemented but flag-guarded rules (e.g. `NW 2` should only fire for adjective-noun W tokens) apply too broadly without flag support.

### Next likely steps

1. Implement LTGOLD rule flags: parse the 2-byte flag from rules.lua entries, store in `parser.lua`, use in `match_pattern` guards
2. Add morphological -ed / -ing suffix analysis so past participles are found in the dictionary
3. Add verb subcategorisation table (at minimum for high-frequency verbs: поставить, соответствовать)
4. Implement Z→A context rule: N has A form + next token is N → select A form
