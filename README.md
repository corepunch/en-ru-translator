# en-ru-translator

A Lua port of the LTGOLD / SARMA 2.0 English→Russian rule-based translator (LinguaTech Systems, 1992).

## Requirements

Lua 5.3+ (uses bitwise operators `>>`, `&`).

## Usage

```sh
# Translate a sentence — prints Russian output
lua init.lua "She can speak Russian."

# Full debug trace: rule firings, token dump, compiler state
lua init.lua "She can speak Russian." --debug

# Translate from stdin
echo "The door is open." | lua init.lua

# Encode/decode CP866 ↔ UTF-8
printf 'Привет' | lua bin/encoding.lua encode > greeting.cp866
lua bin/encoding.lua decode < greeting.cp866
```

## How it works

```
Input (English)
  → Tokenize    — look up each word in BASE.DIC; unknown words get tag #
  → Parse       — apply 692 pattern-matching rules in 8 passes (T1–T8)
  → Compile     — inflect tokens into Russian using BASE.RUS + paradigms.lua
  → Output (Russian)
```

T1–T4 rewrite grammatical tags (clause structure, VP chains, idioms).
T5–T6 reorder tokens for Russian word order.
T7–T8 annotate constituent boundaries used by the compiler for case/inflection.

## Adding a word

Dictionary entries live in `data/BASE.DIC` (one word per line, CP866 encoded).
The format is `english_word*CODES` where CODES encodes grammatical class and Russian translation(s).

**Simple entries:**

```
economy*Nэкономика;экономия     noun — multiple meanings separated by ;
economize*Vэкономить            verb
economic*Aэкономический         adjective
quickly*Dбыстро                 adverb
```

**Ambiguous entries** (word is both verb and noun, for example):

```
answer*ZотвечатьNответ          Z = V-N-A ambiguity: verb first, then N and/or A
work*ZработатьNработаAрабочий   all three roles
```

**Multi-word phrases** are written as a single entry with spaces:

```
turn off*Vвыключать
in spite of*Pнесмотря на
```

The loader (`core/load.lua`) indexes multi-word entries into a nested trie, so `"turn off"` is
looked up as `en_ru["turn"]["off"].__lex`.

**-ing / -ed forms** that differ from the base: add a back-reference with `\base_form` so the
system resolves other forms from the infinitive entry rather than listing them again:

```
interesting*GинтересоватьсяAинтересный\interest
crossed*Eпересекать\cross
```

After editing `BASE.DIC`, no recompilation is needed — the file is parsed at startup.

## Adding a rule

Rules live in `core/rules.lua`. Each rule is one line inside one of the 8 `table.insert` blocks:

```lua
{ flags, "PATTERN", "REPLACEMENT" },
```

- **flags** — constituent-type index (0x00–0x3F); use 0x00 for a plain rewrite rule
- **PATTERN** — sequence of tag matchers (see below)
- **REPLACEMENT** — one character per matched position

### Pattern syntax

| Element | Matches |
|---------|---------|
| `N` | A single noun token |
| `[NZ]` | One token whose tag is N or Z |
| `<KD>` | Zero or more tokens whose tag is K or D (lazy) |
| `<$>` | Zero or more of any token |
| `~Z` | A token that is NOT Z |
| `` `be` `` | The exact English word "be" |
| `*` | Sentence boundary (start or end) |

Common tags: `Z`=ambiguous V/N/A, `N`=noun, `V`=verb, `A`=adjective, `P`=preposition,
`X`=aux be, `U`=modal, `K`=not, `G`=gerund, `E`=past participle, `R`=pronoun.
Full tag table: [docs/rules.md](docs/rules.md).

### Replacement syntax

| Element | Effect |
|---------|--------|
| `N` | Resolve token to noun form |
| `V` | Resolve to verb form |
| `@` | Apply transform using the matched pattern character |
| `$` | Keep the `<>` captured span unchanged |
| `.` | Keep token unchanged |
| `' '` (space) | Suppress token (no output) |

**Example — resolve a Z-ambiguous token to noun:**

```lua
{ 0x00, "~<UVXY>Z", "N" },   -- if no modal/aux before it, Z is a noun
```

**Example — suppress the article before a proper noun:**

```lua
{ 0x00, "T#", " ." },        -- T (article) + # (unknown) → suppress T, keep #
```

Rules are applied left-to-right across the token stream. Add your rule to the appropriate
pass table: T1–T4 for tag rewrites, T5–T6 for word-order reordering. The rule tables run
in order T1 → T2 → … → T8, so a tag set by T2 is visible to T3.

## Testing

```sh
cd LTGOLD/

# Run Lua engine vs LTPRO.EXE reference outputs (10 test sentences)
./test_compare.sh --all

# Test a single sentence
./test_compare.sh "She can speak Russian."

# Capture fresh reference outputs from the original binary (requires dosbox-x)
./test_compare.sh --capture
```

Reference outputs live in `LTGOLD/refs/`. The suite covers: modal chains, PP case
assignment, past tense, relative clauses, passive voice, NP word-order reordering,
and verbal negation.

## Project layout

```
init.lua                 CLI entry point
dictionary_store.lua     Loads BASE.DIC / BASE.RUS for the core
core/
  translator.lua         Public translation API (tokenize → parse → compile)
  parser.lua             Rule application engine
  rules.lua              692 pattern-matching rules (T1–T8)
  compiler.lua           Russian inflection and output generation
  paradigms.lua          Noun / adjective / verb declension tables
  load.lua               Dictionary file parser (CP866 trie)
  utils.lua              Tokenization, CP866 ↔ UTF-8, token inspection
  encoding.lua           Pure CP866 ↔ UTF-8 module
bin/
  encoding.lua           Unix stdin/stdout adapter for encoding
data/
  BASE.DIC               English → grammatical codes + Russian translations
  BASE.RUS               Russian stems → morphological data
  BUSINESS.DIC           Business vocabulary supplement
  COMPUTER.DIC           Computer vocabulary supplement
debug/
  T1.txt … T8.txt        Annotated binary dumps of all 8 rule tables
docs/                    Reference documentation
  pipeline.md            Stage-by-stage pipeline walkthrough
  rules.md               Complete pattern/replacement syntax + tag table
  dictionary.md          BASE.DIC / BASE.RUS binary format
  paradigms.md           Morphological inflection tables
  tools.md               Python reverse-engineering tools
work/                    Active research notes (reverse-engineering in progress)
LTGOLD/                  Original DOS binaries + test harness
AGENTS.md                Guide for AI coding assistants working on this project
```

## Further reading

- [docs/case-study-zork.md](docs/case-study-zork.md) — worked example: diagnosing errors, adding vocabulary, adding rules
- [docs/rules.md](docs/rules.md) — complete pattern/replacement syntax, tag table, flag semantics
- [docs/dictionary.md](docs/dictionary.md) — full BASE.DIC / BASE.RUS binary format
- [docs/pipeline.md](docs/pipeline.md) — detailed stage-by-stage walkthrough
- [ARCHITECTURE.md](ARCHITECTURE.md) — system overview and debug flags
- [DISASSEMBLY.md](DISASSEMBLY.md) — reverse-engineering the original binary with radare2
