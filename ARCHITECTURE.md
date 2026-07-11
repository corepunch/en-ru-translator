# ARCHITECTURE.md

> **Documentation has moved to [`docs/`](docs/INDEX.md)**

This file is a summary. Detailed documentation is split into focused files:

| Document | Description |
|----------|-------------|
| [`docs/pipeline.md`](docs/pipeline.md) | Translation pipeline: tokenize → parse → compile |
| [`docs/paradigms.md`](docs/paradigms.md) | Morphological tables: nouns, adjectives, verbs, pronouns |
| [`docs/dictionary.md`](docs/dictionary.md) | Binary format of BASE.DIC / BASE.RUS |
| [`docs/rules.md`](docs/rules.md) | Pattern matching syntax and replacement tokens |
| [`docs/tools.md`](docs/tools.md) | Python extraction tools for reverse engineering |

## Quick Overview

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Input Text  │───▶│  Tokenize   │───▶│    Parse     │───▶│   Compile   │
│  (English)   │    │  + Lookup   │    │ (8 passes)  │    │ (inflect)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                         │                  │                  │
                    BASE.DIC          rules.lua          paradigms.lua
                    BASE.RUS         (692 rules)        (noun/adj/verb)
```

### Parse passes (T1–T8)

| Pass | Rules | Role |
|------|-------|------|
| T1 | 47 | Clause skeleton: Z disambiguation, J/j boundary injection, connectives |
| T2 | 157 | Core VP: modal/aux chains, passive voice, article suppression |
| T3 | 136 | Embedding: relative clauses, that-complements, gerund/inf phrases |
| T4 | 178 | Idioms, collocations, negation normalisation, final Z cleanup |
| T5 | 9 | NP word-order reorder (digit actions); fixed-count termination |
| T6 | 47 | Extended word-order: longer NPs, hyphenated compounds, verbal negation |
| T7 | 35 | NP/PP/VP structural guards — all no-action; flags = constituent-type index |
| T8 | 83 | Clause/VP structural guards — all no-action; flags = constituent-type index |

T7/T8 rules have no replacement action: they match constituents and annotate them with
a flags value (0–31) that the compiler uses to select the correct inflection strategy.

## Key Files

| File | Role |
|------|------|
| `init.lua` | Imperative CLI shell — parses options, writes output, and selects exit status |
| `translator.lua` | In-process translation API composing tokenizer, parser, and compiler |
| `dictionary_store.lua` | File adapter that loads LTGOLD dictionary tables for the core |
| `encoding.lua` | Pure CP866↔UTF-8 conversion module |
| `bin/encoding.lua` | Unix stdin/stdout adapter for `encoding.lua` |
| `rules.lua` | 692 pattern-matching rules from LTGOLD.EXE binary (8 tables T1–T8) |
| `parser.lua` | Applies rules to the token stream; implements pattern/replacement language |
| `compiler.lua` | Generates Russian output using morphological paradigms for correct inflection |
| `paradigms.lua` | Russian noun/adjective/verb declension and conjugation tables |
| `load.lua` | Parses LTGOLD `*.DIC`/`*.RUS` dictionary files (CP866 encoded trie) |
| `utils.lua` | Tokenization, token inspection, and compatibility encoding exports |
| `debug/T*.txt` | Annotated binary dumps of all 8 rule tables from LTGOLD.EXE |
| `LTGOLD/test_compare.sh` | Test harness: Lua output vs LTPRO.EXE reference per sentence |
| `LTGOLD/refs/` | Captured LTPRO.EXE reference outputs for 10 test sentences |

## Conventions

- **No comments** in Lua source files — keep code compact
- **No new dependencies** — pure Lua only, no luarocks
- **Match LTGOLD style** — preserve original rule order, pattern format, and code structure
- **CP866 throughout** — legacy encoding internally, UTF-8 only for display via `utils.decode()`

## Running

```sh
# Translate a sentence (quiet mode — prints only the Russian output)
lua init.lua "She can speak Russian."

# Translate with full debug trace (rule firings, token dump, compiler state)
lua init.lua "She can speak Russian." --debug

