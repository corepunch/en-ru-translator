# LTGOLD Parity — Agent Instructions

Goal: make our Lua translator output **byte-identical** to LTPRO.EXE for the test corpus.

Current score: **ltgold100: 42/100 · ltgold200: 23/200**  
Target: 100/100 · 200/200

Run tests:
```bash
lua test/ltgold100_test.lua 2>/dev/null | tail -15
lua test/ltgold200_test.lua 2>/dev/null | tail -15
```

All other tests must stay green:
```bash
lua test/parser_test.lua && lua test/translator_test.lua
```

---

## What Has Been Done

### Fixes already in `core/`

| ID | File | What was fixed |
|----|------|----------------|
| A | `parser.lua` | `<$>` universal capture — `$` in `<$>` matches any token span |
| B | `parser.lua` | Tag case-sensitivity — `X`≠`x`, `E`≠`e` in pattern matching |
| C | `compiler.lua` | `h`-tag = imperfective past (not perfective like `E`) |
| D | `compiler.lua` | X203 future auxiliary — silent, marks next verb perfective |
| E | `compiler.lua` | X1xx passive detection — "was signed" → short passive participle |
| F | `compiler.lua` | Adjectival check — only fire for pre-nominal E-N, not subject-verb |
| G | `compiler.lua` | Passive forms — agent present → reflexive (`-ся`), no agent → short participle |
| H | `compiler.lua` | Y printer — "have/has/had" is silent, sets `e.perfective=true` |
| I | `paradigms.lua` | Paradigm 60 ASCII `e` in past tense, Cyrillic `е` in passive participle |
| J | `paradigms.lua` | `-шел` alternation in past tense (прошел/прошла) |
| K | `paradigms.lua` | Irregular past verbs (мочь, жечь, etc.) |
| L | `compiler.lua` | D printer — skip all leading ASCII bytes before CP866 content |
| M | `compiler.lua` | J printer — preserve leading `, что` punctuation |
| N | `parser.lua` + `rules.lua` | `IA→A` rule disabled for numerals |
| O | `parser.lua` | Constituent-flag protection (same-table guards block same-table actions) |
| P | `paradigms.lua` | `word_at()` `=` zero-suffix — LTGOLD uses `=` as empty-suffix placeholder |
| Q | `parser.lua` | Constituent flags cross-table — T3 guard no longer blocks T4 action |
| R | `parser.lua` | `tag_matches()` — `.`/`?`/`!` match `*` inside bracket classes `[,&Jj*]` |
| S | `compiler.lua` | A printer predicative short form — `is final` → `конечно`, `is open` → `открыта` |
| T | `compiler.lua` | X1xx past copula — outputs `был/была/было/были` instead of `будет` |
| U | `compiler.lua` | Reflexive participle adjectives — `движущийся` uses `-ий` paradigm + appends `ся` |

---

## What Remains — Ranked by Impact

### 1. T7-VP: Coordinated Verbs (test100: 4/10 failing — 6 tests)

**Symptom:** "She ran and jumped" → wrong tense for first verb; "He can speak and write" → second verb not in infinitive form.

**Root cause:** T7[33] `flags=0x13 pat='V[,C]<C>V'` and T8[64-69] coordination guard rules need to mark coordinated VPs. When two verbs are coordinated (`V and V`), the second verb should match the aspect/tense of the first. Currently the second `V` is being compiled independently without knowledge of its coordinated role.

**Where to look:**
- `core/rules.lua` around line 440: T8 coordination rules (T8[64]–T8[71])
- `core/compiler.lua`: `printers.V` and `printers.Z` need to propagate context to the next token when a coordination marker is present
- `core/parser.lua`: check if `&` (coordination action) and `C` (conjunction) tokens are properly threading context

**Expected behavior examples:**
```
"She ran and jumped."  → Она побежала и прыгнула.      (both perfective past)
"He can speak and write." → Он может сказать и написать. (both infinitive after modal)
"They may come or go." → Они могут приходить или идти. (both infinitive after modal)
```

---

### 2. T7-PP: Preposition Selection (test100: 6/10 failing — 6 tests)

**Symptom:** "at the station" → `в` instead of `на`; "from the house" → `от` instead of `из`; "to him" → wrong pronoun case.

**Root cause:** Preposition case assignment depends on verb valency frames (`verb_frames` table in `compiler.lua`) and the semantic class of the preposition+noun pair. LTGOLD stores verb-specific preposition rules in the dictionary (e.g., "look at" → `P + accusative + на`).

