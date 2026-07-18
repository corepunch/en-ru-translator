# CONTINUE.md — State & Plan for LTPRO Reverse-Engineering

## Objective

Replicate LTPRO.EXE's translation behavior in Lua to pass 300 regression tests
(ltgold100 + ltgold200). **Current: 185/300 (94/100 + 91/200)**.

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
| 11 | 0x15e8b | A-tagged W forms (participle detection via +0x66) | Disassembled, **partial Lua** |
| 12 | 0x1b1f4 | W-token sub-constituent expansion (noun→wrapper) | Disassembled, **partial Lua** |
| 13 | 0x1d302 | Dynamic W-token creation from 't' tokens | Analyzed, **approximated** |
| 14-17 | 0x18de3+ | Output assembly | **Not yet disassembled** |

## Test Status by Category

| Category | Before | After | Notes |
|----------|--------|-------|-------|
| T8-NEG | 5/8 | **8/8** | All passing |
| T7-PP | 8/10 | **10/10** | All passing |
| T7-NP | 9/10 | **10/10** | All passing |
| T7-AP | 5/10 | **10/10** | All passing (includes "old house burned") |
| T7-VP | 8/10 | **9/10** | "she asked him to go" (спросила) |
| T8-ESS | 4/10 | **9/10** | "report that he wrote" only |
| T8-COORD | 6/10 | **9/10** | "returned" participle issue |
| T8-VERB | 2/10 | **10/10** | All passing |
| T8-REL | 0/10 | **2/10** | "girl/left", "contract/signed" |
| T8-PASS | 2/2 | **2/2** | All passing |
| BASELINE | 10/10 | **10/10** | All passing |

## What We've Built

### Parser (`core/parser.lua`)
- `h→E0/E1` conversion: distinguishes imperative past (h) from dictionary past (E1)
- `x1_past_context` / `x1_copula_context` / `y1_perfect_context` flags
- `G→V` conversion in `find_and_replace`
- `expand_phrase_tokens`: propagates `ts.context` (+0x72) and `ts.constituent_type` (+0x76)
- `apply_copular_it_compatibility`: subordinate "it" → R(он), not O(это); after P → keep R
- `apply_capitalization_compatibility`: skip N-tagged phrases

### Compiler (`core/compiler.lua`)
- F printer: Y-switch scan past K/k tokens
- E printer: E0/E1 perfective-switch suppression, relative-clause participle detection
  - ct=4 or sentence-final E after L/Q → passive/active participle
  - Reflexive verbs → active past participle (оставшийся lookup table)
  - Non-reflexive verbs → passive participle via RUS paired-aspect paradigm
  - **V1 subject position** → infinitive form (report→Сообщать not Сообщает)
  - **V1 gender propagation** → sets e.gender from RUS for X copula agreement
  - **Coordinated past detection** → look-ahead for C+E to resolve lowercase e to past
  - **X copula plural from digit code** → X11x = plural (Three boxes were → поставлены)
- V printer: V= marker (simple past, no switch), V1 aspect preservation
- x printer: short-adjective gender agreement (нужно→нужен)
- A printer: `s.context[i]` fallback, backward subject-noun scan
- N printer: inherently-plural detection (люди→plural), `s.dative_subject[i]` check
- L printer: full который declension table (6 cases × 4 genders), prep-case detection
- l printer: genitive который (fixed from "чей" → который)
- J printer: capitalize "Что" after V1 infinitive subject
- Verb frames: `object_case` for transitive government

### Paradigms (`core/paradigms.lua`)
- `irregular_past["жить"]` added: жило/жил/жила/жили

### Parser (`core/parser.lua`)
- **T6 reorder rule: `lN → 21`** — swap relative pronoun + genitive noun ("whose cover" → "покрытие которой")

### Tokenizer (`core/utils.lua`)
- Back-reference multi-word matching: `\come` → `en_ru["come"]["from"]`

## Remaining Failures & Root Causes

### T8-REL (4 failures remaining)

