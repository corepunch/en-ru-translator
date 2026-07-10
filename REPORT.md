# Flags — Current State Report

## 1. What is documented and confirmed

### Binary layout — fully mapped, no open questions

| Table | Rec size | Flag position | Width | Range observed |
|-------|----------|---------------|-------|----------------|
| T1–T3, T5, T6 | 10 B | bytes 8–9 | uint16 LE | 0x0000–0x003D |
| T4 | 9 B | byte 0 | uint8 | 0x00–0x42 (zero-extended to uint16) |
| T7, T8 | 8 B | bytes 6–7 | uint16 LE | 0x0000–0x0046 |

### Causal proof — flags control compiler output (guard rules only)

**T7 guard rules:** T7[0] flags `0x0002→0x0014`: `доме` (prepositional) → `дом` (nominative).
Full 5-bit scan on PP "He is in the house.": indices 0–31 produce distinct Russian noun forms
(e.g. 0→доме, 1→домах, 2→доме, 3→дом, 4→дое, 5→домом, 6→дома...). Values ≥ 32 all fall
back to default (`доме`). **T7 flags are a 5-bit constituent-type index (0–31).**

**T8 guard rules:** T8[13] flags `0x0025→0x0000`: `говорит` (finite) → `говорить` (infinitive).
Other values produce negation insertion, verb dropping, word-order changes, relative-clause
insertion. **T8 flags control verb morphology AND clause structure.**

**T2 guard rules:** T2[16] flags `0x0033→0x0000`: `"Это сделано?"` → `"это делать?"`
(passive past → infinitive). Full 6-bit scan on "Is it done?" produces 63 distinct outputs
from 64 possible flag values — only 0x0033 (the ORIGINAL) matches baseline. **T2 guard flags
use a different, wider encoding than T7 (every bit position matters).**

**T8 high-flag test:** T8[79] (NlRV) flags `0x0046→0x0006`: `"книгу"` → `"книга"`
(accusative → nominative). **Bits above position 5 in T8 DO participate in constituent
typing — the range is at least 6–7 bits for clause-level rules.**

**Rewrite rules (T1–T4) flags are PURELY for priority/ordering:**
- T4[1] (`X\`need\`` → `` `xпонадобится` ``) flags `0x3C→0x00`: **output unchanged**
- T2[13] (`UR<KdD>[VZ]` → `@@$V`) flags `0x0032→0x0000` on "You must not go.": **output unchanged**
- Multiple other flag values on T2[13] also produced **no change**

→ **Flags have DIFFERENT roles per table type:**
| Table type | Flag role | Source of truth |
|-----------|-----------|-----------------|
| T7       | Constituent-type index (5-bit: 0–31) | T7[0] bit scan |
| T8       | Constituent-type index (6+ bit: 0–70+) | T8[79] 0x0046→0x0006 changes output |
| T2 guards | Broader encoding (not 5-bit index) | T2[16] 6-bit scan: 63/64 values produce unique output |
| T1–T4 rewrite | Priority/ordering only (no effect on output) | T4[1], T2[13] flag nulling → SAME |
| T5         | Terminator encoding on last record | T5[8] flags=0x0009 |
| T4 guards  | Unknown — flags nulling doesn't change PP output | T4[103,105] flags 0x02→0x00 → SAME |

**Cross-table flag consistency is NOT confirmed.** A guard rule with flags=0x0002 in T7
controls PP case. The same flag value (0x0002) appears in T2[36,61,62,63] and T4[103,105].
But nulling T4[103,105] flags to 0x00 does NOT change PP output, and nulling T2[16]
flags from 0x0033 to anything but 0x0033 changes output in a way unique to T2's encoding.
This strongly suggests each table type uses its own flag encoding scheme.

### Known guard-rule flag behaviors (per table)

**T7 flags** — consistent 5-bit index on PP sentences:
| Index | Noun form | Case/number |
|-------|-----------|-------------|
| 0, 2, 8–15, 22–31 | доме | Prepositional singular |
| 1, 18 | домах | Prepositional plural |
| 3, 7, 12, 14, 16, 19–21 | дом | Nominative |
| 4, 17 | дое | Corrupt (stem truncation) |
| 5 | домом | Instrumental |
| 6 | дома | Genitive |

**T8 flags** — wider encoding, multiple behavioral dimensions:
| Flag | Output on "He can flob speak Russian." | Effect |
|------|----------------------------------------|--------|
| 0x0025 | "... говорит Русского." | Finite verb (ORIGINAL) |
| 0x0000 | "... говорить Русского." | Infinitive |
| 0x000F | "Он не может flob..." | Negation inserted |
| 0x001E | "... говорят Русского." | Plural verb |
| 0x002E | "... flob Русского." | Verb dropped |
| 0x0036 | "... flob, которое говорит..." | Relative clause inserted |
| 0x003D | "Он говорить может flob Русский." | Word order + case change |
| 0x003F | "Он flob может говорить Русского." | Word order change |

