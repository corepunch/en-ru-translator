# LTGOLD Reverse Engineering — Knowledge Base & Methodology

## Overview

This document captures everything learned from the session working to make our Lua translator 100% identical to LTPRO.EXE's output. It covers methodology, empirical findings, unresolved questions, and the proposed next steps using radare2/r2ghidra for deeper disassembly.

**Current status (session end):** ltgold100: 38/100, ltgold200: 19/200. Start of session: 14/100, 9/200.

---

## 1. The Empirical Workflow (What We Did)

### Primary Method: Patch-and-Observe

The most productive technique by far:

```bash
# Patch one rule out of a table, run test sentence, observe diff
python3 LTGOLD/patch_rules.py LTPRO.EXE /tmp/patched.exe --table T2 --rule 138
./LTGOLD/run_test.sh "sentence" /tmp/patched.exe
```

**Key insight:** A rule that CRASHES the engine when patched is load-bearing (sentinel or critical index). A rule whose removal changes output fired on that sentence. A rule whose removal produces NO change was never triggered.

This directly answers questions like:
- "Does rule X fire for sentence Y?" → patch X, run Y, compare
- "Which T2 rule handles X+E passive?" → patch all T2 rules one-by-one
- "Why does LTGOLD produce form X but not Y?" → patch the guard rule that enables X

### Secondary Method: DOSBox Reference

```bash
./LTGOLD/run_test.sh "sentence." 2>/dev/null | head -1
# Returns the EXACT CP866→UTF8 decoded LTPRO.EXE output
```

Used to capture all 300 expected outputs (refs100/, refs200/).

### Why Progress Is Slow

The core problem: **every token, every rule, every flag is interconnected**. Fixing passive voice breaks progressive. Fixing case-sensitive matching breaks something else. The bugs compound because:

1. We're approximating a 16-bit DOS binary with no source
2. The flag system (T1-T4 mode flags, T7-T8 constituent flags) is not fully decoded
3. Many rules interact in ways only visible through extensive patching

---

## 2. Architecture Deep Dive

### Rule Table Structure (confirmed via patch_rules.py)

```
T1-T3, T5, T6:  10-byte records
  [pat_off:u16][0x22D5:u16][act_off:u16][pad:u16][flags:u16]

T4:              9-byte records
  [flags:u8][pat_off:u16][0x22D5:u16][act_off:u16][pad:u8]

T7-T8:           8-byte records
  [pat_off:u16][0x22D5:u16][act_off:u16][flags:u16]
```

`0x22D5` is a Borland C++ compiler constant (segment register value). It's NOT rule data — it's a far pointer segment fixup. Pattern and action strings are stored as C-strings in the data segment, accessed via near offset.

### Token Tag System

Tags are single bytes: uppercase = primary forms, lowercase = secondary/derived forms.

| Tag | Meaning |
|-----|---------|
| `T` | Article/determiner (silent) |
| `N`/`n` | Noun singular/plural |
| `A`/`a` | Adjective |
| `V`/`v` | Verb (finite) |
| `E`/`e` | Past participle (E-form) |
| `G`/`g` | Gerund (-ing form) |
| `h` | Historical/irregular past form ← KEY: use imperfective |
| `X` | Copula auxiliary (X003=is, X103=was, X203=will) |
| `Y` | Perfect auxiliary (have/has/had) |
| `U` | Modal verb (U1=past conditional) |
| `R` | Personal pronoun |
| `M` | Indirect pronoun |
| `Z` | Ambiguous verb/noun/adj |
| `I` | Numeral |
| `P`/`p` | Preposition |
| `J`/`j` | Subordinating conjunction / clause marker |
| `L`/`l` | Relative pronoun |
| `D` | Adverb |
| `F` | Perfect passive participle ("written", "built") |
| `B`/`b` | Infinitive particle "to" |
| `K`/`k` | Negation particle |
| `C` | Coordinating conjunction |
| `W` | Multi-word phrase |

**Critical discovery:** In LTGOLD's pattern engine, uppercase 'X' and lowercase 'x' ARE DISTINCT tokens. Similarly for other pairs. Our `tag_matches()` function must be case-sensitive for non-W tokens.

### Token Multi-Form Encoding

A single token can contain multiple forms: `X003бытьUдолженfимеется ли\be`