**Where to look:**
- `core/compiler.lua`: `verb_frames` table (around line 34) — add more verb-preposition mappings
- `core/compiler.lua`: `printers.P` — preposition selection logic
- Check `data/BASE.DIC` entries for the failing verbs (`meet`, `look`, `run from`, `come from`) for their stored preposition forms

**Expected behavior examples:**
```
"at the station" → на станции    (not в станции)
"from the house" → из дома       (not от дома)
"to him"         → ему           (dative pronoun)
```

**Debugging:** `python3 -c "data=open('data/BASE.DIC','rb').read(); [print(l) for l in data.split(b'\n') if b'meet' in l.lower() or b'look' in l.lower()]"` to see what preposition forms the dictionary stores.

---

### 3. T5-GENOF: Genitive NP Reordering (test200: 1/10 — 9 tests)

**Symptom:** "The book of the student" → wrong word order or wrong token type (e.g. Z-verb not N-noun is selected for "book").

**Root cause two parts:**
1. T5 digit-action reordering (e.g. `"NwN" → "23"` moves N2 before N1) is not firing correctly because the token stream after T1-T4 doesn't match T5 patterns.
2. `Z` tokens (ambiguous) are not being resolved to N before T5 runs — "book" is sometimes left as Z instead of N.

**Where to look:**
- `core/parser.lua`: `resolve_attributive_forms()` and `rule_set_preprocessors[6]` (T6 preprocessor) — check if Z→N resolution happens before T5
- `core/rules.lua` T5 rules (around line 590): patterns `NwN`, `NwNN`, etc.
- `core/parser.lua`: `reorder_tokens()` — verify positions and snap logic work for T5
- Trace with: `lua test/ltgold200_test.lua 2>&1 | grep -A2 "FAIL \[T5-GENOF\]"`

**Expected behavior:**
```
"The book of the student" → Книга студента   (N2 goes to genitive, precedes N1)
"The door of the house"   → Дверь дома
```

---

### 4. T8-REL: Relative Clauses (test100: 0/10 — 10 tests)

**Symptom:** "The book whose cover I saw" → wrong pronoun form; "in which" produces 3-space gap `в   котором`; "of whom", "whom" → wrong case.

**Root cause:** Relative pronouns `L`/`l` (который/которого/etc.) need case and gender agreement with their antecedent. The current `printers.L` has basic logic but misses:
1. Genitive relative (`whose` → `книгу которой` — genitive fem)
2. Prepositional relative (`in which` → `в котором` — prepositional)
3. Accusative relative (`whom/which[obj]` → accusative form)

**Where to look:**
- `core/compiler.lua`: `printers.L` (around line 600) — extend case/gender logic
- `core/rules.lua` T3 rules for relative pronouns: `T3[65] '[,N]<w>`whose`<AO>[NZ]'` and surrounding rules
- The 3-space gap `в   котором` in expected output is LTGOLD's way of expressing "preposition + relative pronoun as a fixed phrase" — might require a multi-token literal output

---

### 5. T8-VERB: Complex Auxiliaries (test100: 2/10 — 8 tests)

**Symptom:** "has spoken" → wrong form (passive instead of active perfective); "had been waiting" → present tense; "was writing" → present; "could have gone" → wrong aspect.

**Root cause:** Multi-auxiliary stacks (Y+X+E, Y+V, could+have+E) need state propagation across multiple tokens. Key patterns:
- `Y + V` (has done) → perfective active past
- `Y + X + E` (has been written) → perfective passive
- `X1xx + G` (was writing) → imperfective past (progressive)
- `U + Y + E` (could have gone) → conditional perfect

**Where to look:**
- `core/compiler.lua`: `printers.Y`, `printers.V` — how they interact when stacked
- `core/compiler.lua`: `printers.G` (gerund) — when X1xx + G should be past progressive
- `core/rules.lua` T2 rules around index 100-115: `U<KAdD>X<AdD>[Ee]` patterns

---

### 6. T8-ESS: Essential Clauses (test100: 4/10 — 6 tests)

**Symptom:** "There is a problem" → wrong word order (здесь comes before есть); "He spoke about it to her" → `он` not inflected to `нем`; "it was done" → pronoun case wrong.

**Root cause three parts:**
1. `there is/are` existential: word order inversion. Expected: `Есть проблема здесь` — the `D(here/here)` must come after the noun, not before.
2. Pronoun `it` after preposition `about` → genitive/prepositional `нем`, not nominative `это`.
3. Pronoun `it` as subject in passive clause → `он/она/оно` matching the object's gender, not literal `это`.