**Already fixed (6/10 pass):**
- "girl/left" → оставшийся ✓ (active participle lookup table)
- "contract/signed" → истеченный ✓ (passive_participle with paired paradigm)
- "problem/arose" → возникала ✓ (intransitive relative clause aspect preservation)
- "woman/spoke" → говорил ✓ (E printer subject gender detection)
- "girl/loved" → полюбил ✓ (intransitive relative clause + subject gender)
- "report/sent" → послал ✓ (intransitive relative clause guard correctly skipped)

**Root causes of remaining 6:**

1. **Word order** (book, man): "N l N" vs expected "N N l" — added lN reorder rule but case agreement now wrong (покрытия которого vs покрытие которой). Need to fix case propagation.

2. **House burned**: "жженный" (passive participle) vs "жечь" (infinitive expected). The E printer correctly detects relative clause context but LTGOLD outputs infinitive for intransitive E at sentence end. Also missing "взрослым" from packed token.

3. **Letter/wrote**: "прибытый" (masc nom) vs "прибытую" (fem acc) — passive participle gender/case disagreement. LTGOLD uses feminine accusative form.

4. **Man/car**: "ломаться/названный" vs "сломало/называло" — E tokens not getting past-tense conjugation.

### Remaining single failures
- T7-VP: "she asked him to go" → спросила (dictionary entry issue, E001→попросить paired stem conflict with He would go→попросила)
- T8-COORD: "returned" → возвращенные (passive participle in coordination)

## Key Discovered Behaviors

### Aspect flag convention
```
byte2 & 2 == 0 → imperfective (писать, читать, прибывать, оставаться)
byte2 & 2 == 2 → perfective   (написать, прочитать, прибыть, остаться)
```
Note: AGENTS.md says opposite. Actual behavior: `byte(2)&2 ~= 2` triggers imperfective→perfective switch.

### Parser E→V! conversion loses constituent_type
When the parser converts E→V! via `find_and_replace(ts, j, 'V')`, the new V token gets ct=1
overriding the original ct=48 (relative clause verb). This prevents the Z printer from
detecting relative clause context for aspect preservation.

### Packed tokens with spaces
Tokens like `Eстановиться взрослым` contain space-separated verb+adjective.
`utils.decode` stops at ASCII space, losing the adjective portion.

## Files to Modify

| File | Typical changes |
|------|-----------------|
| `core/compiler.lua` | Printer functions, verb_frames, e context handling, R/M pronoun case |
| `core/parser.lua` | flag variables, find_and_replace, expand_phrase_tokens, V1 subject detection |
| `core/rules.lua` | T6 reorder rules (lN, etc.) |
| `core/utils.lua` | tokenizer back-reference, phrase matching |
| `core/paradigms.lua` | Verb/noun/adjective inflection tables, pronoun paradigm |
| `core/token_stream.lua` | Field definitions, metadata propagation |
| `core/rules.lua` | Custom T6 reorder rules |

## Running Tests

```sh
lua test/ltgold100_test.lua        # 94/100
lua test/ltgold200_test.lua        # 91/200
```

## Current Work State

**Objective:** 1:1 matching of LTGOLD's DEMO.OUT reference output for all 10 DEMO.TXT sentences.

### What was done

**Previous session:**
- W token expansion, G→N fallback, case propagation, X copula, find_form() rewrite.