# Run the default test sentence
lua init.lua
```

Requires Lua 5.3+ (uses bitwise operators `>>`, `&`).

## Core and shell boundary

The translator follows Functional Core, Imperative Shell. Core modules accept
values and return values; command-line and file adapters own external effects.
Dependencies point from shells toward the core: `init.lua` loads dictionary data
through `dictionary_store.lua`, constructs `translator.lua`, and prints its return
value. `encoding.lua` can likewise be called directly or used as a Unix filter:

```sh
printf 'Привет' | lua bin/encoding.lua encode > greeting.cp866
lua bin/encoding.lua decode < greeting.cp866
```

## Debug mode (`--debug`)

Pass `--debug` as the second CLI argument to `init.lua`. This sets `_G.TRANSLATOR_DEBUG = true`
which gates trace output in both `parser.lua` and `compiler.lua`.

What you see with `--debug`:

1. **Rule firings** — every rule that matches prints `Applying <pattern> <action>` (parser.lua).
   Example: `Applying U<KAdD,'">[ZV]	@$V`

2. **Post-parse token dump** — after all 8 passes, each surviving token is printed with
   ANSI blue colour, showing its full CP866 content decoded to UTF-8:
   `R032она` → shown as `Rоная` (pronoun she, 3rd-person singular feminine)

3. **Compiler token trace** — for every token being compiled, prints:
   ```
   [i] tag=X  token=<decoded>  =>  <output>  e={inf=.. perf=.. plur=.. form=..}
   ```
   `e` = current morphological state (infinitive, perfective, plural, case form).
   Errors (missing base entry, nil paradigm) are printed on the line below.

## Dictionary debug utilities

### `utils.lua` API

| Function | Description |
|----------|-------------|
| `utils.decode(s)` | Decode CP866 string `s` to UTF-8; passes ASCII through unchanged |
| `utils.decode(s, true)` | Decode and strip to first consecutive high-byte run (primary Russian word only) |
| `utils.extract(s)` | Return first `[\127-\255]+` byte run from `s` raw (no conversion; used by paradigms) |
| `utils.debug(w)` | Recursively decode a token or dictionary trie node to a human-readable string |
| `utils.tokenize(sent, dic)` | Split English sentence into CP866 token array using dictionary trie |

### BASE.DIC token format

Tokens are CP866 strings with the structure `TAG form1 [TAG2 form2 ...]`:

| Example | Meaning |
|---------|---------|
| `Vговорить` | Tag `V` (main verb) + imperfective infinitive |
| `ZоткрытьNоткрытие` | Tag `Z` (ambiguous) + V-form + N-form |
| `R032она` | Tag `R` + plural-flag(0) + person(3) + gender(2) + word |
| `PВПвb` | Tag `P` + case-letter1 + case-letter2 + Russian preposition + suffix byte |
| `Uмочь` | Tag `U` (modal) + Russian word |

Tag letters are ASCII (e.g. `V`=0x56, `N`=0x4E); Russian words follow as CP866 bytes
(0x80–0xFF). Use `utils.decode(token)` to view a token, `utils.decode(token, true)` to
extract just the first Russian word.

### BASE.RUS paradigm entry format

Each entry maps a Russian base-form word to its morphological data:

| Bytes | Content |
|-------|---------|
| 0 | Tag letter (same as in BASE.DIC) |
| 1 | Aspect/type flags — bit 1: perfective marker |
| 2 | Noun agreement flags — bits 0-1: gender (0=neut, 1=masc, 2=fem); bit 2: plural-only |
| 3 | Paradigm table index (0–127) used by `paradigms.noun / verb / adjective` |
| 4 | Additional agreement byte |
| 5+ | Perfective stem (for imperfective verbs that pair with a perfective form) |

To inspect a BASE.RUS entry in Lua:
```lua
local base = {}  -- populated by compiler.base = base in init.lua
local b = base["говорить"]  -- key is UTF-8 decoded word
print(string.format("aspect=%02X gender=%d paradigm=%d", b:byte(2), b:byte(3)&3, b:byte(4)&~0x80))
-- perfective stem:
if #b > 5 then print("perfective:", utils.decode(b:sub(6))) end
```

## Testing

```sh
cd LTGOLD/

# Capture reference outputs from LTPRO.EXE (run once; requires dosbox-x)
./test_compare.sh --capture

# Run full 10-sentence test suite (Lua engine vs LTPRO.EXE reference)
./test_compare.sh --all

# Test a single sentence
./test_compare.sh "She can speak Russian."
```

Reference outputs live in `LTGOLD/refs/`. The 10 test sentences exercise:
modal + verb chains (T2), PP case assignment (T7), past tense (E/F),
relative clauses (T3/T8), passive voice (T2), NP word-order reordering (T5/T6),
and verbal negation (T6).
