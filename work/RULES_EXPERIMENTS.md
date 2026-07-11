# RULES_EXPERIMENTS.md — Binary Patching Experiments on LTPRO.EXE

Running log of experimental findings from surgical binary patching of `LTPRO.EXE`.
Each finding updates confirmed reference docs (`docs/rules.md`, `docs/pipeline.md`) once stable.

Tooling: `LTGOLD/explore_patterns.py`, DOSBox-X headless, CP866 decoder.

---

## Methodology

Individual rule strings in `LTPRO.EXE` are replaced with simplified variants (same or
shorter length, null-padded), then the test sentence is run through DOSBox-X headless
and the CP866-decoded output is compared to the unmodified baseline.

Test sentences used:
- `"She can speak Russian."` — baseline output: `"Она может сказать Русского."`
- `"He can flob speak Russian."` — exercises T8[13] `~[bB]?[UVXY]`
- `"The dog that I saw ran away."` — exercises T8[10-11] validation rules
- `"He must not go."` — exercises T8[11] `[UV][kNR][VXY]`
- `"He is in the house."` — exercises T7[0] `P<$>N` (PP inflection)
- `"She sat on the chair."` — exercises T7[0] (preposition selection)
- `"Is it done?"` — exercises T2[16] guard rules

---

## Table Sweep Results

Binary sweep: clear each record (zero its pattern pointer) and observe output on "She can speak Russian."

| Table | Records | Safe to clear | Boundary | Notes |
|-------|---------|---------------|----------|-------|
| T1 | 47 | ALL 47 | none | No rules fire on this sentence |
| T2 | 157 | NONE | T2[156] hangs | Sentinel-lock (see below) |
| T3 | 136 | NONE | T3[135] hangs | Sentinel-lock |
| T4 | 178 | 4 (174–177) | T4[173] hangs | |
| T5 | 9 | 1 (index 8) | T5[7] hangs | Fixed-count termination |
| T7 | 35 | ALL 35 | none (output changes) | |
| T8 | 83 | 70 (13–82) | T8[12] hangs | First 13 records essential |

**Sentinel-lock:** T2/T3 hang when a string is zeroed because the engine terminates
by null-pointer sentinel (`pat_off=0`), not by count. Zeroing the string leaves
`pat_off` non-null → engine sees empty pattern, matches at every position, infinite loop.
Fix: zero `pat_off` itself, not the string it points to.

T1 can be cleared entirely — its rules did not fire on "She can speak Russian." (a simple SVO sentence), confirming T1 handles clause structures absent from SVO.

T7 can be cleared entirely but output changes — its rules fire. Nulling T7[0] (`P<$>N`)
changes "в доме" → "в дом" (prepositional → nominative) and "на стуле" → "в стул"
(preposition + case change). T7 guards directly control compiler PP inflection.

T8 records [0–12] are essential (clearing any causes hang); records [13–82] can be cleared.
The boundary record is T8[12] `L[RN]<$>p*` (flags=0x003F).

---

## T8[10-13] Cross-Rule Comparison

These 4 rules are pure structural guards with (none) action. All are within the essential first-13-record block. They fire on consecutive positions in "The dog that I saw ran away." (output: "Собака, которую Я видeл убегать."):

| Rule | Pattern | Flags | Fires at |
|------|---------|-------|----------|
| T8[10] | `[VXY]N[N#][UVXY]` | 0x0037 | Verb + noun object + aux chain |
| T8[11] | `[UV][kNR][VXY]` | 0x0038 | Modal/aux + (neg/noun/pronoun) + verb |
| T8[12] | `L[RN]<$>p*` | 0x003F | Relative pronoun + NP + preposition (last essential) |
| T8[13] | `~[bB]?[UVXY]` | 0x0025 | Non-B/b token + unknown + modal-verb (first clearable) |

The flags progression 0x0037 → 0x0038 → 0x003F suggests T8[10-12] share a constituent tier.
T8[13]'s lower flag (0x0025) is consistent with it being the first non-essential record.

---

## Pattern Semantics — Confirmed by Experiment

### `$` in `<$>` is consumed from replacement, not part of pattern matching

T8[12] `L[RN]<$>p*`: replacing `<$>` with `<Z>` or `<>` produces SAME output on the test
sentence — the sentence doesn't have a relative clause ending with a preposition, so the
`<>` span content doesn't affect matching. The `$` is read from the replacement stream by
`eat('$', f())`.

### T8[13] `~[bB]?[UVXY]` token-by-token trace

Given "He can flob speak Russian." → token stream: `R(He) U(can) ?(flob) V(speak) N(Russian)`:

1. `~[bB]` → j=2: token "can" has tag `U`. U ∈ {b,B}? No. Negation → **match**
2. `?` → j=3: token "flob" has tag `?`. → **match**
3. `[UVXY]` → j=4: token "speak" has tag `V`. V ∈ {U,V,X,Y}? → **match**

Result: match at position 2, protecting tokens 2-4 (U, ?, V), keeping "speak" finite.

