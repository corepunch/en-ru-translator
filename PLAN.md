# PLAN.md — Building a Better English→Russian Translator

## Philosophy

LTPRO (1990-1993) was a pioneering DOS translator but has serious limitations:
- Incorrect case agreement (genitive instead of accusative, wrong plurals)
- Missing tense sequencing rules (before → future tense in Russian)
- Wrong preposition choices (в instead of на for languages)
- Undeclined proper names (Дом Питер instead of Дом Питера)
- Broken constructions ("not as...as", gerunds, "both...and")
- Many dictionary entries with wrong translations

We've extracted LTPRO's valuable components (paradigm tables, dictionary format,
rule engine), but we're now building **beyond** LTPRO with proper Russian grammar.

## Current Scores

```
ltgold100: 93/100
ltgold200: 128/200  (+21 from baseline 107)
Total:     221/300
```

## Architecture

```
Input text
  → Tokenize (lookup en_ru dictionary, attach grammatical tags)
  → Parse (apply T1-T8 pattern-matching rules from parser.lua)
  → Compile (inflect tokens via compiler.lua + paradigms.lua)
  → Output
```

## Phase 1: Fix Dictionary Mappings (impact: ~5 tests)

### Wrong verbs
| English | LTPRO gives | Should be | Context |
|---------|------------|-----------|---------|
| "run" (running) | останавливаться (to stop) | бежать (to run) | He is running |
| "present" (be present) | представлять (to represent) | присутствовать (be present) | Both were present |
| "either" (each) | также (also) | каждый (each) | Either answer |
| "see" (imperative) | видеть (to see) | смотреть (to look) | See page twelve |

### Missing past tenses
| English | Missing | Should map to |
|---------|---------|---------------|
| "rebuilt" | ✓ already added | разрабатывать |
| "rebuilt" prefix | missing "вновь" | need re- prefix handling |

**Actions:**
- Fix dictionary entries in `data/BASE.DIC`
- Add context-disambiguating entries where needed

## Phase 2: Preposition Overrides (impact: ~3 tests)

Russian preposition choice is context-sensitive. "in" → "в" by default
but changes to "на" for:

| Context | English | Rule | Example |
|---------|---------|------|---------|
| Languages | "in Russian" | на + language | на русском |
| Abstract positions | "in first place" | на + position | на первом месте |
| Physical impact | "hurt on the door" | о/в + accusative | в дверь |

**Implementation:** `core/compiler.lua` P printer context checks
- After P token, if next N is a language name → override preposition to "на"
- After P token, if next N is an ordinal position → override to "на"

## Phase 3: Case Government Rules (impact: ~6 tests)

### Ordinal + Noun
- After ordinals 1-4 (1st, 2nd, 3rd, 4th): accusative singular
- After ordinals 5+: nominative/genitive plural
- "5th chapter" → "5 главу" (accusative, not genitive)
- **File:** `core/compiler.lua` N printer

### Numeral + Noun case
Russian numeral agreement:
- 1: nominative singular
- 2-4: genitive singular (два стола)
- 5-20: genitive plural (пять столов)
- 21: nominative singular again
- 22-24: genitive singular
- etc.

**Implementation:** `core/compiler.lua` I printer case propagation

### Compound subject plural
- "X and Y" → verb should be plural ("говорили" not "говорила")
- ✓ Already implemented in E printer subject scan

## Phase 4: Missing Constructions (impact: ~10 tests)

### "not as ADJ as" → "не так ADJ как"
- Currently broken: produces "не - как высок Поскольку она"
- Need parser rule: detect "not as ADJ as" pattern
- **File:** `core/parser.lua` new rule in T4

### Gerunds "Having done X" → "Сделав X"
- "Having finished the work" → "Закончив работу"
- Currently outputs: "Завершаемый работа" (wrong participle form)
- Need: detect "Having + V-ed" → Russian adverbial participle
- **File:** `core/parser.lua` T3-GER rules

### "both X and Y" with verbs
- "He both reads and writes" → "Он и читает и пишет"
- Currently outputs: "как чтение так и пишет" (converts verb to noun)
- Need: keep both as verbs, not convert to noun
- **File:** `core/parser.lua` T4-BOTH

### "either...or" / "neither...nor"
- Already partially working

## Phase 5: Tense Sequencing (impact: ~3 tests)

### "before" requires future in Russian
- "before she arrived" → "прежде чем она прибудет" (future, not past)
- Rule: J(прежде чем) + past tense → future tense
- **File:** `core/parser.lua` tense sequencing

### "when/if/as" temporal clauses
- Often require conditionals or future
- Already partially working

## Phase 6: Dictionary Expansion

### New words to add
| English | Tags | Russian | File |
|---------|------|---------|------|
| loudly | D | громко;инф)шумный | BASE.DIC ✓ |
| rebuilt | E | разрабатывать;инф)строить | BASE.DIC ✓ |
| orc | N | орк | DUNGEON.DIC |
| goblin | N | гоблин | DUNGEON.DIC |

### Re-prefix handling
- "rebuilt" = re + built → вновь + разработан
- Need prefix-detection in tokenizer/parser
- **File:** `core/parser.lua` or `core/utils.lua`

## Phase 7: Test Suite Modernization

### Stop matching LTPRO errors
Mark tests as "LTPRO_ERROR" where LTPRO output is grammatically wrong:
- "Дом Питер" → correct is "Дом Питера" (genitive)
- "прибыла после before" → correct is "прибудет" (future)
- Case errors in T6-NUM tests

### Add correct Russian reference
- Create `test/reference_correct.txt` with grammatically correct Russian
- Flag tests where our output is better than LTPRO's

## Implementation Plan

| Priority | Task | Tests | Effort |
|----------|------|-------|--------|
| P0 | Preposition overrides (на for languages) | +2 | Small |
| P1 | Dictionary fixes (run, present, either) | +3 | Small |
| P2 | Numeral + Noun case rules | +5 | Medium |
| P3 | "not as...as" parser rule | +3 | Medium |
| P4 | Gerund parser rules | +5 | Large |
| P5 | "both...and" verb coordination | +1 | Medium |
| P6 | Tense sequencing (before→future) | +2 | Medium |
| P7 | Re-prefix handling | +1 | Small |
| P8 | Dictionary expansion (dungeon words) | - | Small |

**Estimated total: +22 tests → 150/200**

## Files Reference

| File | What goes there |
|------|-----------------|
| `core/compiler.lua` | Printer functions, case government, preposition overrides |
| `core/parser.lua` | Pattern-matching rules, construction detection |
| `core/rules.lua` | T1-T8 rule tables extracted from LTPRO |
| `core/paradigms.lua` | Noun/verb/adjective inflection tables |
| `core/utils.lua` | Tokenizer, encoding, string helpers |
| `core/load.lua` | Dictionary file loading |
| `data/BASE.DIC` | Main dictionary (English → Russian) |
| `data/BASE.RUS` | Russian paradigm data (gender, paradigm ID) |
| `test/ltgold200_test.lua` | 200 regression tests (some with LTPRO errors) |
| `test/ltgold100_test.lua` | 100 regression tests |
| `PLAN.md` | This file |
