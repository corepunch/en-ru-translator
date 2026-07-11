# RESEARCH.md — Reverse Engineering Findings

Document of all findings from reverse-engineering LTGOLD.EXE. Updated as we discover new things.

## Provenance Research

**Status: CONFIRMED** — LTGOLD is the English-branded version of SARMA 2.0.

### Key Discovery: SARMA 2.0

LTGOLD and SARMA 2.0 are **the same translation engine** from the same company:
- **Company:** САРМА ЛТД (SARMA LTD), Saint Petersburg, Russia
- **Address:** Невский пр., д.176, а/я 562, тел. (812) 349-1940
- **Date:** 1992 (SARMA 2.0 documentation)
- **Copyright:** 1990-1993 LinguaTech Systems, USA / Russia (LTGOLD documentation)

### Relationship

| Product | Language | Documentation |
|---------|----------|---------------|
| SARMA 2.0 | Russian | `SAR2BI/SARMA1.DOC`, `SARMA2.DOC`, `DIC.DOC` |
| LTGOLD | English | `LTGOLD/README.ENG`, `LTGOLD/README.CYR` |

Both products:
- Use the same dictionary format (`*.DIC`, `*.RUS`)
- Use the same rule engine (pattern→action rules)
- Are from the same company (САРМА ЛТД / LinguaTech Systems)
- Translate English → Russian

### What SARMA Documentation Reveals

The `SAR2BI/DIC.DOC` file is the **dictionary system documentation** — it explains:
- How to encode English words with grammatical tags
- How to encode Russian words with morphological codes
- The dictionary format and structure

This documentation directly explains the codes we see in `BASE.DIC` and `BASE.RUS`.

### External Sources

**Confirmed:**
- Globalink and MicroTac led the early-1990s PC machine-translation market and merged in December 1994
- Globalink's engine "Barcelona" is documented as a rule-based transfer system with a proprietary rule editor exposing pattern→action "keyed rules"
- "Sokrat" was built by Arsenal (founded 1995, part of "Russian Office" suite) — a separate, competing product

**Searched but found nothing relevant:** BetaArchive forums, exetools.com reversing forum, direct site-restricted queries against old-dos.ru for "LTGOLD"

## Tooling Decision

**Primary tool:** radare2 with r2ghidra for decompilation and analysis.

**Fallback:** dis86 only if r2 output is too messy to understand.

**Reasoning:**
- r2ghidra already gives us working C code (4188 lines for the rule processor)
- No extra setup needed (BSL config, flat binary extraction)
- All analysis tools (`afl`, `axt`, `/x`) are built-in
- dis86 adds complexity without proportional benefit for our use case

**Workflow:** r2 → decompile with `pdg` → search C output with `rg` → go back to r2 for details.

See [DISASSEMBLY.md](DISASSEMBLY.md) for the complete workflow.

## Rule Tables in LTGOLD.dat

`LTGOLD.dat` is the data section extracted from `LTGOLD.EXE` at offset `0x50960`
(330080 bytes). The extraction was done with:

```sh
# Extract data section from EXE (offset 0x50960, size 61376 bytes)
dd if=LTGOLD.EXE of=LTGOLD.dat bs=1 skip=330080 count=61376
```

The EXE was decompressed with `UNLZEXE.EXE` before extraction. Rules are stored
in `LTGOLD.dat`, not as compiled code in the EXE.

### Table Locations

| Table | Offset | Entries | Record Size | Purpose |
|-------|--------|---------|-------------|---------|
| 1 | 3374 | 47 | 10 bytes | Clause-boundary detection, discourse connectives |
| 2 | 3854 | 157 | 10 bytes | Modal auxiliaries, passive "with/by", relative clauses |
| 3 | 5434 | 136 | 10 bytes | "that"-clauses, relative pronoun resolution |
| 4 | 11981 | 178 | 9 bytes | Idiom/collocation lexicalization, tag normalization |
| 5 | 16610 | 9 | 10 bytes | Late cleanup (copula agreement, "is the") |
| 6 | 16874 | 56 | 10 bytes | Structural stabilizers — no rewrite (protect compounds) |
| 7 | 17972 | 35 | 8 bytes | Final structural validation — no rewrite |
| 8 | 19158 | 83 | 8 bytes | Additional validation rules |

