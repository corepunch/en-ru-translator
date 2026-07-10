# PLAN.md — Reverse-Engineering the LTGOLD Rule System

## What We're Dealing With

LTGOLD (= SARMA 2.0, LinguaTech Systems, 1992) is a rule-based English→Russian machine
translator. It works in a **cascaded rewrite pipeline**:

```
Input tokens → T1 → T2 → T3 → T4 → T5 → [T6/T7/T8 validate] → Compile → Russian output
```

Each table is a list of `{priority, pattern, replacement}` triples. The engine scans the
token stream left-to-right for each rule. Patterns describe sequences of grammatical tags;
replacements rewrite those tags in-place.

The three objectives map onto concrete open questions:

| Objective | Open questions |
|-----------|---------------|
| **INPUT symbols** in patterns | What do `b`, `e`, `f`, `u`, `v`, `x`, `y`, `m`, `q`, `s`, `t`, `i`, `a`, `o`, `c`, `:`, `(`, `)`, `{`, `}`, `^`, `+`, `&`, `\|`, `;`, `_`, `-`, `%` mean inside a pattern? What does `$` in `<$>` capture? What do `~*` (negated boundary) and `[*)]` do exactly? |
| **OUTPUT symbols** in replacements | What do `^`, `=`, `;`, `+`, `&`, `\|`, `{`, `}`, `(`, `)`, `j`, space, `m`, `f`, `b`, `v`, `x`, `y`, lowercase letters do in replacements? What does empty output `""` do (Tables 6+7)? |
| **Table sequence** | Why 7–8 tables? What does each table guarantee at its output, and why does the next one need it? Why do T6/T7/T8 have no actions? |

---

## Current State of Knowledge

### Confirmed pattern chars
`Z N A V P D E G S C X U F R Q J T # ? W I w` — all mapped in RESEARCH.md / RULES_APPLIED.md.

### Confirmed replacement chars
`@` (transform current), `.` (keep), `$` (captured group ref), space (insert separator),
`` `word` `` (insert literal Russian), tag letters that relabel.

### Confirmed table roles (coarse)
T1: clause boundary / discourse connectives  
T2: modal auxiliaries, passive, relative clauses  
T3: "that"-clauses, relative pronouns  
T4: idioms, collocations, tag normalization  
T5: late cleanup (copula, "is the")  
T6/T7/T8: structural validation / no-action "protect" rules

### Confirmed lowercase = "already resolved"
`n g j k l v b p a c m q r s t x y e u` are lowercase variants of uppercase tags,
used as "this slot was already consumed" markers.

### Resolved tag meanings (from dic.txt)

All single-letter tags now have confirmed or near-confirmed meanings.
See RULES_APPLIED.md Step 3 for the full table. Key corrections vs. earlier docs:
- `B` = infinitive particle 'to' (perfective) — NOT copula; `X` = auxiliary 'be'
- `K` = 'not', `k` = 'no' — negation particles, not modal markers
- `H` = digits — not possessive
- `M` = indirect/object pronoun — not adverbial modifier
- `O` = demonstrative pronoun — not object-case marker
- `I` = cardinal numeral — not "bare infinitive"
- `D` = adverb/parenthetical — not "do-support"
- `Y`/`y` = 'have' (two senses), `X` = 'be'
- `Z` = V-N-A ambiguity (resolved by rules into `V`, `N`, or `A`)

### Working assumption for unknown symbols

**Default hypothesis:** a symbol means the same in rule patterns/replacements as it does in the dictionary format (dic.txt). Verify this first using binary patching or disassembly. If it doesn't hold — the symbol behaves differently in rules — then determine the rule-specific meaning from the C code or patch experiments.

### Remaining unknowns (operator/punctuation symbols only)

1. `$` in `<$>` — captures a span, referenced in replacement by `$`; exact span semantics unclear
2. `^` in replacements — word-join or clause-boundary marker?
3. `=` in replacements — appears in `"<$>,\"` → `"\|$,="` — case-setting or equality marker?
4. `;` in replacements — appears in `"@J$;"` — separator insertion?
5. `&` in patterns/replacements — coordination marker (`ACA` → `@&`)?
6. `+` in patterns — appears in `[g+]Z`; rare
7. `(` `)` `{` `}` — grouping in both pattern and replacement; partially implemented
8. `%` — rare, appears in `<H%D,>Z`; percentage or modifier flag?
9. `!` — rare, appears in `"NI!мес!"` — inline Russian literal injection?
10. `_` — appears in `_Z[_*]` — token boundary or special separator?
11. `p` — appears as lowercase of `P` (preposition, already resolved); confirm from binary
12. Priority byte `0x00`–`0x45` — rule ordering / category mask; not yet confirmed