**This session (T8-NEG/T8-COORD grammar pass):**
- **F printer Y scan past negation** (`compiler.lua`): Changed `is_perfect` check to scan backward past K/k tokens for Y auxiliary (e.g. "has not seen" → Y+K+F). Fixes "She has not seen him." — "увидeла" (past tense) not "увидена" (participle).
- **X1 past-tense propagation via V= marker** (`parser.lua`, `compiler.lua`): Added shared `x1_past_context` flag set when X1 ("did") is consumed by ` ` action. The V action handler now uses V= (simple past, no perfective switch) instead of V! (which triggers switch). Compiler V printer handles V= to set e.past but suppress perfective switch via `e.simple_past`. Fixes "He did not write the report." — "писал" (imperfective past) not "написал" (perfective past).
- **y1 genitive government** (`compiler.lua`): y1 ("нет" = there is no) now sets `e.form = case["Р"]` (genitive) on the governed noun. Fixes "There is no problem here." — "проблемы" (genitive) not "проблема" (nominative).
- **V1 aspect preservation under modals** (`compiler.lua`): Z printer infinitive path now checks `t:match('^V1')` — V1 tokens (dictionary-stored present-tense surface forms like понимать) keep their original imperfective aspect under modals instead of switching to perfective. Fixes "She can read and understand it." — "понимать" not "понять".
- **e-tag tense default** (`compiler.lua`): Lowercase `e` (ambiguous infinitive/past/participle) no longer defaults to past tense; only uppercase `E` (definite past) forces e.past. Fixes "He put it on the table." — "устанавливает" (present) not "установил" (past).
- **E printer verb_frame support** (`compiler.lua`): E printer now sets `e.verb_frame` so preposition case overrides work for e-tagged verbs. Added "устанавливать" frame (accusative with "на"). Fixes "He put it on the table." — "на стол" (accusative) not "на столе" (prepositional).
- **P printer particle absorption** (`compiler.lua`): P tokens with a D (adverb) following a verb and without a following noun are now suppressed (absorbed by the verb). Fixes "A small red ball fell down." — removes extra "вниз по".
- **E printer perfective switch guard** (`compiler.lua`): The E printer's perfective switch now requires `e.past` to be true, preventing unwanted aspect changes for e-tagged verbs.

**This session (ltgold100 regression pass):**
- **Intransitive relative clause aspect preservation** (`compiler.lua`): E verbs in relative clauses without an explicit subject (the relative pronoun IS the subject, e.g. "which arose") keep their original aspect instead of switching to perfective. Detects: L/Q before E with no R/M between them and no clause boundary (X/Y). Fixes "The problem which arose was solved." — "возникала" (imperfective) not "возникла" (perfective).
- **E printer subject gender detection** (`compiler.lua`): The E printer now scans backward past auxiliaries to find the subject noun for past-tense gender agreement, but only when the E is in the main clause (no relative pronoun L/Q/l between subject and verb). Also stops at L/Q (relative clause boundary) and R/M (pronoun subject). Fixes "The leader of the group spoke." — "говорил" (masculine) not "говорила" (feminine). Restores correct gender for "The book whose cover I saw" — "видeл" (masculine).

**This session (92→94/100):**
- **X copula plural from digit code** (`compiler.lua`): X1xx past copula now reads plural from the second digit of the code (X11x=plural "были", X10x=singular). Fixes "Three big red boxes were delivered." — "поставлены" (plural short participle) not "поставлен" (singular).
- **V1 subject position → infinitive** (`compiler.lua`): V1 tokens preceded by article/adjective now output infinitive form and set e.gender from RUS data for copula agreement. Fixes "The report that he wrote was long." — "Сообщать" (infinitive) not "Сообщает" (present 3sg), and "было" (neuter) not "был" (masculine).
- **J printer capitalization** (`compiler.lua`): "Что" capitalized after V1 infinitive subject. Fixes remaining diff in "The report that he wrote" sentence.
- **Coordinated past tense detection** (`compiler.lua`): Lowercase e-tag looks ahead for C conjunction followed by uppercase E (past verb) and propagates past tense. Fixes "She can read and understand it." — both verbs now infinitive under modal. Also recovers "He put it on the table." which was accidentally broken by earlier fix.
- **T6 reorder rule lN→21** (`rules.lua`): Swaps relative pronoun (l) and genitive noun (N) for "whose X" constructions: "покрытие которой" not "которой покрытие".

## r2 Quick Reference

```sh
cd LTGOLD && r2 -e bin.relocs.apply=false -A -q -c 'pd 200 @ 0x15e8b' LTPRO.EXE  # Type-11
cd LTGOLD && r2 -e bin.relocs.apply=false -A -q -c 'pd 200 @ 0x15000' LTPRO.EXE  # Type-10
```