**Note:** Tables 6 and 7 have **no action strings** — they match patterns but don't modify
tokens. These are "recognize-and-leave-alone" rules that mark patterns as already
resolved, preventing downstream rules from mis-firing.

### Record Formats

**10-byte record:**
```
[pattern_offset:u16] [unknown:u16] [action_offset:u16] [unknown:u16] [flags:u16]
```

**9-byte record:**
```
[flags:u8] [pattern_offset:u16] [unknown:u16] [action_offset:u16] [unknown:u8]
```

**8-byte record:**
```
[pattern_offset:u16] [unknown:u16] [action_offset:u16] [flags:u16]
```

Pattern and action are null-terminated C-strings stored in the same data block.
Offset 0 means "no pattern" or "no action".

### Tables Without Actions

Tables 6 and 7 have **no action strings** — they match patterns but don't modify
tokens. These are "recognize-and-leave-alone" rules that mark patterns as already
resolved, preventing downstream rules from mis-firing.

## Code Structure

### Key Functions

| Address | Function | Role |
|---------|----------|------|
| `0x418FE` | `fcn.000418fe` | Main dispatcher (uses function table at `0x27c`) |
| `0x4D608` | `fcn.0004d608` | Rule processing function (355 blocks, 3144 bytes) |
| `0x4E1E3` | `fcn.0004e1e3` | Replacement token handler (35 blocks, 654 bytes) |
| `0x4E95D` | `fcn.0004e95d` | Called by rule processor (46 blocks, 433 bytes) |
| `0x414AF` | `fcn.000414af` | Command dispatch (calls `0x418FE`) |

### Pattern Matching Logic (from code analysis)