---

## Work Plan

### Phase 1 — Binary patching experiments (workflow variant A)

**Goal:** Confirm or correct our tag guesses by observing output changes.

**Tool:** `LTGOLD/patch_rules.py` + DOSBox-X + a fixed test sentence.

**Test sentence:** `"He was arrested by the police last year."`
This exercises passive voice (E/F), `by`-phrase, auxiliary `was` (B), noun, adverb.

#### 1a. Baseline
Run LTPRO.EXE with the unmodified binary. Record exact CP866 output bytes as baseline.

#### 1b. Isolate each table
For each table T1…T5 individually (T6 skip, T7/T8 can be zeroed):
- Zero that table alone, run, record output delta.
- The delta reveals what semantic work that table does.

#### 1c. Surgical single-rule patches
After 1b identifies which table is responsible for a behavior, zero single rules:
- Find rule record offset = `DAT_BASE + (LTGOLD_offset - SHIFT) + rule_index * rec_size`
- Zero just that one record (e.g. 9–10 bytes).
- Run, compare output.

This directly answers: "what does THIS pattern+replacement do?"

**Extend `patch_rules.py`** to support:
```
python3 patch_rules.py LTPRO.EXE LTPRO_PAT.EXE --table T2 --rule 5
```

#### 1d. Symbol-specific tests
Design test sentences that exercise one symbol at a time:
- `b`: `"She was being followed."` — tests lowercase `b` in `bG → BV`
- `e`: `"She has been seen."` — exercises `e`/`E` interaction
- `^`: `"to go"` → tests `^` in replacements (word join?)
- `=`: look for rules with `=` in replacement, craft matching input

### Phase 2 — Disassembly (workflow variant B)

**Goal:** Read the actual C code that interprets patterns/replacements; confirm all symbol meanings from source.

**Tool:** `r2 + r2ghidra` as documented in DISASSEMBLY.md.

#### 2a. Re-generate decompiled C

```sh
# Rule processor (main matching loop)
r2 -q -e bin.cache=true -A \
   -c "pdg @ 0x0004d608" -c q LTGOLD/LTGOLD.EXE \
   | sed 's/\x1b\[[0-9;]*m//g' > /tmp/ltgold_4d608.c

# Replacement handler
r2 -q -e bin.cache=true -A \
   -c "pdg @ 0x0004e1e3" -c q LTGOLD/LTGOLD.EXE \
   | sed 's/\x1b\[[0-9;]*m//g' > /tmp/ltgold_4e1e3.c

# Secondary function called by rule processor
r2 -q -e bin.cache=true -A \
   -c "pdg @ 0x0004e95d" -c q LTGOLD/LTGOLD.EXE \
   | sed 's/\x1b\[[0-9;]*m//g' > /tmp/ltgold_4e95d.c
```

#### 2b. Map replacement byte dispatch

In `0x4E1E3` (replacement handler), find the switch/if-else on the replacement byte.
Every `case 0xXX:` or `cmp al, 0xXX` corresponds to one replacement symbol.

Symbols to look up: `0x5E` (^), `0x3D` (=), `0x3B` (;), `0x7C` (|), `0x26` (&),
`0x2B` (+), `0x6A` (j), `0x5F` (_), `0x21` (!).

Expected outcome: a complete table mapping every replacement byte to its semantic action.

#### 2c. Map pattern byte dispatch

In `0x4D608` (rule processor), find the `try_match_pattern` equivalent.
Look for comparisons against `0x28` `(`, `0x29` `)`, `0x7B` `{`, `0x7D` `}`, `0x2D` `-`.
These reveal how those chars are parsed in patterns.

#### 2d. Map T6/T7/T8 "no-action" semantics

Find where the code calls the validation tables and what happens after a match:
- Is a flag set on the token? (e.g. `token.flags |= PROTECTED`)
- Does matching prevent the token from being matched again by later tables?
- Cross-reference calls to the T6/T7/T8 dispatch with what the compiler reads later.

#### 2e. Priority byte semantics

The first byte of each rule (0x00–0x45 seen in rules.lua) is discarded in our Lua
implementation. In the binary, find where rules are sorted or filtered by this byte.
Likely answers: rule priority within a pass, or a rule-category mask.

### Phase 3 — Synthesis and documentation

After phases 1 and 2 produce enough data:

