# CONTINUE.md — State & Plan for LTPRO Reverse-Engineering

## Objective

Replicate LTPRO.EXE's translation behavior in Lua to pass 300 regression tests
(ltgold100 + ltgold200). **Current: 116/300 (75/100 + 41/200)**.

## Approach

1. Disassemble LTPRO.EXE with radare2 (`/opt/homebrew/bin/r2`)
2. Annotate morph-engine type handlers in `docs/disassemble/`
3. Replicate the flag-propagation logic in `core/parser.lua`, `core/compiler.lua`

## Key Constants

```
LTPRO.EXE:         LTGOLD/LTPRO.EXE  (207714 bytes, DOS 16-bit)
VSHIFT:            0x3A00   (r2 vaddr + VSHIFT = file offset)
DAT_BASE:          0x26750  (data segment base in file)
Morph engine VA:   0x1df0f  (post-T8 morphology, 21 type handlers)
Type jump table:   CS:0x2318 in overlay 0x1000 (r2 VA 0x12318)

r2 command template:
  cd LTGOLD && r2 -e bin.relocs.apply=false -A -q -c 'pd 200 @ VA' LTPRO.EXE
```

## LTPRO Token Structure (~0x11c bytes)

| Offset | Field | Lua equivalent |
|--------|-------|----------------|
| +0x0c | Primary tag (N,V,E,A,W,…) | `ts[i]:sub(1,1)` |
| +0x72 | Context marker (case/gender) | `ts.context[i]` **✓ wired** |
| +0x76 | Constituent type (0x02=PP, 0x06=NP) | `ts.constituent_type[i]` **✓ wired** |
| +0x77 | Aspect/government flags | `ts.flags[i]` (stored, **not consumed**) |
| +0x7a | Has-sub-constituents flag | Not mapped |

## Morph Engine Type Handlers Disassembled

| Type | VA | Purpose | Status |
|------|-----|---------|--------|
| 10 | 0x15000 | Packed V+P form expansion + flag propagation | Disassembled, **partial Lua** |
| 11 | 0x15e8b | A-tagged W forms (participle detection via +0x66) | Disassembled, **not implemented** |
| 12 | 0x1b1f4 | W-token sub-constituent expansion (noun→wrapper) | Disassembled, **partial Lua** |
| 13 | 0x1d302 | Dynamic W-token creation from 't' tokens | Analyzed, **approximated** |
| 14-17 | 0x18de3+ | Output assembly | **Not yet disassembled** |

## What We've Built

### Parser (`core/parser.lua`)
- `h→E0/E1` conversion: distinguishes imperative past (h) from dictionary past (E1)
- `x1_past_context` / `x1_copula_context` / `y1_perfect_context` flags
- `G→V` conversion in `find_and_replace`
- `expand_phrase_tokens`: propagates `ts.context` (+0x72) and `ts.constituent_type` (+0x76)
- `apply_copular_it_compatibility`: subordinate "it" → R(он), not O(это)
- `apply_capitalization_compatibility`: skip N-tagged phrases

### Compiler (`core/compiler.lua`)
- F printer: Y-switch scan past K/k tokens
- E printer: E0/E1 perfective-switch suppression, intransitive detection stub
- V printer: V= marker (simple past, no switch), V1 aspect preservation
- x printer: short-adjective gender agreement (нужно→нужен)
- A printer: `s.context[i]` fallback, backward subject-noun scan
- N printer: inherently-plural detection (люди→plural), `s.dative_subject[i]` check
- Dative pre-scanner in `compile()`: N/A… + x(нужно) → marks NP for dative
- Verb frames: `object_case` for transitive government (читать, возвращать, устанавливать)

### Tokenizer (`core/utils.lua`)
- Back-reference multi-word matching: `\come` → `en_ru["come"]["from"]`
- W-token splitting: `WVисходитьPРиз` → V + P tokens preserving original tag

### Token stream (`core/token_stream.lua`)
- Fields: `tag`, `context`, `constituent_type`, `flags`, `constituent_flags`
- All wired to LTPRO offsets; `context` and `constituent_type` are consumed

## Test Status by Category

| Category | Before | After | Misses |
|----------|--------|-------|--------|
| T8-NEG | 5/8 | **8/8** | — |
| T7-PP | 8/10 | **10/10** | — |
| T7-NP | 9/10 | **10/10** | — |
| T7-AP | 5/10 | **9/10** | "that old house burned" (жегся) |
| T7-VP | 8/10 | **9/10** | "she asked him to go" (спросила) |
| T8-ESS | 4/10 | **7/10** | 3 remain: participle, pronoun, verb/noun |
| T8-COORD | 6/10 | **8/10** | "went to city", "read book" |
| T8-VERB | 2/10 | 2/10 | 8 complex verb forms |
| T8-REL | 0/10 | 0/10 | 10 relative clauses |
| T8-PASS | 2/2 | 2/2 | — |
| BASELINE | 10/10 | 10/10 | — |

## Remaining Failures & Required LTPRO Types