- `X003` = X-form (copula, code 003), text "быть"
- `U` = U-form (modal), text "должен"  
- `f` = f-form (existential), text "имеется ли"
- `\be` = English lemma separator

The `find()` function in parser.lua iterates these forms. **This is why `X` matches `U` patterns** — when a rule tries to match 'U', it finds the embedded U-form in the X003быть token.

---

## 3. Flags Semantics (Partially Decoded)

### T1-T4 Flags (Mode/Condition Bits)

These are NOT constituent-type flags. They control when rules apply based on clause context. Partially decoded:

| Flags | Observed behavior |
|-------|------------------|
| `0x0B` | Apply in multiple contexts (most common) |
| `0x1A` | Rule 138: X+E→V (never fires in test corpus!) |
| `0x30` | Guard rule: marks X+E passive participle context |
| `0x1F` | T4 IA→A: numeral+adj constituent |
| `0x3F` | Sentence-boundary condition |

**Key finding (patch experiment):** T2 rule 137 `(0x30, "X<KkdD?>E", "")` stores flag `0x30` on the E token when a passive X+E construction is detected. Rule 138 `(0x1A, "X<CKkdD>E", " $V")` NEVER fires in practice for any test sentence (patching it out causes no change). The `0x30` flag on E signals the E printer to use short passive participle form.

### T7-T8 Flags (Constituent Type)

These ARE constituent type flags, stored by guard rules on the head token:

| Flags | Constituent |
|-------|-------------|
| `0x01` | Numeral NP (I<AO>N) |
| `0x02` | PP (P<$>N) |
| `0x03` | VP (U<KD>[VX]) |
| `0x05` | EN (E-N adjectival) |
| `0x06` | NP (N<AOD>N) |
| `0x07` | Compound NP (N<Hw>&N) |
| `0x12` | PP with adjective (P<AOdD>[IH]) |

**Problem:** Later rules overwrite earlier flags. A guard sets `0x30` on E, but then T8's `X<k>A` stores `0x12` on the same position. The flag system only stores the LAST value. This is why flag-based passive detection is unreliable without understanding the full firing sequence.

---

## 4. Key Bugs Fixed This Session

### (A) `<$>` Universal Capture (Parser)
**Problem:** `<$>` in patterns like `"*<dD,>`if`<$>,~C"` should match ANY tokens between anchors. Our `matches()` function only matched tokens starting with `$`. 
**Fix:** `tag_matches(t, v)` returns true if `v == '$'` regardless of token content.
**Impact:** All T1 conditional clause rules (if/when/since/during/as) now fire.

### (B) Tag Case Sensitivity (Parser)
**Problem:** Our pattern matcher checked token forms via `find()` which searches ALL embedded forms. `matches(X103token, 'x')` returned true because X103быть has an embedded `x`-form.
**Fix:** New `tag_matches()` function checks only the LEADING character (case-sensitive for non-W tokens).
**Impact:** Prevented `R<K>x → m` from incorrectly converting subject pronouns to dative in passive constructions.

### (C) h-Tag = Imperfective Past (Parser + Compiler)
**Problem:** "came", "spoke", "went" etc. are h-tagged (irregular past). We converted h→E in normalization, then E printer did perfective switch: "came" → пришел (wrong). LTGOLD outputs приходил (imperfective).
**Fix:** Normalize h→E1 (with '1' flag = "already resolved, skip perfective switch").
**Impact:** T8-COORD correct verb aspect for ~6 tests.

### (D) X203 Future Auxiliary (Compiler)
**Problem:** X203 ("will") was treated as passive construction (X+V = passive). It should set perfective=true and output nothing.
**Fix:** X2xx code → `e.perfective=true; return ""`.
**Impact:** "he will follow" → "последует" ✓

### (E) E Printer: X1xx Passive Detection (Compiler)  
**Problem:** X103 (past copula "was") + E(past participle) should use short passive participle. Flag `0x30` was being overwritten by later T8 rules.
**Fix:** Direct detection: `if prev_token starts with 'X' and code starts with '1'` → passive.
**Impact:** "was signed" → "было подписано" ✓

### (F) E Printer: Adjectival Check Overfired (Compiler)
**Problem:** `adjectival` check fired for N-E-P (subject-verb-preposition) like "cat sat on mat", not just pre-nominal E-N-P.
**Fix:** Only fire when previous token is T/A/O (article/adj/demonstrative), not N/R (subject).
**Impact:** "cat sat on mat" → "посидeла на ковре" ✓ (not passive).

