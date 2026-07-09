# RESEARCH.md — Reverse Engineering Findings

Document of all findings from reverse-engineering LTGOLD.EXE. Updated as we discover new things.

## Rule Tables in LTGOLD.dat

Rules are stored in `LTGOLD.dat` (extracted from EXE), not as compiled code.
The data section starts at file offset `0x6900`.

### Table Locations

| Table | Offset | Entries | Record Size | Purpose |
|-------|--------|---------|-------------|---------|
| 1 | 3374 | 47 | 10 bytes | Core structural patterns (verb phrases, negation, conditionals) |
| 2 | 3854 | 157 | 10 bytes | Detailed grammatical transformations (articles, pronouns, tenses) |
| 3 | 5434 | 136 | 10 bytes | Preposition handling, conjunction processing, special constructions |
| 4 | 11981 | 178 | 9 bytes | Passive voice, gerunds, complex verb forms |
| 5 | 16610 | 9 | 10 bytes | Final cleanup rules |
| 6 | 16874 | 56 | 10 bytes | Noun agreement patterns |
| 7 | 17972 | 35 | 8 bytes | Preposition/case rules (no actions — pattern-only) |
| 8 | 19158 | 83 | 8 bytes | Final rules (no actions — pattern-only) |

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

Tables 7 and 8 have **no action strings** — they match patterns but don't modify
tokens. These likely set internal flags or control subsequent rule processing.

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