### 1. T7-AP #1: "That old house burned." → жегся (reflexive)
**Expected:** `Этот старый дом жегся{1.гореть;обжигать}.`
**Got:** `Этот старый дом жёг{1.гореть;обжигать}.`
**Root cause:** E-tagged verb without object should add -ся for intransitive.
**LTPRO:** Type-11 checks arg `+0x66` for E/e/V/G → builds pre-nominal participle.
Our intransitive check was too broad (broke T7-NP). Need more targeted detection.

### 2. T7-VP #1: "She asked him to go." → спросила
**Expected:** `Она спросила его, чтобы придти.`
**Got:** `Она попросила его идти.`
**Root cause:** Dictionary has `E001Впросить` → produces попросить, not спросить.
", чтобы" + "придти" need B+infinitive rule handling.

### 3. T8-ESS #2: "The woman that he loved left." → participle
**Expected:** `Женщина, которую он полюбил оставшийся.`
**Got:** `Женщина, которую он полюбил остался.`
**Root cause:** "left" should be present/past participle (оставшийся), not past verb (остался).
**LTPRO:** Type-11 A-form selection for participial context.

### 4. T8-ESS #5: "He spoke about it to her." → pronoun case
**Expected:** `Он говорил о нем на ее.`
**Got:** `Он говорил об этом на нее.`
**Root cause:** "it" → "этом" vs "нем", "to her" → dative "ей" not "на нее".
**LTPRO:** Type-13 prepositional government chain.

### 5. T8-ESS #6: "The report that he wrote was long." → verb/noun
**Expected:** `Сообщать Что он писал{…} было долго{…}.`
**Got:** `Сообщает что он написал{…} был долго{…}.`
**Root cause:** Z→N resolution fails; copula gender wrong; aspect wrong.
5 differences — too complex for quick fix.

### 6. T8-VERB (8 failures): Complex verb forms
All involve modal+perfect, past-perfect-continuous, or conditional constructions.
**LTPRO:** Type-10 V+P packed expansion handles verb chains.

### 7. T8-COORD (2 failures): Coordinated verbs
"He went to the city and came back." — "на городской" vs "в город"
"She read the book and returned it." — "возвратила" vs "возвращенные"
**LTPRO:** Multiple type chain for coordinated predicate handling.

### 8. T8-REL (10 failures): Relative clauses
"whose cover", "in which", "of whom" patterns — word order, pronoun, participle.
**LTPRO:** Full Type-11/12/13 chain for relative clause formation.

## Next Steps (Priority Order)

1. **Type-11 participle forms** (`morph_type11_a_forms.asm`): Implement +0x66 verbal-tag check.
   When W-sub-form is A-tagged AND source has E/e/V/G, force participle form.
   This targets T7-AP #1, T8-ESS #2, and some T8-REL failures.

2. **Type-13 pronoun government** : Implement +0xc='P' → child +2='K' chain.
   This targets T8-ESS #5 and the dative case generalization.

3. **Type-14/Type-17 output assembly**: Disassemble remaining morph types.
   Understanding the output pipeline may reveal simpler fixes for T8-VERB/T8-COORD.

4. **Type-10 V+P packed expansion**: Full implementation of verb-chain handling.

## Files to Modify

| File | Typical changes |
|------|-----------------|
| `core/compiler.lua` | Printer functions, verb_frames, e context handling |
| `core/parser.lua` | flag variables, find_and_replace, expand_phrase_tokens |
| `core/utils.lua` | tokenizer back-reference, phrase matching |
| `core/paradigms.lua` | Verb/noun/adjective inflection tables |
| `core/token_stream.lua` | Field definitions, metadata propagation |
| `core/rules.lua` | Custom T6 reorder rules |

## Running Tests

```sh
# Full ltgold100 suite (75/100 passing)
lua test/ltgold100_test.lua

# Full ltgold200 suite (41/200 passing)
lua test/ltgold200_test.lua

# Quick diff check after changes
lua test/ltgold100_test.lua 2>&1 | grep -c FAIL

# Debug single sentence
lua -e '
loadfile("init.lua")()
print(engine:translate("That old house burned."))
'
```

## r2 Quick Reference

```sh
# Dump rule tables
cd LTGOLD && python3 r2_tools.py tables T2

# Disassemble morph type handler
r2 -e bin.relocs.apply=false -A -q -c 'pd 200 @ 0x15000' LTPRO.EXE

# Disassemble function at known address
r2 -e bin.relocs.apply=false -A -q -c 'pd 200 @ 0x1d302' LTPRO.EXE

# Known morph type VAs (add 0x10000 base for r2):
# Type 10: 0x15000 (0x5000 + 0x10000)
# Type 11: 0x15e8b (0x5e8b + 0x10000)
# Type 12: 0x1b1f4 (0xb1f4 + 0x10000)
# Type 13: 0x1d302 (0xd302 + 0x10000)
# Type 17: 0x136d8 (0x36d8 + 0x10000)
```

## Git Workflow

```sh
# All changes are on branch: refactor-modular-architecture
git branch

# Commit pattern
git add -A && git commit -m "fix: ..." && git push

# View last 10 commits
git log --oneline -10
```