**T2 guard flags** — complex encoding, every bit matters:
| Flag | Output on "Is it done?" | Effect |
|------|-------------------------|--------|
| 0x0033 | "Это сделано?" | Passive past (ORIGINAL — only SAME value) |
| 0x0000 | "это делать?" | Infinitive |
| 0x0002 | "Это сделало?" | Past neuter singular |
| 0x0010 | "это это делать?" | Pronoun reduplication |
| 0x0020 | "это?" | Verb dropped entirely |
| 0x0034 | "Неужели Сделанное это -?" | Question word inserted |

---

## 2. What is missing or uncertain

### A. The per-table flag encoding scheme is not fully mapped

The 5-bit index model only holds for T7. T8 uses at least 6 bits (0x0046 is index 70).
T2 guard rules appear to use a completely different encoding where every bit combination
produces unique output. It is unknown:

- Whether T8 uses bit-masking (like T7's truncation at index 32) or full-range encoding
- Whether T2 guard rules use the same encoding as T8 or something table-specific
- What the compiler-side lookup table actually looks like — is it one table per table type,
  or one unified table with different bases?

**To confirm:** Run a full 7-bit scan (0–127) on T8[79] and T2[16] to find the truncation
boundary, if any.

### B. T4 guard rule flags — untested beyond two rules

T4[103] and T4[105] both have flags=0x02 (same as T7[0] PP marker). Nulling their flags
to 0x00 produced no output change on "He is in the house." But these rules may not fire
on that test sentence. We need:

- A test sentence that specifically triggers a T4 guard rule (e.g. T4[103] `VP<TAO>N<w>A`)
- Then patch its flags and check for output changes

### C. How do flags interact with the compiler?

We know flags affect compiler output, but the mechanism is opaque:

- Does the engine pass each matched rule's flags to a global state array per table?
- Does the compiler read flags from a fixed memory location (overwritten by each match)?
- Are all flags accumulated (intersection), or is only the last/first match used?

The T2[16] result is particularly puzzling: nulling the pattern (preventing the rule from
matching) gave SAME output, but nulling the flags (keeping the rule matching) gave DIFF.
This could mean the engine reads flag values during scanning regardless of match outcome.

### D. T5[8] flags=0x0009 — special case

T5's last record carries `flags=0x0009` encoding the table count (9), not a constituent
type. T5 uses flags for a completely different purpose (fixed-count termination). The
exact engine mechanism is unclear.

### E. T6 flags — completely untested

T6 has 47 rules with flags ranging 0x0000–0x000D. Many are digit-action rules. No
patching experiment has been done on any T6 rule. Key unknowns:

- Do T6 guard rules (e.g. rule 12, `A-N` with (none) action) participate in constituent
  typing?
- Do T6 digit-action rule flags affect anything?

### F. T5/T6 digit-action semantics — not experimentally confirmed

The interpretation "digit N = output the token at match position N" is consistent with
all documented patterns but no binary patching experiment has directly confirmed it.

### G. Several replacement symbols are undocumented behaviorally

The special-symbol table in RULES_APPLIED.md has many entries marked as hypothesized.
None have been tested via binary patching.

### H. Priority/ordering role of flags in T1–T4

We confirmed that nulling rewrite rule flags doesn't change output. But does this mean
flags are purely for priority? No experiment has tested whether rule ORDERING by flag
value determines match precedence. Hypothesis: within a table, rules with higher flags
fire before lower ones. To test: swap flag values between two rules and check if the
behavior swaps.

---

## 3. Lua port status — what is missing

The entire flag mechanism is **unimplemented** in the Lua port:

| Component | Status |
|-----------|--------|
| `rules.lua` | All rules stored as `{ 0x00, pattern, action }` — every flag is `0x00` |
| `parser.lua` | Does not read or propagate flag values at all |
| `compiler.lua` | Does not consume constituent-type indices from rule matches |
| T6 (47 rules) | Entirely absent |

The compiler instead relies on its own state struct (`e.form`, `e.gender`, `e.plural`,
`e.person`) updated incrementally as tokens are printed. This works for simple SVO
sentences but breaks for structures that depend on guard-rule flags (PP case, verb
finiteness, clause agreement, negation word order).

---

## 4. Priority order for next experiments

1. **T8[79] full bit scan** — run indices 0–127 (or until TIMEOUT) to find the
   truncation boundary for T8's flag encoding

2. **T2[16] full 7-bit scan** — find truncation boundary for T2 guard encoding

3. **T4 guard rule triggering** — find a sentence that actually fires a T4 guard
   rule, then test flag patching

4. **T5/T6 digit-action validation** — null T5[3] (`NwNw→34`) pattern in the binary,
   compare output word order for a sentence with genitive NP

5. **Replacement symbol patching** — test `^` by nulling it in a rule that uses it
   (T2[3]: `-→^`) and observing if hyphenated compounds break