Variant tests:
- `[bB]?[UVXY]` (without `~`) → DIFF: matches nothing → verb becomes infinitive
- `~[bB]?V` → SAME (V matches "speak")
- `~[bB]?U` → DIFF (U doesn't match "speak")
- `~[bB]?[UVXY]` matches twice on "He can flob speak Russian.": at (U, ?, V) and at (R, U, ?)

---

## Flag Patching Experiments

### Test 1 — T7[0] nulled (PP case assignment)

Pattern `P<$>N`, flags=0x0002.

"He is in the house."
- Baseline: "Он - в доме." (prepositional case)
- No T7[0]: "Он - в дом." (nominative — no PP case assignment)

"She sat on the chair."
- Baseline: "Она посидeла на стуле."
- No T7[0]: "Она посидeла в стул." (accusative, prep changed to "в")

→ T7[0] firing is required for correct Russian PP inflection.

### Test 2 — T7[0] flags bit scan ("He is in the house.")

Patching T7[0] flags to each power-of-two bit:

| Flag value | Noun output | Case/Number |
|-----------|-------------|-------------|
| 0x0000 | доме | Prepositional singular |
| 0x0001 | домах | Prepositional plural |
| 0x0002 | доме | Prepositional singular (ORIGINAL) |
| 0x0004 | дое | Corrupt ending |
| 0x0008 | доме | Prepositional singular |
| 0x0010 | дом | Nominative |
| 0x0020 | доме | Prepositional singular |
| 0x0040–0x8000 | доме | All fall back to default |

Full 5-bit index scan (0–31):
- 0, 2, 8–15: "доме" (prepositional sg)
- 1, 18: "домах" (prepositional pl)
- 3, 7, 12, 14, 16, 19–21: "дом" (nominative)
- 4, 17: "дое" (corrupt — stem truncated)
- 5: "домом" (instrumental)
- 6: "дома" (genitive)
- 10: "доа" (corrupt)
- 22–31: "доме" (all fall back to default)

→ Flags field is a **~5-bit constituent-type index** (0–31). Values ≥ 32 produce default behavior.

### Test 3 — T8[13] flags scan ("He can flob speak Russian.")

Original flags=0x0025:

| Flag | Output | Effect |
|------|--------|--------|
| 0x0025 | "Он может flob говорит Русского." | Finite verb (ORIGINAL) |
| 0x0000 | "Он может flob говорить Русского." | Infinitive |
| 0x000F | "Он не может flob говорить Русского." | Negation inserted |
| 0x0010 | "Он может flob говорит Русского." | Finite (same as original) |
| 0x001E | "Он может flob говорят Русского." | Plural verb |
| 0x002E | "Он может flob Русского." | Verb dropped |
| 0x0035 | "." | Only period |
| 0x0036 | "Он может flob, которое говорит Русского." | Relative clause inserted |
| 0x003D | "Он говорить может flob Русский." | Word order + case change |
| 0x003F | "Он flob может говорить Русского." | Word order change |

→ T8 flags control verb finiteness, negation, word order, clause structure, and noun case.

### Test 4 — Cross-table flag swap

T7[0] with T8[13]'s flag (0x0025): "Он - в доме." SAME — a verb-construction flag has
no effect in a PP context; the compiler found no PP inflection rule for that type and fell
through to default prepositional case.

T8[13] with T7[0]'s flag (0x0002): "Он может flob говорить Русского." DIFF (infinitive).
A PP flag doesn't preserve verb finiteness.

→ **Same flag value produces different effects in different tables** because the constituent
type index is interpreted in the context of the matched phrase type (PP vs VP vs clause).

### Test 5 — T2[16] guard flags ("Is it done?")

T2[16] flags `0x0033 → 0x0000`: "Это сделано?" → "это делать?" (passive past → infinitive).
Full 6-bit scan on "Is it done?" produces 63 distinct outputs from 64 possible flag values —
only 0x0033 matches baseline.

→ T2 guard flags use a different, wider encoding than T7 (every bit position matters in T2's context).

### Test 6 — T8[79] high-flag test

T8[79] (pattern `NlRV`, flags=0x0046): patching to 0x0006 changes "книгу" → "книга"
(accusative → nominative). Bits above position 5 in T8 DO participate in constituent typing.

---

## Unresolved Questions

- [ ] What is the exact meaning of `W` tokens (phrases)? Still unknown.
- [ ] What do replacement symbols `=`, `;`, `+`, `&`, `^` do exactly? Unused in current Lua port.
- [ ] What do T5/T6 digit actions mean — are they 1-based position indices into the matched token sequence?
- [ ] T6 is absent from the Lua port — which of its 47 rules overlap with T5/T7, and which are missing functionality?
- [ ] Do flags mean the same thing in every table? Likely yes, but needs T2/T4 cross-confirmation (pick a T2 rule with flags=0x0002 and null its pattern — check if PP case reverts to nominative).
- [ ] T4 uses a 1-byte flags field (0x00–0x42); compiler may zero-extend. T5[8] flags=0x0009 is a table-size encoding, not a constituent type.

## Resolved Questions

- [x] What does `$` capture in replacements? — Consumed from replacement stream by `<>` spans; does NOT affect pattern matching.
- [x] How does `~` negation interact with `any` (`<...>`) tokens? — Sets negation flag; `<...>` with negation matches tokens NOT in the class.
- [x] How are the 8 tables different? — T1–T4 = tag rewrite; T5–T6 = word-order reorder (digit actions); T7–T8 = structural guards (all no-action).
- [x] Why do T2/T3 rule deletions hang the engine? — Engine terminates by null-pointer sentinel. Zeroing the string leaves `pat_off` non-null → empty pattern matches everywhere → infinite loop.
- [x] What do flags values control? — Constituent-type identifier; compiler maps index 0–31 to inflection behaviors.