#### 3a. Complete the tag reference table in RULES_APPLIED.md

For every symbol in patterns and replacements, write:
- **Meaning** (confirmed or inferred)
- **Source** (binary address OR patch experiment OR rule context)
- **Example rule** from rules.lua

#### 3b. Document each table's contract

For T1…T8, write:
- **Precondition:** what the token stream looks like coming in
- **Work done:** what transformations happen
- **Postcondition:** what is guaranteed going out
- **Why it must precede the next table**

#### 3c. Document the empty-output case

Rules in T6/T7/T8 have no replacement. Document exactly what "matching with no action"
does: does it set a protection flag, skip a token, or something else?

#### 3d. Implement missing symbols in parser.lua

Once meanings are confirmed:
- Implement `^`, `=`, `;`, `|`, `&`, `+`, `j` in `replace()` in [parser.lua](parser.lua)
- Implement `(` `)` `{` `}` grouping in `try_match_pattern()`
- Implement priority sorting: sort rules by first byte before applying

#### 3e. Run full test suite

Compare LTPRO.EXE output with Lua implementation output for 10–20 diverse sentences.
Target: identical or near-identical Russian output.

---

## Execution Order

```
Phase 1a  →  baseline output captured
Phase 1b  →  per-table responsibility mapped
Phase 2a  →  C code generated
Phase 2b  →  replacement symbols confirmed from C
Phase 2c  →  pattern symbols confirmed from C
Phase 1c  →  single-rule patches confirm specific rules
Phase 1d  →  symbol-specific patches for remaining unknowns
Phase 2d  →  T6/T7/T8 semantics from C
Phase 2e  →  priority byte semantics from C
Phase 3a  →  RULES_APPLIED.md completed
Phase 3b  →  table contracts documented
Phase 3c  →  empty-output case documented
Phase 3d  →  parser.lua updated
Phase 3e  →  end-to-end test
```

Phases 1 and 2 can be interleaved: start 2a (decompile) while 1a/1b run.

---

## Tooling Extensions Needed

### 1. Single-rule patcher (extends patch_rules.py)

```python
python3 patch_rules.py LTPRO.EXE LTPRO_PAT.EXE --table T2 --rule 5
```

Zero record at index 5 in T2 only. All other records unchanged.

### 2. Rule dumper (new script: dump_rules.py)

Read rule tables from LTGOLD.dat, print each record as:
```
T2[005]  flags=0x3A  pattern="Z`of`N"  action="@N"
```

This makes it easy to cross-reference `rules.lua` entries against binary offsets.

### 3. DOSBox wrapper (run_test.sh)

```sh
#!/bin/sh
echo "$1" > LTGOLD/IN.TXT
dosbox-x -silent \
  -c "mount c $(pwd)/LTGOLD" \
  -c "c:" -c "LTPRO.EXE IN.TXT OUT.TXT -F-" -c "exit" 2>/dev/null
python3 -c "print(open('LTGOLD/OUT.TXT','rb').read().decode('cp866'))"
```

One-line test harness. Use `LTPRO.PAT.EXE` to test patched versions.

---

## Acceptance Criteria

RULES_APPLIED.md is done when:

- [ ] Every pattern symbol has a confirmed meaning + source + example
- [ ] Every replacement symbol has a confirmed meaning + source + example
- [ ] `$` capture semantics are fully documented (what `<$>` captures, how `$` in replacement refers to it)
- [ ] T6/T7/T8 "protect" semantics are documented
- [ ] Priority byte meaning is documented
- [ ] Each table's role, precondition, and postcondition are written
- [ ] parser.lua implements all confirmed symbols
- [ ] Lua output matches LTPRO.EXE output for ≥10 test sentences

---

## Key Files

| File | Purpose |
|------|---------|
| [rules.lua](rules.lua) | All 644 rules — primary reference |
| [parser.lua](parser.lua) | Current Lua pattern engine — extend here |
| [RULES_APPLIED.md](RULES_APPLIED.md) | Target doc — fill in as we learn |
| [RESEARCH.md](RESEARCH.md) | Accumulated findings |
| [LTGOLD/patch_rules.py](LTGOLD/patch_rules.py) | Table-zeroing tool — extend for single-rule patches |
| [DISASSEMBLY.md](DISASSEMBLY.md) | r2ghidra workflow |
| `LTGOLD/LTPRO.EXE` | Decompressed binary (208K) — patch target |
| `LTGOLD/LTGOLD.EXE` | Original compressed binary — disassembly source |