### (G) Passive Forms: -ся Reflexive vs Short Participle (Compiler)
**Problem:** LTGOLD uses TWO passive forms:
- With agent (by X): imperfective reflexive past + -ся → "разбивалось ним"
- Without agent: X103 + short passive participle → "было подписано"
**Fix:** V/E/F printers detect `has_agent` (PТ = CP866 byte 0x92 following) to choose form.

### (H) Y Printer: Perfect Tense (Compiler)
**Problem:** Y(have/has/had) had no printer, output "иметь" as fallback.
**Fix:** `printers.Y` outputs "" (silent) and sets `e.perfective=true`. F printer checks `prev_tag == 'Y'` for perfective active past.
**Impact:** "has written" → "написала" ✓

### (I) Paradigm 60 ASCII 'e' (Paradigms)
**Problem:** LTGOLD outputs ASCII 'e' (0x65) in past tense of -деть verbs (видeл, посидeла) but Cyrillic 'е' in passive participle suffix (видена).
**Fix:** Paradigm 60 position 8 uses `string.char(101)` = ASCII e; position 13 stays Cyrillic.

### (J) -шел Alternation in Past Tense (Paradigms)
**Problem:** пройти paradigm: past suffix "шел" → "прошели" (wrong). Correct: "прошла/прошло/прошли".
**Fix:** When past suffix ends in "шел" and non-masc form → drop the "е" middle byte.

### (K) Irregular Past Verbs (Paradigms)
**Fix:** `irregular_past` table for мочь, жечь, лечь etc.: мог/могла/могло/могли.

### (L) D Printer Double-Prefix (Compiler)
**Problem:** "DDтщательно" (double-D prefix) — D printer stripped only one D, leaving ASCII 'D' in output.
**Fix:** D printer skips all leading ASCII letter bytes before decoding CP866 content, stops at ';'.

### (M) J Printer Comma Preservation (Compiler)
**Problem:** J tokens like "J, что" had the leading comma stripped by `decode(t, true)`.
**Fix:** J printer uses `decode(t:sub(2), false)` to preserve `, что`.

### (M) Source Word Capitalization (Compiler)
**Problem:** Init-capped source words (Russian, Metric, Fish) were not preserving their caps.
**Fix:** Pass `src_caps` directly (both `true` and `"init"`) to `apply_source_caps`.

### (N) IA → A Rule Disabled for Numerals (Rules + Parser)
**Problem:** Rule `IA → A` converted numeral I-tokens to genitive A-form (трёх instead of три). Also `resolve_attributive_forms` pre-converted I before rules.
**Fix:** Rule action changed to `.` (no-op). Skip I-tokens in `resolve_attributive_forms`. Added `printers.I` with 2-4 vs 5+ agreement logic.

### (O) Constituent-Flag Protection in match_pattern (Parser)
**Problem:** Guard rules (like T2[137] `0x30 X<E>→""`) stored flags on tokens. Then action rules (like T2[138] `X<E>→' $V'`) ignored those flags and converted the token anyway.
**Fix:** Before applying an action rule, check if the last matched token has `constituent_flags`. If non-zero → skip the action.

---

## 5. Remaining Failures by Category

### T7-PP (6 failures): Preposition Selection
Cases: "at the station" → "в" vs "на", "from the house" → "от" vs "из", "to him" → pronoun case.
**Root cause:** Preposition selection is controlled by verb valency frames (verb_frames table in compiler.lua) and preposition case assignments in the dictionary. Many frames are missing or incorrect.
**LTGOLD approach:** The dictionary stores P-form case assignments. E.g., "look at" → PПна(acc), "come from" → PРиз(gen).

### T7-NP (6 failures): Numeral Agreement
Cases: "три стула" (genitive singular), "две собаки" (genitive singular with nominative adj).
**Root cause:** The I printer needs proper 2-4 genitive singular vs 5+ genitive plural logic. The plural/singular flag from printers.I doesn't propagate correctly through adj agreement.
**LTGOLD approach:** T7[025] flags=0x01 marks numeral NP. Compiler uses flag to force genitive singular on noun even when n-tagged.