**Where to look:**
- `core/parser.lua`: T1[7] `*X\`there\`` → `@f ` rule — check if the `f` (existential marker) token is used correctly
- `core/compiler.lua`: `printers.f` — existential "есть" handler
- `core/compiler.lua`: case propagation for `M` (indirect pronoun) tokens after prepositions
- Pronoun gender agreement: `R` printer — when subject pronoun needs to agree with a noun antecedent

---

### 7. T6-NUM / T6-MEAS: Numerals and Measurements (test200: 0/38 — all failing)

**Symptom:** "five kilograms" → `пяи килограммы` (wrong numeral ending, wrong case); "ten liters" → garbled.

**Root cause:** Numeral agreement in Russian is complex:
- 2-4 after numeral: genitive singular (`два килограмма`)
- 5+ after numeral: genitive plural (`пять килограммов`)
- The I-printer (`printers.I`) currently outputs nominative form only

**Where to look:**
- `core/compiler.lua`: `printers.I` — needs to set `e.form = genitive` on the following noun/adjective
- `core/rules.lua` T6 rules: `NCNNN` etc. — these reorder numeral+noun constituent
- `core/paradigms.lua`: numeral paradigms — the declension for `пять/пяти/пятью` etc.

---

### 8. T3-REL / T3-GER / T3-INF: Subordinate Clauses (test200: 0/21)

**Symptom:** Relative, gerund, and infinitive clause structures are not being correctly assembled.

**Root cause:** The T3 rules that build subordinate clauses (e.g. `N\`that\`<RKdD>[EZ]` → `NL$V`) transform relative clauses, but our implementation drops or misorders constituents.

**Where to look:**
- `core/rules.lua` T3 rules 56–135 — the large relative/gerund block
- `core/parser.lua`: `find_and_replace` with action `'L'` (relative pronoun injection)
- `core/compiler.lua`: `printers.L` — relative pronoun declension

---

### 9. T1-CLAUSE: Clause Conjunctions (test200: 1/16 — 15 tests)

**Symptom:** "When the train arrives, we will board" → leading comma added incorrectly; "as/since/during" handled inconsistently.

**Root cause:** T1 rules inject a `j` clause-marker which our `printers.j` outputs as a comma. The position of that comma relative to the subordinating conjunction word varies.

**Where to look:**
- `core/compiler.lua`: `printers.j` and `printers.J` — comma placement
- `core/rules.lua` T1 rules (first 20 entries) — clause boundary injection patterns
- `core/rules.lua` T3[2]: `,\`if\`<$>,` → `@J$j` — how conditional clause marker is set

---

### 10. T7-AP: Adjectival Participles (test100: 4/10 failing — 6 tests — partially fixed)

**Symptom:** "That old house burned" → reflexive verb form wrong (`жёг` vs `жегся`); "The broken window needs repair" → nominative instead of dative; "The stolen car was found" → wrong passive participle form.

**Root cause remaining:** 
- Reflexive intransitive verbs (burn, melt) need `-ся` suffix always
- E-form (past participle) used as subject → needs case agreement with the predicate object (`needs repair` = dative)
- Short passive participle suffix selection for F-form

**Where to look:**
- `core/compiler.lua`: `printers.E` — `adjectival` context detection and case propagation
- `core/compiler.lua`: `printers.F` — passive participle for F-tagged (perfect passive) tokens
- `data/BASE.DIC` entries for `burn`/`steal`/`write` — check whether they carry reflexive marker

---

## How to Debug Any Failure

### Quick trace

```bash
# Inline translation with debug level 1 (shows rule applications):
lua -e "
package.path = './?.lua;./core/?.lua;' .. package.path
local utils,parser,compiler,load = require'core.utils',require'core.parser',require'core.compiler',require'core.load'
local dbg = require'core.dbg'; dbg.level = 1   -- 0=quiet,1=rules,2=compiler,3=verbose
local file = io.open('data/BASE.DIC','r'); local file2 = io.open('data/BASE.RUS','r')
local en_ru = {}; compiler.base = {}
for line in file:lines() do load.lingua(en_ru, line:gsub('%b{}',''):gsub('%.',''):gsub('%*([A-Z])%1W','*W')) end
for line in file2:lines() do local w,c=line:match('^(.-)%*(.*)$'); if c then compiler.base[utils.decode(w)]=c end end
file:close(); file2:close()
local ts = utils.tokenize('SENTENCE HERE.', en_ru)
parser.collect(en_ru, ts)
print(compiler.compile(ts, {quiet=false}))
"
```

### See token stream after each rule table

```bash
# Change dbg.level = 2 and grep for "After T"
# e.g.: grep "After T\|RESULT\|Applying"
```

### Look up dictionary entries

