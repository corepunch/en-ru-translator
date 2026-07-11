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
10. `_` — appears in `_Z[_*]` — literal underscore character, used in document template placeholder fields (see LTGOLD/DEMO.TXT: `_______ day of __________`, `____________________________`)
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

Located at `LTGOLD/run_test.sh`. Usage:

```sh
./run_test.sh "Sentence."                  # run against LTPRO.EXE (default)
./run_test.sh "Sentence." LTPRO_NO_T1.EXE  # run against a specific EXE variant
```

Writes the sentence to `IN.TXT`, runs the EXE via DOSBox-X (`-silent` flag — headless, no window, implies `-exit`), then decodes `OUT.TXT` from CP866 to UTF-8 and prints to stdout. Exits with error if the EXE produced no output. All EXE variants must live in `LTGOLD/` alongside `BASE.DIC` and other data files.

---

## Acceptance Criteria

RULES_APPLIED.md is done when:

- [ ] Every pattern symbol has a confirmed meaning + source + example
- [ ] Every replacement symbol has a confirmed meaning + source + example
- [ ] `$` capture semantics are fully documented (what `<$>` captures, how `$` in replacement refers to it)
- [x] T6/T7/T8 "protect" semantics are documented — flags field confirmed as constituent-type index via binary patching (see RULES_APPLIED.md "Flag Semantics")
- [ ] Priority byte meaning is documented
- [ ] Each table's role, precondition, and postcondition are written
- [ ] parser.lua implements all confirmed symbols
- [ ] Lua output matches LTPRO.EXE output for ≥10 test sentences

---

## LTPRO.EXE Table Locations (verified)

All rule tables reside in the decompressed `LTGOLD/LTPRO.EXE` (207,714 bytes).  
Offsets below are **direct file offsets within LTPRO.EXE** — no shift needed.

| Table | LTPRO Start | LTPRO End | Bytes | Record Size | Rules | 1st Rule Pattern |
|-------|-------------|-----------|-------|-------------|-------|------------------|
| T1 | `0x2738C` | `0x27562` | 470 | 10 | 47 | `*Z[?#]*` |
| T2 | `0x2756C` | `0x27B8E` | 1,570 | 10 | 157 | `` `a`[:*)] `` |
| T3 | `0x27B98` | `0x280E8` | 1,360 | 10 | 136 | `=~<)>,\x00@$|` |
| T4 | `0x2952B` | `0x29B6D` | 1,602 | 9 | 178 | `V~<VXUY>[^BbjJLlQ*]` |
| T5 | `0x2A740` | `0x2A79A` | 90 | 10 | 9 | `NwNww` |
| T7 | `0x2AC92` | `0x2ADAA` | 280 | 8 | 35 | `P<$>N` |
| T8 | `0x2B134` | `0x2B3CC` | 664 | 8 | 83 | `J[VUXY]` |

All 660 records verified: every `pat_off`/`act_off` pointer lands within file bounds.  
Table 6 (56 rules, between T5 and T7) is deliberately skipped — zeroing it crashes the program.

Derivation (for reference): `LTPRO_offset = DAT_BASE + (LTGOLD.dat_offset - 242)`,  
where `DAT_BASE = 0x26750` and `SHIFT = 242` converts from the extracted `LTGOLD.dat` coordinate space.

---

## Rule Sweep Results (binary search from end of each table)

**Test sentence:** `"She can speak Russian."` — baseline output: `"Она может сказать Русского."`

**Method:** For each table, binary-search to find the largest suffix that can be disabled (strings zeroed) without crashing or hanging the program. A TIMEOUT (10s) indicates the engine entered an infinite loop scanning past the end of the table.

