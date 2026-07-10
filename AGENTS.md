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

- **No comments** in Lua source files — keep code compact
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
