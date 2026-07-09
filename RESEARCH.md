# RESEARCH.md — Reverse Engineering Findings

Document of all findings from reverse-engineering LTGOLD.EXE. Updated as we discover new things.

## Provenance Research

**Status: UNCONFIRMED** — LTGOLD's exact identity and lineage remain unconfirmed.

No forum thread, changelog, leaked source tree, or documentation page mentioning "LTGOLD" by that exact name turned up, despite searching:
- old-dos.ru (site-restricted search and general queries)
- BetaArchive, VOGONS-adjacent abandonware indexes
- exetools.com's DOS-reversing forum
- ACL Anthology's MT Summit/TMI archive
- Russian-language searches for Cократ/Арсеналъ/Стилус/ПРОМТ history

**What is independently confirmed (not proof of lineage):**

- Globalink and MicroTac led the early-1990s PC machine-translation market and merged in December 1994
- Globalink's engine "Barcelona" is documented as a rule-based transfer system with a proprietary rule editor exposing pattern→action "keyed rules" — same two-part shape as `rules.lua` entries
- "Sokrat" was built by Arsenal (founded 1995, part of "Russian Office" suite) and is treated as one of exactly two competing engines of that era (the other being PROMT/Stylus)
- No evidence suggesting Sokrat licensed a Western engine — reads as independently-built Russian product

**Bottom line:** LTGOLD's exact identity and lineage remain unconfirmed.

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

### Grammatical Tags

| Tag | Meaning | Source |
|-----|---------|--------|
| `Z` | Verb | `load.lua:24` maps `Z` → `V` internally |
| `N` | Noun | |
| `V` | Adjective | Same as `A` |
| `A` | Adjective | Same as `V` |
| `P` | Preposition | May have case government info |
| `D` | Adverb | |
| `E` | Past participle | |
| `G` | Gerund / present participle | |
| `S` | Adjective (alternate) | |
| `C` | Conjunction | |
| `X` | Infinitive marker | |
| `U` | Unique verb form | "must", "can", "shall" |
| `F` | Passive participle | |
| `R` | Pronoun | `R013` = person 0, number 1, case 3? |
| `Q` | Question word | |
| `J` | Subordinating conjunction | |
| `T` | Empty / separator | |
| `#` | Number | |
| `?` | Unknown word | |
| `n` | Noun (plural) | lowercase = modifier |
| `w` | Lowercase modifier | |
| `W` | Phrase marker | Multi-word entry indicator |
| `I` | Idiom marker | |

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