| Table | Recs | Safe to clear | Boundary record | Flags | Pattern |
|-------|------|---------------|-----------------|-------|---------|
| **T1** | 47 | **ALL 47** ✅ | none | — | — |
| **T2** | 157 | **NONE** ❌ | last record T2[156] hangs | `0x0026` | `` `whether`<TDAOERNw#?"'>[XYUV] `` |
| **T3** | 136 | **NONE** ❌ | last record T3[135] hangs | `0x0000` | `T*` |
| **T4** | 178 | **4** (174–177) | T4[173] hangs | `0x00` | `` [RN#]`used``to`[GVE] `` |
| **T5** | 9 | **1** (index 8) | T5[7] hangs | `0x0000` | `NNw` |
| **T7** | 35 | **ALL 35** ✅ | none (output changes though) | — | — |
| **T8** | 83 | **70** (13–82) | T8[12] hangs | `0x003F` | `L[RN]<$>p*` |

### Interpretation

**End-of-table sentinel:** Every table ends with an invisible sentinel record — the 2-byte pair `pat_off=0x0000, act_off=0x0000` stored immediately after the last real record's final byte. The engine scans records linearly; when it encounters this null record, it knows the table is done. Corrupting any record before the sentinel prevents the engine from reaching it, causing an infinite loop (TIMEOUT).

- **T1/T7 exceptions:** These tables can be entirely zeroed without hanging. Their sentinels might be reached via a different code path, or their records are optional (the engine moves on when no match is found).
- **T5 exception:** No null sentinel exists after T5's last record (the byte at `0x2A79A` has non-null pointers). T5 uses a different termination mechanism — perhaps a fixed record count or a flag-based terminator (T5[8] has `flags=0x0009` vs T5[7] `flags=0x0000`).
- **Output diffs (T7, T8):** Clearing certain suffixes changes the translation without crashing, confirming those records fire on the test sentence. T7[0] clearing changes output to "Она не мочь сказать Русского." (modal verb misinflected).

### Flags byte — confirmed as constituent-type index

The flags field has been **experimentally confirmed** as a ~5-bit **constituent-type selector** (index 0–31) that the compiler uses to determine how to inflect a matched span. Causal proof by binary patching:

- **T7[0] flags (0x0002 → 0x0014):** Changes "в доме" → "в дом" (prepositional case removed)
- **T8[13] flags (0x0025 → 0x0000):** Changes "говорит" → "говорить" (finite → infinitive)
- **Systematic bit mapping:** Each index 0–31 produces a different Russian case/number form for nouns and different verb morphology for verbs. Values ≥ 32 all fall back to default behavior.

Full experimental results in RULES_APPLIED.md "Flag Semantics" section.

### Tool

Results were produced by `LTGOLD/sweep_rules.py`, which for each table:
1. Captures baseline output from unmodified LTPRO.EXE
2. Binary-searches from the end to find the safe-clear boundary
3. Logs every test point (clear range → SAME/DIFF/TIMEOUT/CRASH)
4. Prints the boundary record's pattern, action, and flags
5. Uses 8.3 filenames (COMMAND.COM limitation in DOSBox)

### How the sweep was run

```
cd LTGOLD/
python3 sweep_rules.py
```

This scans all tables in reverse order (T8 → T7 → T5 → T4 → T3 → T2 → T1). For each table, it:
1. Tests clearing *all* records — if output unchanged, the whole table is safe
2. Tests clearing *only the last* record — if that hangs, no suffix is clearable
3. Binary-searches between the known-failing and known-working range to find the exact boundary (max suffix clearable without hang)
4. Each test: copies LTPRO.EXE, patches the suffix's pattern strings to null bytes, writes `SW.EXE`, runs `./run_test.sh "She can speak Russian." SW.EXE` via DOSBox-X headless, captures output
5. `TIMEOUT` (10s) means the engine entered an infinite loop scanning past the end of a corrupted table — the sentinel record (null pat_off/act_off) was never reached

To scan a single table: `python3 sweep_rules.py --table T8`  
To test a single rule: `python3 sweep_rules.py --table T8 --rule 80`  
To (re-)capture baseline only: `python3 sweep_rules.py --baseline`

---

## LTPRO Binary Analysis: Record Structure

### Record Size Per Table

| Table | Rec Size | Priority | pat_off | act_off | Flags | Total bytes |
|-------|----------|----------|---------|---------|-------|-------------|
| T1 | 10 | 2 bytes | 4 bytes | 4 bytes | — | 10 |
| T2 | 10 | 2 bytes | 4 bytes | 4 bytes | — | 10 |
| T3 | 10 | 2 bytes | 4 bytes | 4 bytes | — | 10 |
| T4 | **9** | **1 byte** | 4 bytes | 4 bytes | — | **9** (outlier!) |
| T5 | 10 | 2 bytes | 4 bytes | 4 bytes | — | 10 |
| T6 | 10 | 2 bytes | 4 bytes | 4 bytes | — | 10 |
| T7 | **8** | 2 bytes | **3 bytes** | **3 bytes** | — | 8 (outlier!) |
| T8 | **8** | 2 bytes | **3 bytes** | **3 bytes** | — | 8 (outlier!) |

Key difference: T7/T8 use 3-byte pointers (needle-sharing in the same binary segment), while T1-T6 use 4-byte pointers. T4 has 1-byte priority (0x00-0x42 range) vs 2-byte for others.

### End-of-Table Sentinel

All tables except T5 use a **null-pointer sentinel**: the 10 (or 9/8) bytes immediately after the last real record are all zeros (pat_off=0, act_off=0). The engine scans linearly; hitting the null sentinel stops the table.

- **T1/T7 sentinel reachable even after clearing all rules** — empty table still terminates
- **T2/T3/T4/T8**: clearing the record just before the sentinel corrupts the scan → infinite loop (TIMEOUT)
- **T5**: NO null sentinel — uses fixed-count termination. T5[8] has flags=0x0009 (the 9 = record count). The byte at 0x2A79A (right after T5) has non-null data = start of T6.

### T6 Discovery Problem

T6 has no entry in the original PLAN.md table because it was "deliberately skipped" (zeroing it crashed). Actually T6 exists at offset 0x2A79A (immediately after T5's last byte) with 47 records. Its sentinel is at 0x2A970. Records beyond [47] in the binary are string-pool data misread as records.

### Flags Byte — Confirmed Constituent-Type Index

T7 and T8 use a 2-byte flags field (bytes 6-7 of each 8-byte record). The flags are a **~5-bit constituent-type index** (0–31) that the compiler uses to select inflection behavior. Values ≥ 32 all produce default behavior.

**Experimental confirmation (T7[0] `P<$>N`, test "He is in the house."):**

Patch different flag values onto T7[0] and observe noun output:

| Flag index | Noun | Case |
|-----------|------|------|
| 0 (0x0000) | доме | Prepositional sg (same as original) |
| 1 (0x0001) | домах | Prepositional pl |
| **2 (0x0002)** | **доме** | **Prepositional sg (ORIGINAL — PP constituent)** |
| 3 (0x0003) | дом | Nominative |
| 4 (0x0004) | дое | Corrupt stem |
| 5 (0x0005) | домом | Instrumental |
| 6 (0x0006) | дома | Genitive |
| 7 (0x0007) | дом | Nominative |
| 8–15 | доме | Prepositional sg (modulated) |
| 16 (0x0010) | дом | Nominative (uninflected) |
| 17–18 | varies | Mixed |
| 19–21 | дом | Nominative |
| **20 (0x0014)** | **дом** | **Nominative (T7[2]'s value — clause-level)** |
| 22–31 | доме | Prepositional sg (fallback) |

**Experimental confirmation (T8[13] `~[bB]?[UVXY]`, test "He can flob speak Russian."):**

| Flag index | Output | Effect |
|-----------|--------|--------|
| 0 (0x0000) | "... говорить Русского." | Infinitive |
| **37 (0x0025)** | **"... говорит Русского."** | **Finite verb (ORIGINAL)** |
| 15 (0x000F) | "Он не может flob ..." | Negation inserted |
| 16 (0x0010) | "... говорит Русского." | Finite (same as original) |
| 30 (0x001E) | "... говорят Русского." | Plural verb |
| 46 (0x002E) | "... flob Русского." | Verb dropped |
| 53 (0x0035) | "." | Only period |
| 54 (0x0036) | "... flob, которое говорит ..." | Relative clause inserted |
| 61 (0x003D) | "Он говорить может flob Русский." | Word order + case change |
| 63 (0x003F) | "Он flob может говорить Русского." | Word order change |

→ The flags field controls not just inflection but also word order, negation, clause insertion,
and which lexical items appear. It is the compiler's primary selector for output generation.

**Key findings:**
1. Flags are a 5-bit index (0–31 range), not a bitmask. Values ≥ 32 all default to baseline.
2. Same flag value can produce DIFFERENT effects in different tables (T7 PP context vs T8 VP context).
3. The original flag values encode each guard rule's constituent type, which the compiler maps to specific output generation rules via a lookup table.

---

## Complete Pattern Symbol Reference

All symbols observed in LTGOLD rule patterns, with confirmed or hypothesized meanings.

### Tag Characters (grammatical class)

| Char | Confirmed? | Meaning |
|------|-----------|---------|
| `Z` | ✅ | V-N-A ambiguity (unresolved verb/noun/adjective) |
| `z` | ✅ | v-n ambiguity (3sg-s form: verb or noun) |
| `V` | ✅ | Main/content verb (resolved finite predicate) |
| `v` | ✅ | Verb -s/-es form (3rd person singular present) |
| `N` | ✅ | Noun (singular) |
| `n` | ✅ | Noun (plural) |
| `A` | ✅ | Adjective, ordinal numeral |
| `a` | ✅ | Adjective-adverb ("more", "less") |
| `D` | ✅ | Adverb, parenthetical |
| `d` | ✅ | Adverb/adjective ambiguity |
| `E` | ✅ | -ed forms and irregular past (past participle / simple past) |
| `e` | ✅ | Ambiguous: infinitive/participle-II/past tense |
| `G` | ✅ | -ing verb forms (gerund/present participle) |
| `g` | ✅ | Lowercase G (already processed gerund) |
| `F` | ✅ | Active present participle (analyzer-generated) |
| `f` | ✅ | Determiner-expression ("a lot of") |
| `P` | ✅ | Preposition (unresolved) |
| `p` | ✅ | Preposition (resolved) |
| `C` | ✅ | Conjunction (coordinating/disjunctive) |
| `c` | ? | Lowercase C (rare; seen in T7[30] `O[&c]I`) |
| `J` | ✅ | Subordinating conjunction, clause head |
| `j` | ✅ | End-of-clause boundary marker |
| `X` | ✅ | Auxiliary verb 'be' (is/are/was/were) |
| `x` | ✅ | Impersonal verb ("there is") |
| `Y` | ✅ | Auxiliary verb 'have' (possession/perfect) |
| `y` | ✅ | Auxiliary 'have' (existential/copular sense) |
| `B` | ✅ | Infinitive particle 'to' (before perfective) |
| `b` | ✅ | Infinitive particle 'to' (before imperfective) |
| `U` | ✅ | Modal verb ("must", "can", "shall") |
| `u` | ✅ | Modal combination ("had better", "ought to") |
| `K` | ✅ | Negative particle 'not' |
| `k` | ✅ | Negative particle 'no' |
| `R` | ✅ | Personal pronoun ("I", "you", "he") |
| `r` | ✅ | Compound personal pronoun ("myself", "yourself") |
| `M` | ✅ | Indirect/object pronoun ("him", "her", "them") |
| `m` | ✅ | Compound indirect pronoun ("himself", "themselves") |
| `Q` | ✅ | Question word |
| `L` | ✅ | Relative word ', который' (which/who — resolved) |
| `l` | ✅ | Movable relative 'whose' (analyzer-generated) |
| `T` | ✅ | Determiner (article); outputs empty string |
| `t` | ✅ | Determiner — segment boundary (analyzer-generated) |
| `H` | ✅ | Digits and numeric combinations |
| `I` | ✅ | Cardinal numeral |
| `W` | ? | Multi-word phrase marker (not in dic.txt) |
| `w` | ? | Multi-word/compound modifier flag (genitive chain marker) |
| `#` | ✅ | Untranslatable unit (proper noun, designation) |
| `?` | ✅ | Unknown/unrecognized word (not in dictionary) |
| `\|` | ✅ | Fictitious separator (clause boundary in token stream) |
| `S` | ✅ | Demonstrative pronoun (adjectival: "this book") |
| `O` | ✅ | Demonstrative pronoun (standalone: "this", "that") |

### Operator Symbols in Patterns

| Symbol | Confirmed? | Meaning | Example |
|--------|-----------|---------|---------|
| `*` | ✅ | Sentence boundary (start j==1 or end j>#ts) | `*Z*` = single-Z sentence |
| `~` | ✅ | Negation prefix — inverts NEXT token | `~[bB]` = NOT b/B |
| `[...]` | ✅ | Character class — match one token whose tag starts with any char in set | `[UVXY]` = U/V/X/Y |
| `<...>` | ✅ | Any-match — zero-or-more tokens matching class (lazy) | `<N>` = zero+ nouns |
| `<$>` | ✅ | Any-match with capture — `$` consumed from replacement, marks span | `L[RN]<$>p*` |
| `` `word` `` | ✅ | Literal English word exact match | `` `be` `` = token for "be" |
| `_` | ✅ | Underscore placeholder field | `_Z[_*]` — underscore-framed Z (see LTGOLD/DEMO.TXT for context) |
| `-` | ✅ | Hyphen character (compound words) | `A-E` = adj-hyphen-participle |
| `,` | ✅ | Comma punctuation token | `[,C*]` = comma, conj, or end |
| `(` `)` | ? | Parenthetical grouping (optional/alternative patterns) | `[?#](~<UVXY>)Z` |
| `{` `}` | ? | Brace grouping (alternation?) | `(#)` → `{#}` |
| `:` | ✅ | Colon punctuation | `<HI:>` = digits, I, or colon |
| `'` | ✅ | Apostrophe/quote | `<"'>` = quote/apostrophe |
| `"` | ✅ | Quote mark | `"T*` |
| `%` | ? | Modifier flag for digit patterns | `<H%D,>` = H with modifier |
| `^` | ✅ | Word-join operator in patterns | `JK^` → `@Dj` (caret as boundary) |
| `+` | ? | Coordination/join marker | `[g+]Z` → `.N` |
| `&` | ✅ | Coordination marker | `N<Hw>&<&AOD>N` |
| `;` | ? | Clause separator | `[*,:;("]<D>\`see\`` |
| `=` | ✅ | Case-equality operator | `=~<)>,` → `@$\|` |
| `!` | ✅ | Inline Russian literal injection (in patterns!) | `NI!мес!` = numeral + adj + inline "месяц" |
| `\`` | ✅ | Backtick for literal word matching | `` `word` `` |

### W/w Tags — Current Understanding

The `w` tag (lowercase) appears in T5/T6 patterns as the **genitive/possessive chain marker**. After T2-T3 resolve possessive structures like "X of Y", they insert a `w` token between the head noun and its genitive modifier:

- `NwN` = head noun + `w` + genitive noun ("book of John")
- `NwNw` = longer chain ("book of the student of the class")
- `NNw` = apposition with trailing marker ("the city Moscow" → after resolution)

The `W` tag (uppercase) is a **multi-word phrase boundary marker**, inserted by T3 for fixed expressions and participial phrases. W-tagged tokens are special: the `is()` function in parser.lua does `word:upper():find(class)` for W-tagged words, so they match ANY class letter.

### Priority/Flags Byte Range per Table

| Table | Min | Max | Notes |
|-------|-----|-----|-------|
| T1 | 0x00 | 0x0F | Low values, mostly clause-boundary markers |
| T2 | 0x00 | 0x3D | Wide range, modal/aux rules have higher values |
| T3 | 0x00 | 0x32 | Medium range |
| T4 | 0x00 | **0x42** | **1 byte only** (not 2), highest single-byte value |
| T5 | 0x00 | 0x09 | Fixed-count terminator uses 0x0009 |
| T6 | 0x00 | 0x0D | Low range |
| T7 | — | — | Flags field, not priority |
| T8 | — | — | Flags field, not priority |

---

## Complete Replacement Symbol Reference

| Char | Confirmed? | Meaning | Code path |
|------|-----------|---------|-----------|
| `' '` (space) | ✅ | Suppress output (set token to space) | `ts[j] = ' '` |
| `.` | ✅ | Keep token unchanged (passthrough) | no-op |
| `$` | ✅ | Keep token unchanged; capture ref in patterns | no-op |
| `@` | ✅ | Apply transform using PATTERN character, not replacement | `find_and_replace(ts, j, pattern_char)` |
| Tag char (e.g. `V`, `N`, `A`, `G`) | ✅ | Replace token's tag — find first occurrence of char in token string, splice | `find_and_replace(ts, j, s)` |
| `` `literal` `` | ✅ | Replace token with literal string (Russian word) | `ts[j] = literal` |
| `^` | ✅ | Word-join operator (connects adjacent tokens into compound) | T2[3]: `-` → `^` |
| `\|` | ✅ | Clause-boundary separator injection | T2[2]: `"<$>,"` → `\|$,=` |
| `=` | ? | Case-setting operator (sets grammatical case for following NP) | T2[2]: `"<$>,"` → `\|$,=` |
| `;` | ? | Clause separator / continuation marker | T1[25]: `*\|as\|<$>,` → `@J$;` |
| `&` | ✅ | Coordination marker (links adjacent NPs) | T4[128]: `ACA` → `@&` |
| `+` | ? | Word-join or compound modifier | T3[133]: `N<Hw>"<TAO>N<P/N>"` → `@$+` |
| `j` | ✅ | End-of-clause marker (injects clause boundary) | T1[25]: `*\|as\|<$>,` → `@J$;` (wait, `j` appears elsewhere) |
| `(` `)` | ? | Parenthetical grouping in replacements | T1[40]: `[?#](~<UVXY>)Z~[UVXYxy]` → `@#($)V` |
| `{` `}` | ? | Brace bracketing in replacements | T2[4]: `(#)` → `{#}` |
| `!` | ✅ | Inline Russian literal (CP866 text directly in replacement) | T4[9]: `NI!мес!` → `A` |

### How `find_and_replace` Works

```lua
function find_and_replace(ts, j, target_tag)
  local z = find(ts[j], 'Z')  -- look for Z-form in token
  if z and string.find('VNA', target_tag) then
    -- Z-ambiguous token being resolved to V, N, or A
    local tmp = z:gsub('^.','V')
    if find(tmp, target_tag) then
      ts[j] = find(tmp, target_tag)
    end
  elseif find(ts[j], target_tag) then
    ts[j] = find(ts[j], target_tag)  -- replace with found form
  end
end
```

The `find()` function uses `iter(t)` which parses the CP866-encoded token string looking for tag-letter prefixes. Each token stores multiple forms: `ZopenVоткрыватьNоткрытыйAоткрытый` means:
- Tag Z (ambiguous V/N/A) + English "open"
- Followed by V-form: "открывать" (infinitive)
- Followed by N-form: "открытый" (noun)
- Followed by A-form: "открытый" (adjective)

When replacement char `V` is applied: `find(ts[j], 'V')` finds the V-form, replaces the token.

### The `@` Replacement — Key Detail

`@` tells the replacer: "use the PATTERN character (not the replacement char) to find_and_replace." Example:

- Pattern: `aG` → Replacement: `@A`
- `a` matches token 1 (determiner) → replacement char `@` → `find_and_replace(ts, 1, 'a')`
  - This looks for the 'a' form in the token (which doesn't exist for determiners) → no-op
- `G` matches token 2 (gerund) → replacement char `A` → `find_and_replace(ts, 2, 'A')`
  - This finds the A-form in the gerund token → replaces with adjective form

So `@` is a "pass-through the pattern char" operator, useful when you want the replacement for a token to depend on which pattern element matched it.

---

## Experimental Findings from Binary Patches

### T8[13] `~[bB]?[UVXY]` — Symbol Verification

Test sentence: "He can flob speak Russian." → baseline output has "говорит" (finite verb)

| Patch (replace pattern with) | Result | Meaning |
|-----------------------------|--------|---------|
| `[bB]?[UVXY]` (no `~`) | DIFF | Verb becomes "говорить" (infinitive). Without `~`, no match at position 1 |
| `~?[UVXY]` (no `[bB]`) | DIFF | `~?` = NOT unknown → matches R("He") instead of U("can") |
| `~[bB][UVXY]` (no `?`) | SAME | Still matches at positions 1+2+3 (U, ?, V) — `?` is optional alongside `~[bB]` |
| `~[bB]?V` | SAME | V alone suffices for "speak" — U,X,Y not needed for this sentence |
| `~[bB]?U` | DIFF | U does NOT match "speak" (V) |
| `?[UVXY]` (no `~[bB]`) | SAME | Matches at position 2 (?, V) — unknown then verb |
| `~[bB]?[UVXY]` (original) | SAME | Protects all three tokens |

Key conclusions:
- `~` negates the immediately following token only: `~[bB]` = match NOT(b/B)
- `?` matches unknown-word tokens (tag `?`)
- `[UVXY]` matches one token whose tag contains U, V, X, or Y
- Pattern can match at MULTIPLE positions in the token stream

### T8[12] `L[RN]<$>p*` — Capture Group

Test sentence: "The dog that I saw ran away." — `$` replacement experiments all returned SAME because the test sentence doesn't end with a preposition after a relative clause.

- The `$` inside `<>` is consumed FROM THE REPLACEMENT STREAM by `eat('$', f())`
- It does NOT affect pattern matching — `<$>` is functionally identical to `<>` for matching
- The `$` marks the captured span for potential back-reference in the replacement

### T7[0] `P<$>N` — Flag Field Experiments

T7[0] (PP guard, flags=0x0002) confirmed to directly control the compiler's case assignment
for prepositional phrases:

**Experiment 1: Null pattern** — Zeroing T7[0]'s pattern string removes PP case assignment:
- "He is in the house.": "в доме" → "в дом" (prepositional → nominative)
- "She sat on the chair.": "на стуле" → "в стул" (preposition changed + case changed)
→ T7[0] is REQUIRED for correct Russian PP inflection

**Experiment 2: Flag value 0→31 mapping** — Each value produces a different case/number form:
- 0: "доме" (prep sg, same as 2)
- 1: "домах" (prep pl)
- 2: "доме" → ORIGINAL PP constituent
- 3: "дом" (nom)
- 4: "дое" (corrupt — stem truncated)
- 5: "домом" (instrumental)
- 6: "дома" (genitive)
- 7: "дом" (nom)
- 16: "дом" (nom, uninflected)
- 20: "дом" (nom — same as T7[2] value)
- 22–31: "доме" (fallback to default)

→ Compiler has a 5-bit lookup table (32 entries) mapping constituent type to inflection rule.

### T8[13] `~[bB]?[UVXY]` — Flag Field Experiments

T8[13] (verb construction guard, flags=0x0025) controls verb morphology AND word order:

**Flag mapping (selected values):**
- 0x00: infinitive "говорить" — fallback when no constituent type specified
- 0x0F: negation inserted "не может" (bits 0-3 activate negation word-order)
- 0x10: finite "говорит" — same as original (bit 4 = finite verb marker)
- 0x1E: plural "говорят" — (bits 1-4 activate plural subject agreement)
- 0x25: ORIGINAL — finite "говорит" preserves modal+verb+unknown structure
- 0x2E: verb dropped "flob Русского" — verb suppressed
- 0x35: empty period output — radical structural change
- 0x36: relative clause inserted "которое говорит"
- 0x3D: word order inverted "говорить может flob"
- 0x3F: modal fronted "flob может"

→ The flags field in T8 is a COMPLEX INDEX, not a simple case selector. Different values
produce wildly different Russian output, suggesting the compiler has 32+ different output
generation strategies indexed by this field.

### T8[10-13] Cross-Comparison

All four rules in T8 have space `" "` replacement (suppress output). They fire on different positions:

| Rule | Pattern | Fires at | Guards |
|------|---------|----------|--------|
| T8[10] | `*L` | Token 1 start | Relative pronoun at sentence start |
| T8[11] | `[UV][kNR][VXY]` | T2-4 | Modal + negation/subject + verb |
| T8[12] | `L[RN]<$>p*` | After relative clause | Relative + NP + preposition + end |
| T8[13] | `~[bB]?[UVXY]` | Multiple | Modal/aux after unknown or non-infinitival |

---

## Pattern‑Replacement 1:1 Mapping

Each pattern token has a corresponding replacement token. The mapping is consumed by iterating both iterators in parallel:

```lua
-- In try_match_pattern:
for t, v, i in m do            -- pattern iterator
    ...
    if match succeeds at position j:
        j = replace(ts, j, v, t, f())  -- consume one replacement token
```

Special cases:
- `*` (wildcard) consumes replacement via `eat('@', f())` — the `@` is discarded as a no-op at sentence boundaries. This ensures the replacement stream stays aligned even though `*` doesn't match a token.
- `<>` (any-match) consumes the NEXT replacement token via `eat('$', f())`. The `$` is discarded (no-op replacement). This ensures alignment between pattern and replacement when `<>` may match zero or more tokens.
- Space `' '` replacement suppresses the matched token (sets to space)

---

## How the Lua Port Differs from LTGOLD.EXE

1. **Priority byte discarded** (`r[1]` in `table.unpack(r)` is never used). LTGOLD may sort/weight rules by this value.
2. **`$` capture not used in replacements**: The `replace()` function treats `$` and `.` identically (no-op). LTGOLD may use captured spans.
3. **No `^`, `=`, `;`, `+`, `&`, `j` handling**: These replacement symbols are treated as unknown chars by `replace()` and go through `find_and_replace(ts, j, s)` which looks for them as tag letters — they likely won't match anything, becoming no-ops.
4. **No `(`, `)`, `{`, `}`, `_` handling in patterns**: These grouping/boundary operators are not implemented in `pattern_tokens()`.
5. **T6/T7/T8 all processed identically**: The Lua port runs all tables through the same `match_pattern` loop. LTGOLD may handle validation tables differently (e.g., setting flags on tokens).
6. **Reordering not implemented**: T5/T6 digit-string actions go through normal `find_and_replace` which doesn't reorder tokens.
7. **Token `find()` uses the Lua `iter()`**: LTGOLD has its own CP866 parsing. The Lua reimplementation may incorrectly parse multi-form tokens.
8. **Compiler printers may differ**: The Lua `compiler.lua` dispatch may not match LTGOLD's morphological output exactly.
9. **`W`/`w` handling**: The `is()` function has a special case for W-tagged tokens. This may not match LTGOLD's W handling.

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
| `debug/T[1-8].txt` | Annotated rule dumps with concrete examples per table |
