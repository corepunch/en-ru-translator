# CONTINUE.md — LTPRO Reverse-Engineering & Zork Translation

## Objective

Build a quality English→Russian translator for text adventure games.
**Primary target: Zork I: The Great Underground Empire.**

**Current: 25/57 Zork tests (44%), 129/200 LTPRO tests (+22), 93/100 ltgold100.**

## Zork Translation Status

**What works:**
- Room descriptions (partial)
- Object interactions (take, drop, open)
- Navigation (go direction)
- Compound directions (northeast, southwest, etc.)
- Basic combat messages

**What needs fixing:**
1. Imperative vs infinitive in player commands
2. Missing vocabulary (troll, coffin, lantern, etc.)
3. Compound subject plural agreement
4. Preposition choice (на vs в)
5. Case government rules

**Key vocabulary added:**
- 85 DIC entries for Zork-specific words
- 80 RUS entries for paradigm data

## Recent Session (+22 on ltgold200)

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