```bash
python3 -c "
data = open('data/BASE.DIC','rb').read()
for line in data.split(b'\n'):
    d = line.decode('cp866','replace')
    if 'burn' in d.lower(): print(repr(d[:80]))
" | head -10
```

### Check what LTPRO.EXE actually outputs

```bash
cat LTGOLD/refs100/She_ran_and_jumped.txt
cat LTGOLD/refs200/The_book_of_the_student_was_old.txt
```

### Inspect rule tables

```bash
cd LTGOLD
python3 r2_tools.py tables T5    # show all T5 rules with patterns/actions
python3 r2_tools.py tables T8    # show all T8 rules
python3 r2_tools.py token        # token struct offsets from disassembly
```

---

## Key Architecture Facts

### Rule tables (T1–T8)

All rules live in `core/rules.lua`. Format: `{ flags, pattern, action }`.

- **T1** (47): sentence-level rewriting — clause boundaries, `there is`, sentence type
- **T2** (157): modals, passive, progressive, relative clause markers  
- **T3** (136): that-clauses, gerunds, infinitives, relative pronoun forms
- **T4** (178): idioms, collocations, negation, coordination  
- **T5** (9): NP reorder — digit actions like `"23"` swap token positions
- **T6** (56): extended NP reorder — numeral + noun constituent ordering
- **T7** (35): constituent-type guards — store flags, no rewrite actions
- **T8** (83): final constituent guards — store flags, no rewrite actions

Guard rules (T7/T8, and same-table T1-T6 guards) have empty/`.` actions and store `flags` on the matched head token. These flags block incompatible rewrites from the same table.

### Constituent flags

`ts.constituent_flags[i]` = `{ setter_table_idx, flags }`. A rule is skipped when the head token's flag was set by the **same table** or by T7/T8. Flags from an earlier table do not block a later table's action rules.

### Token encoding (CP866)

All Russian text inside tokens is CP866-encoded. `utils.decode(t, true)` decodes to UTF-8. `utils.encode(utf8_str)` goes the other way. The leading byte is the POS tag (ASCII).

### The `e` context object

Passed by reference through `compiler.compile`. Key fields:
- `e.infinitive` — set by X003 copula; used by A/Z/V printers
- `e.perfective` — set by X2xx, Y; causes perfective aspect selection
- `e.past` — set by E/V! printers; enables past tense conjugation
- `e.form` — case (1=nom, 2=gen, 3=dat, 4=acc, 5=instr, 6=prep)
- `e.gender` — 0=neut, 1=masc, 2=fem
- `e.plural` — boolean

**Important:** `e` persists across tokens. A printer that sets `e.form = case["Т"]` affects the next token. After using a context flag, reset it: `e.infinitive = false` etc.

### Reflexive verb marker

CP866 byte `0x92` (`Т` in Koi8) following a P-token signals an instrumental agent ("by X"). Detected in E/V/F printers via: `s[i+1]:sub(1,1) == 'P' and #s[i+1] == 2 and s[i+1]:byte(2) == 0x92`.

---

## r2 Disassembly Tools

```bash
cd LTGOLD
python3 r2_tools.py tables T2          # all T2 patterns/actions
python3 r2_tools.py dispatch           # action character → handler vaddr
python3 r2_tools.py disasm 0xfd03 80   # T3 dispatch function disassembly
python3 r2_tools.py decompile 0xb0ff   # Ghidra decompile of rule engine
```

Key: `r2 vaddr + 0x3A00 = file offset`. Token fields: see `r2_tools.py token`.

---

## Quick Wins (Highest ROI, Simplest Fixes)

1. **T7-VP coordination** — 6 tests. Add `e.infinitive=true` propagation when a `C` (conjunction) token follows a modal. When compiler sees `U...C...V`, the second V should inherit the modal's infinitive context.

2. **`there is/are` word order** — 2 tests (T8-ESS). The `f`-tagged existential "есть" token should appear before the noun. Check T1[7] `*X\`there\`` → `@f ` and how the `f` printer positions output.

3. **T5-GENOF first-token Z→N** — 9 tests. Many "of" constructions fail because the subject is a Z-token (not resolved to N). Add a preprocessor for T5 that resolves Z→N when followed by `w`+N pattern (as T6 preprocessor does for A→adj).

4. **`T7-AP` `-ся` reflexive verbs** — several tests. Add to `printers.E`: when the verb's BASE.RUS entry has the reflexive marker, always append `-ся` to the past form output.

5. **Pronoun `it` as subject** — 3 tests. When `it` appears as the grammatical subject and the predicate has a noun with gender, output the matching gendered pronoun (`он/она/оно`) rather than `это`.