### T7-AP (9 failures): Predicative and Attributive Adjectives
Cases: "is final" → "конечно" (short adj after copula), "moving truck" → adjective form.
**Root cause:** `printers.A` with `e.infinitive=true` path needs better short-form computation. The 4-char stem cut is wrong for some adjectives.

### T8-REL (10 failures): Relative Clauses  
Cases: "whose cover", "in which", "of whom" — special relative pronoun constructions.
**Root cause:** Rules in T3 for "whose" (l-form), "in which" (in-which preposition + L), "of whom" are not producing the spaces LTGOLD uses ("в   котором"). These are multi-word fixed phrases with special spacing.

### T8-VERB (8 failures): Complex Auxiliaries
Cases: "could speak" → "могла бы сказать" ✓, "had been waiting", "may have seen".
**Root cause:** Multi-auxiliary chains (Y+X+E, could have gone) require tracking auxiliary stack through multiple tokens.

### T2-PERF (5 failures): Perfect Tense
Now partially fixed (Y printer). Remaining: "had left before she arrived" needs past perfect ordering.

### T5-GENOF (10 failures): Genitive of-phrase Reordering
"The book of the student" → "Книга студента". T5 is a reorder table (digit actions). Our token stream after T2-T4 is likely wrong, causing T5 position reordering to fail.

### T6-NUM/ORD/MEAS (30+ failures): Numerals and Measurements
"five kilograms of flour" → "пять килограммов муки". Issues with numeral agreement + genitive of measured noun.

### T1-CLAUSE (15 failures): Clause Conjunctions
"When the train arrives" → extra comma at start, wrong word "when" handling.

---

## 6. Proposed Next Steps: r2/r2ghidra Approach

### What We Know About the EXE

```
Format:     MZ (16-bit DOS)
Size:       207,714 bytes (decompressed via UNLZEXE)
Code entry: 0x3a00
Data base:  0x26750 (Borland C++ runtime signature at 0x26754)
Arch:       x86 16-bit real mode
Compiler:   Borland C++ (evidenced by runtime constant 0x22D5, aad patterns)
```

r2 has Ghidra decompiler built in (`pd:g`). The largest function `fcn.0000b0ff` (7502 bytes) is the likely rule engine. The `fcn.0001d214` (5220 bytes) is probably the pattern matcher.

### Targeted Disassembly Plan

**Goal 1: Understand T1-T4 flag bit semantics**

The flags in T1-T4 records control WHEN rules fire. We need to find the code that reads `record.flags` and decides whether to skip the rule.

```bash
# Find where the 10-byte record flags field (offset +8) is read:
# In code, this would be: mov ax, [bx+8] followed by test/and/compare
# Search for: 8b 47 08 (mov ax,[bx+8]) near table iteration loops
r2 -qc 'aaa; /x 8b4708' LTPRO.EXE
```

Once found, decompile that function to see the flag-checking logic:
```bash
r2 -qc 's <addr>; pd:g' LTPRO.EXE > flag_check.c
```

**Goal 2: Understand the pattern matching for 'h' vs 'E' tags**

LTGOLD treats h and E identically in pattern matching (confirmed: patching `R<dD?>E` crashes on "came"). But the output differs (h→imperfective, E→perfective). The distinction must be in the ACTION application, not pattern matching.

Find where token tags are resolved after a match:
```bash
# The action '@' calls a resolve function. Find it:
# Look for switch statement on action character byte after find_and_replace call
r2 -qc 's fcn.0000b0ff; pd:g' LTPRO.EXE | grep -A5 'switch\|case.*0x40'  # '@' = 0x40
```

**Goal 3: Decode the full flag semantics**

The T1-T4 flags encode a "mode" bitmask. LTGOLD maintains a current "sentence mode" (statement/question/relative clause/passive/etc.) and rules only fire when their flags match the current mode.

```bash
# Find the global mode variable by looking for what's ORed with flags:
r2 -qc 's fcn.0000b0ff; pd:g' LTPRO.EXE | grep -A2 'AND\|OR.*bitmask'
```

**Goal 4: Export all functions to a C pseudo-code file**

```bash
# Full decompilation of the rule engine:
r2 -A -qc 'pd:g @ fcn.0000b0ff' LTPRO.EXE > docs/rule_engine_decompiled.c

# Export all functions:
r2 -qc 'aaa; afr @@f' LTPRO.EXE > docs/all_functions.c
```

