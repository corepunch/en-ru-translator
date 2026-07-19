# CONTINUE.md — LTPRO Reverse-Engineering & Grammar Improvements

## Objective

Build a quality English→Russian translator using LTPRO's paradigm tables and rule engine
as a foundation, then improve beyond what the 1990-era DOS translator could do.

**Current: 222/300 (93/100 + 129/200)**, +22 from baseline 107 on ltgold200.

## New Direction (July 2026)

After reaching +22 on ltgold200, we've stopped trying to match LTPRO's sometimes-incorrect
outputs (wrong case agreement, undeclined proper names, broken constructions).
Instead we're building proper Russian grammar rules.

**See `PLAN.md` for the full grammar improvement roadmap.**

## Test Scores

```
ltgold100: 93/100  (7 pre-existing parser failures)
ltgold200: 129/200 (+22 from baseline 107)
Total:     222/300
```

## Recent Fixes (+22 on ltgold200)

| Fix | Impact | File |
|-----|--------|------|
| X003 pro-verb "does" conjugation | +2 | compiler.lua |
| Reflexive double-ся (CP866 stem check) | +1 | compiler.lua |
| Compound subject plural (C conjunction scan) | +1 | compiler.lua |
| V infinitive after infinitive particle | +1 | compiler.lua |
| Name transliteration (LTPRO table 0x32602) | +1 | compiler.lua |
| X1xx embedded verb conjugation | +1 | compiler.lua |
| Dictionary: "loudly" annotation | +1 | BASE.DIC |
| Dictionary: "rebuilt" entry | +1 | BASE.DIC |
| Preposition override: "на" for languages | +1 | compiler.lua |
| Various T1-EXIST, T4-SEE, T4-HYPH fixes | +7 | compiler.lua |

## Transliteration Table

Found at offset 0x32602 in LTPRO.EXE. Maps CP866 Cyrillic (А-Я) to Latin:
A,B,V,G,D,E,J,Z,I,J,K,L,M,N,O,P,R,S,T,U,F,H,C,CH,SH,SC,J,Y,J,E,YA

## Key Files

| File | Purpose |
|------|---------|
| `core/compiler.lua` | Printer functions, case govt, preposition override |
| `core/parser.lua` | Pattern-matching rules (T1-T8) |
| `core/rules.lua` | Rule tables extracted from LTPRO |
| `core/paradigms.lua` | Noun/verb/adjective inflection |
| `core/utils.lua` | Tokenizer, encoding, helpers |
| `data/BASE.DIC` | English→Russian dictionary |
| `data/BASE.RUS` | Russian paradigm data |
| `test/ltgold200_test.lua` | 200 LTPRO regression tests |
| `test/correct_test.lua` | Correct Russian test suite (new) |
| `PLAN.md` | Grammar improvement roadmap |

## Running Tests

```sh
lua test/ltgold100_test.lua        # 93/100
lua test/ltgold200_test.lua        # 129/200
lua test/correct_test.lua          # 0/8 (WIP)
```