1. **`*` (wildcard)** checks `j==1` (start) or `j>#ts` (end) — sentence boundary
2. **`~` (negation)** inverts the match result via XOR
3. **`[` (select)** matches one of listed characters
4. **`<` (any)** matches zero or more of listed characters
5. **`` ` `` (literal)** matches exact English word

### Replacement Logic (from `0x4E1E3`)

The function at `0x4E1E3` handles replacement tokens:
- **`@` (0x40)** — triggers `find_and_replace()` on current token
- **`$` (0x24)** — references captured groups from `<...>` or `(...)`
- **`.` (0x2E)** — keep current token unchanged
- **`T` (0x54)** — checked in comparison, likely separator handling
- **`K` (0x4B)** — checked in comparison, likely special action

### Dispatcher Pattern (from `0x418FE`)

```c
// Simplified from decompiled code
if (command < 0x12) {
    func_ptr = table[command * 9];  // function table at 0x27c
    if (flag & 0x8000) {
        func_ptr[2]();  // alternate path
    } else {
        func_ptr[1]();  // normal path
    }
}
```

## Decoded Symbols

**Source:** `dic.txt` (SARMA 2.0 Russian documentation, authoritative tag legend).
In-rule meanings may differ from dictionary meanings; see notes.

### Grammatical Tags — Uppercase

| Tag | dic.txt meaning | Notes |
|-----|-----------------|-------|
| `A` | Adjective, ordinal numeral | |
| `B` | Infinitive particle 'to' (perfective verb) | NOT the copula; `X` is auxiliary 'be' |
| `C` | Coordinating/disjunctive conjunction | |
| `D` | Adverb, parenthetical | |
| `E` | -ed forms and irregular past | Past participle / simple past |
| `F` | Active present participle — **analyzer-generated** | compiler.lua uses `passive()` — possible mismatch |
| `G` | -ing verb forms | Gerund / present participle |
| `H` | Digits and their combinations | Numeric token; NOT possessive |
| `I` | Cardinal numeral | NOT "bare infinitive" |
| `J` | Conjunctions, phrase-boundary separators | Subordinating conj / complementizer |
| `K` | Negative particle 'not' | NOT "modal marker" |
| `L` | Relative word ', который' | Relative pronoun (resolved) |
| `M` | Indirect pronoun | Object pronoun ("him", "her", "them") |
| `N` | Singular noun | |
| `O` | Demonstrative pronoun | "this", "that" (standalone); NOT "object-case marker" |
| `P` | Preposition | |
| `Q` | Question word | |
| `R` | Personal pronoun | "I", "you", "he" |
| `S` | Demonstrative pronoun (second class) | Likely adjectival demonstrative ("this book") |
| `T` | Determiner (article) | Maps to `separator()` → empty output |
| `U` | Modal verb | "must", "can", "shall" |
| `V` | Main (content) verb | Resolved from `Z`; finite predicate |
| `W` | — (not in dic.txt) | Multi-word phrase marker |
| `X` | Auxiliary verb 'be' | is/are/was/were |
| `Y` | Auxiliary verb 'have' (possession) | 'have' as perfect auxiliary |
| `Z` | Ambiguity V-N-A | Unresolved: verb, noun, or adjective |

### Grammatical Tags — Lowercase ("already processed" or derived)

| Tag | dic.txt meaning | Notes |
|-----|-----------------|-------|
| `a` | Adjective-adverb subclass ("more", "less") | |
| `b` | Infinitive particle 'to' (imperfective verb) | Lowercase of `B` |
| `d` | Adverb/adjective ambiguity | |
| `e` | Coincidence of infinitive/participle-II/past tense | Ambiguous verb form |
| `f` | Determiner-expression (followed by NP) | e.g. "a lot of" |
| `k` | Negative particle 'no' | Attributive negation; `K` = 'not' |
| `l` | Movable relative 'whose' — **analyzer-generated** | Genitive relative pronoun |
| `m` | Compound indirect pronoun | "himself", "themselves" |
| `n` | Plural noun form | |
| `r` | Compound personal pronoun | "myself", "yourself" |
| `t` | Determiner — segment boundary — **analyzer-generated** | |
| `u` | Modal verb combination | "had better", "ought to" |
| `v` | Verb form -s/-es (3sg present) | |
| `w` | — (not in dic.txt) | Compound/multi-word flag (inferred) |
| `x` | Impersonal verb combination ("there is", etc.) | Existential construction |
| `y` | Auxiliary 'have' (existential/copular) | 'have' in non-possession sense |
| `z` | Ambiguity v-n | Unresolved: 3sg-s verb or noun |

### Pattern Syntax

| Syntax | Matches | Example |
|--------|---------|---------|
| `*` | Sentence boundary | `*Z*` = verb spanning full sentence |
| `[...]` | Character class | `[VZ]` = adjective OR verb |
| `<...>` | Any-match | `<VXY>` = zero or more adj/gerund |
| `~` | Negation | `~Z` = anything EXCEPT verb |
| `` ` `` | Literal word | `` `if` `` = the word "if" |

### Replacement Tokens

| Token | Action |
|-------|--------|
| `@` | Apply grammatical transformation |
| `$` | Reference captured group |
| `.` | Keep current token unchanged |
| `#` | Keep number/unknown token |
| `` `word` `` | Insert literal Russian word |
| `N`, `V`, `Z` | Change token's grammatical tag |
| `^` | Transform to noun form |
| `=` | Set case marker |
| `j` | Insert comma |
| `;` | Insert separator |
| ` ` (space) | Insert space in output |

## Unresolved Questions

- [ ] What do the `flags` bytes in rule records control?
- [ ] How are tables 7 and 8 (no actions) used?
- [ ] What is the exact structure of `BASE.RUS` binary codes?
- [ ] How does the dispatcher table at `0x27c` map commands to functions?
- [ ] What are the remaining offsets in `extract2.py` (2136, 16874, etc.)?
- [ ] How does `~*` (negated boundary) work in practice?
- [ ] What does `$` capture exactly — position in `<...>` group or something else?