### r2ghidra Command Reference

```bash
# Full analysis + decompile a function
r2 -A -qc 's <addr>; pd:g' LTPRO.EXE

# Find cross-references to a data address
r2 -qc 'aaa; axt <data_addr>' LTPRO.EXE

# Search for byte sequence in code
r2 -qc 'aaa; /x <hex>' LTPRO.EXE

# Decompile all functions to a file
r2 -A -qc 'aaa; afr @@f' LTPRO.EXE > decompiled.c

# Interactive session
r2 -A LTPRO.EXE
[0x00003a00]> s fcn.0000b0ff
[0x0000b0ff]> pd:g   # decompile with Ghidra
[0x0000b0ff]> pd 100 # disassemble 100 instructions
[0x0000b0ff]> afvd   # show local variables
[0x0000b0ff]> axt    # cross-references to this function
```

### Key Data Addresses to Track

| Address | Content |
|---------|---------|
| `0x26750` | Data section base (Borland C++ start) |
| `0x2745C` | T1 table start (47 × 10 bytes) |
| `0x27E1C` | T2 table start (157 × 10 bytes) |
| `0x29448` | T3 table start (136 × 10 bytes) |
| `0x2ADDB` | T4 table start (178 × 9 bytes) |
| `0x2BFF0` | T5 table start (9 × 10 bytes) |
| `0x2C79A` | T6 table start (47 × 10 bytes) |
| `0x2C542` | T7 table start (35 × 8 bytes) |
| `0x2C9E4` | T8 table start (83 × 8 bytes) |

The string pool (pattern and action C-strings) lives in the data segment relative to the segment base. Pattern offsets are near pointers from segment base.

---

## 7. The Flag Decoding Problem

This is the core remaining challenge. LTGOLD's rule flags have two layers:

**Layer 1 (T7/T8):** Constituent type. We've decoded these (0x01=num NP, 0x02=PP, 0x06=NP, etc.) and our `constituent_flags` mechanism stores them correctly. But they get overwritten.

**Layer 2 (T1-T4):** Mode/condition mask. These we've barely decoded. The key ones:
- `0x1A` on rule 138: fires only in certain clause modes (never in test corpus)
- `0x0B`: fires broadly
- `0x30`: marks passive participle context

**Hypothesis:** LTGOLD maintains a global `sentence_mode` bitmask. Each rule's flags byte is ANDed with the current mode. If result is non-zero (or zero, depending on polarity), the rule fires.

The mode is set by T1 rules (clause type: conditional, relative, etc.) and modified by T2-T4 processing. The compiler then uses the final mode to select output forms.

**To verify:** Find the global mode variable in the decompiled code. Check how it's updated by T1 rules and read by T2-T4 flag checks.

---

## 8. Patching Methodology Reference

### Tools

- `LTGOLD/patch_rules.py` — zeros/disables rule records
- `LTGOLD/run_test.sh` — run a sentence through LTPRO.EXE via DOSBox-X
- `LTGOLD/test100.sh` / `test200.sh` — run batches

### One-liner for quick experiments

```bash
# Disable T2 rule N and test sentence:
python3 LTGOLD/patch_rules.py LTGOLD/LTPRO.EXE /tmp/t.exe --table T2 --rule N 2>/dev/null
cp /tmp/t.exe LTGOLD/TEST.EXE
./LTGOLD/run_test.sh "The sentence." TEST.EXE 2>/dev/null | head -1
```

### What Each Table Does (confirmed empirically)

| Table | Primary role | Safe to patch? |
|-------|-------------|----------------|
| T1 | Clause boundaries (if/when/since), word-order fixes | Yes (all) |
| T2 | Modals, passive, progressive, relative clauses | Most rules yes, some crash |
| T3 | That-clauses, gerunds, infinitives | Most crash (critical) |
| T4 | Idioms, collocations, negation, coordination | Most crash |
| T5 | NP reorder (compact, digit actions) | Yes |
| T6 | NP reorder (extended) | Yes (but SKIP T6 — crashes) |
| T7 | Structural validation guards (no actions) | All yes |
| T8 | Final validation guards (no actions) | All yes |

### T6 Anomaly

T6 has 47 real records at a DIFFERENT offset than originally documented. Earlier tooling miscounted string-pool bytes as rule records, causing out-of-bounds writes. The correct T6 base is `0x2C79A` with 47 records × 10 bytes. **Do not patch whole T6 — use --rule N for individual records.**

---

## 9. The 'j' Clause Marker Semantics

In LTGOLD's output, clauses are separated by commas. Our `j` token represents the boundary.

- `j` is injected by T1 rules like `*<dD,>`if`<$>,~C → @$J$j` (the comma gets replaced by `j`)
- `printers.j` must output `","` (not silence) since it replaced the comma
- The `J` printer must use `decode(t:sub(2), false)` to preserve `, что` style leading punctuation

---

## 10. Dictionary Structure Notes

### BASE.DIC Token Format

```
word*[tag][code][forms...][\lemma]
```

Multi-form tokens: `X003бытьUдолженfимеется ли\be`

### Token Forms Relevant to Compiler

- `V` = present tense verb form
- `E` = past tense form (perfective path)
- `h` = irregular past (imperfective path — NO aspect switch!)
- `F` = perfect passive participle
- `U` = modal form
- `;` = semicolon separates alternative meanings → {N.alt} in output
- `\` = lemma separator (English source word stored after)

### BASE.RUS Entry Format

```
word*[VorN][byte2][byte3][byte4][byte5][aspect_pair...]
```

- `byte2 & 0x02` = perfective flag (1=perf, 0=imperf)
- `byte4 & ~0x80` = paradigm index
- `byte5+` = aspect pair word (CP866-encoded)

---

## 11. Lessons Learned

1. **Patch first, theorize second.** Empirical patching reveals ground truth faster than reading disassembly.

2. **The `0x22D5` constant is a red herring.** It's a Borland segment fixup, not rule data. Searching for it finds the rule records but the bytes immediately surrounding it are also data, not code.

3. **h-tag ≠ E-tag.** Despite identical pattern matching behavior, h-tagged past forms must output imperfective past. The historical name "h" = "historical irregular" is a clue — these are defective verbs where LTGOLD always used the imperfective base.

4. **Flag overwrites are a fundamental problem.** The `constituent_flags` approach fails when T8 rules overwrite T2 flags. Solution: need either (a) a stack of flags per token position, or (b) decode the actual flag semantics so rules know which flags to respect.

5. **Case sensitivity in pattern matching is critical.** X vs x, U vs u, E vs e, N vs n are ALL semantically distinct in LTGOLD's engine. Our original case-insensitive matching caused many subtle bugs.

6. **The `<$>` universal capture is correct.** The `$` in LTGOLD patterns means "any token span" (wildcard capture). Without this fix, all T1 clause boundary rules failed to fire.

7. **Multi-word D tokens.** Some D (adverb) tokens encode entire idiom phrases like "Dво что бы то ни стало". The decoder must preserve spaces but stop at `;` (alternate meaning separator).

---

## 12. R2 Analysis Session — Key Discoveries

### Critical: r2 vaddr ≠ file offset

r2 vaddr + 0x3A00 = file offset (the MZ loader stub is 0x3A00 bytes).
So fcn.0000b0ff → file offset 0xeaff, fcn.0000bde8 → file 0xf7e8.

### Rule Table r2 Addresses (corrected)

```
T1: file=0x2738c, r2=0x2398c
T2: file=0x2756c, r2=0x23b6c
T3: file=0x27b98, r2=0x24198
T4: file=0x2952b, r2=0x25b2b
T5: file=0x2a740, r2=0x26d40
T6: file=0x2a79a, r2=0x26d9a
T7: file=0x2ac92, r2=0x27292
T8: file=0x2b134, r2=0x27734
DAT_BASE r2 = 0x22d50 (file 0x26750)
```

### The Two-Engine Architecture

LTPRO.EXE has TWO separate rule engines in different code segments:

**Segment 0 (CS=0x0000): T1-T8 Syntactic Rewriting Engine**
- Main function: fcn.0000b0ff (file 0xeaff, 7502 bytes) — pattern-byte matcher
- Wrapper: fcn.0000bde8 (file 0xf7e8) — calls b0ff at 0xbf05
- Main translation entry: 0xcd5c (sub sp, 0x66e), initializes globals [0xbcee]=0, [0xbcec]=0
- Global [0xbcec/0xbcee]: current sentence-scan far pointer
- The T1-T8 rules are applied via this engine; flags at record[+8] are NOT bitmask-matched at runtime against a "current_mode" variable. Instead, the engine gates rule firing through TOKEN STRUCTURE FIELDS set by prior rules.
- Token fields used as gates: [token+0x76], [token+0x6d], [token+0x72], [token+0x77], [token+0x66]
- Token structure: ~0x90 bytes per token. Fields at +0xc = POS tag, +0x66 = secondary tag, +0x72 = context byte, +0x77 = flags

**Segment 1 (CS=0x1000): Morphological Output Engine**
- Main function: 0x1df0f — iterates rule records at DS:0x4fec (file 0x2b73c)
- Record format: [pat_near:u16][seg_0x22D5:u16][act=0:u16][type:u16] (8 bytes)
- The `type` field (1-21) dispatches to handlers via jump table at CS:0x2318 (file 0x15d18)
- Rule pointer advances by `add word [bp-8], 8` (at 0x1e6cf) per iteration
- Global [0xc7fa/0xc7fc]: token array far ptr (12 bytes/entry)
- Global [0xc7fe]: token count
- Global [0xc7b1]: current output token index

### Rule Table at file 0x2b73c (DS=0x22D5:0x4fec)

This is AFTER T8 ends at file 0x2b3cc. It's a separate table for the morphological engine.
Records decoded (first 15):

```
type=1  pat='*NP'
type=3  pat='*ILV,<PN#W,>V'
type=10 pat='*N<P>R'
type=9  pat='*<JQ>UR'
type=7  pat='GB'
type=5  pat='VNPC,E'    # E-form passive/participle context
type=4  pat='*NPE'
type=5  pat='|W,E'
type=5  pat='LVN<,>E'
type=5  pat='[CJ]N<P>E'
type=18 pat='*PV'
type=18 pat='*BNV'
type=18 pat='*B<b>WV'
type=20 pat='~[MRCQL,]V~[#ANWSQIHOkbp]'
type=21 pat='~[MRCQL]Vb~[^ANWIHOkJp]'
```

### Type Dispatch Table (all 22 handlers, CS:0x2318, file 0x15d18)

```
type  1: CS:0x868d  — checks token[+0x85], [+0x7a], [+0x7b], [+0x78]
type  2: CS:0xf7b8
type  3: CS:0xd803
type  4: CS:0xc436
type  5: CS:0x261f  — E-form handler (calls lcall at 0x2637 for form selection)
type  6: CS:0x7f80
type  7: CS:0x4e0c  — checks token[+0x76] == 0 or 8, token[+0x6e] bit 4
type  8: CS:0xde75  — token text-position far ptr copy (ordering helper)
type  9: CS:0x41b8
type 10: CS:0x5000
type 11: CS:0x5e8b
type 12: CS:0xb1f4
type 13: CS:0xd302
type 14: CS:0x8de3
type 15: CS:0xb886
type 16: CS:0x03f7
type 17: CS:0x36d8
type 18: CS:0x1fc4  — VP/infinitive/modal context
type 19: CS:0xff26
type 20: CS:0x9ab7  — subject+VP pattern handler
type 21: CS:0x2600
type 22: CS:0xb7ff
```

### What the T1-T4 Flags Actually Do (Current Hypothesis)

The "flags at +8" in T1-T4 10-byte records are NOT compared against a runtime bitmask.
The engine appears to use token fields as gate conditions (set by earlier rules as side effects).
The flags likely serve as RECORD CLASSIFICATION tags used at load time to group rules or control ordering — not at match time.
**Open question**: The flags 0x0B, 0x1A, 0x30 may control which transformation sub-engine handles the action (T2[137] sets 0x30 on the E token as a side effect, not as a gate check).

### Search Commands for Next Session

To find flag-checking in T1-T4:

```bash
# Search for pattern: load rule record word at +8, then test/and/cmp
# In r2 with correct addressing (add 0x3a00 to all file searches):
r2 -qc 's 0xeaff; pd 2000' LTPRO.EXE | grep -A3 'flags\|0x0b\|0x1a\|0x30'
# Look at fcn.0000bc03 (rule record lookup) to understand how +8 is used
r2 -qc 'aaa; s 0xbc03; pd 80' LTPRO.EXE
```
