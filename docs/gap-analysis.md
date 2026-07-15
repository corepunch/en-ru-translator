# Current Test Status and Gap Analysis

## Test Results

| Suite | Passed | Failed | Total |
|-------|--------|--------|-------|
| ltgold100 | 65 | 35 | 100 |
| ltgold200 | 36 | 164 | 200 |
| **Total** | **101** | **199** | **300** |

The July 2026 grammar pass raised the corpus from 65/300 to 89/300. It added
source-aware preposition government for the decoded `at`/`from`/`about` frames,
dative transfer-verb pronouns, scoped modal infinitives, past-progressive propagation,
numeral NP agreement, and bounded alternative-meaning extraction. The remaining
failures below are broader undecoded frame and constituent-flag coverage; the five
features are no longer wholly absent.

The first T3 infinitive pass also restored B/b morphology controls in the
compiler. This fixes “wants to go,” “began to speak,” and “tried to open”; the
remaining five T3-INF failures originate in the governing verb's lexical/frame
selection or unrelated preposition handling rather than loss of the infinitive.

---

## Failure Categories (by Root Cause)

### 1. Preposition Selection (T7-PP) — ~15 failures

**Pattern:** Wrong preposition for English "at", "from", "to"

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "met at the old station" | "на старой станции" | "в старой станции" | "at" → "на" vs "в" not resolved |
| "looked at the white wall" | "на белую стену" | "в белой стене" | Case assignment wrong |
| "ran from the burning house" | "из горящего дома" | "от горящего дома" | "from" → "из" vs "от" not resolved |
| "came from a distant city" | "из отдаленного города" | "от отдаленного города" | Same issue |
| "handed it to him" | "ему" | "он на него" | Pronoun case (dative) missing |

**Root Cause:** LTPRO.EXE has T7 guard rules that select prepositions based on the governed noun's semantic class. The Lua port doesn't implement this preposition-noun case government.

### 2. Verb Tense/Aspect (T8-VERB, T7-VP) — ~20 failures

**Pattern:** Wrong tense or aspect

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "She ran and jumped" | "побежала" | "бежит" | Past tense not selected |
| "He can speak and write" | "сказать и написать" | "сказать и пишет" | Infinitive vs present |
| "She told him" | "сказала" | "говорила" | Wrong verb form |
| "They gave it to us" | "это нам" | "он на нас" | Pronoun case + verb |
| "She asked him to go" | "чтобы придти" | "идет" | Infinitive construction |

**Root Cause:** LTPRO.EXE resolves verb forms based on auxiliary chains (can+V → infinitive, was+V → past). The Lua port doesn't fully implement these resolutions.

### 3. Plural/Singular Agreement (T7-NP) — ~10 failures

**Pattern:** Wrong number/gender agreement

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "Two large black dogs" | "Две большие" | "Два больших" | Numeral-noun gender agreement |
| "Three big red boxes" | "три больших красных ящика" | "три большого красного ящика" | Numeral-noun case agreement |
| "Five metric tons" | "тонн" (gen. pl.) | "тонна" (nom. sg.) | Genitive plural after numerals |

**Root Cause:** LTPRO.EXE applies numeral-noun agreement rules. The Lua port doesn't implement the full case/number/gender agreement system.

### 4. Pronoun Case Assignment (T8-ESS) — ~8 failures

**Pattern:** Wrong pronoun case

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "She handed it to him" | "ему" (dative) | "он на него" | Dative case not applied |
| "He spoke about it to her" | "о нем на ее" | "о он на нее" | Prepositional + genitive |
| "He knew that it was done" | "он был сделан" | "это был сделан" | Neuter pronoun "it" → "он" |

**Root Case:** LTPRO.EXE assigns pronoun cases based on verb government. The Lua port doesn't implement the full case government system.

### 5. Missing Alternative Translations — ~10 failures

**Pattern:** Missing {1.таблица}, {1.записывать}, etc.

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "He put it on the table" | "стол{1.таблица}" | "столе{1._INF}таблицаAтабличный}" | Alternative format wrong |
| "The long legal agreement" | "соглашение было подписано{1.отмечать}" | "соглашение было подписано" | Alternative missing |

**Root Cause:** LTPRO.EXE outputs alternatives in a specific format. The Lua port doesn't fully implement the multi-meaning output format.

### 6. Clause Boundary Handling (T1-CLAUSE) — ~12 failures

**Pattern:** Wrong conjunction translation or comma placement

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "When the train arrives" | "Когда поезд прибывает" | ", когда поезд прибывает" | Comma placement |
| "As he spoke" | "Поскольку он говорил" | "Как он говорил" | "as" → "Поскольку" vs "Как" |
| "Since he left" | "Поскольку Он остался" | "Поскольку он остался" | Capitalization |

**Root Cause:** LTPRO.EXE has specific rules for clause connectives. The Lua port doesn't fully implement the conjunction translation rules.

### 7. Existential "There" (T1-EXIST) — ~6 failures

**Pattern:** Wrong existential construction

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "There was a problem" | "Была проблема" | "Быть проблема" | Past tense existential |
| "There were no books" | "Были никакие книги" | "Быть книга" | Plural + negation |

**Root Cause:** LTPRO.EXE has specific rules for "there is/are/was/were". The Lua port doesn't fully implement these.

### 8. Negation (T1-NEG) — ~4 failures

**Pattern:** Missing negation particle

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "No large truck passed" | "Никакой большой грузовик не прошел" | "большой грузовик прошел" | "не" missing |

**Root Cause:** LTPRO.EXE adds negation particles. The Lua port doesn't implement the negation insertion rules.

### 9. Relative Clauses (T8-REL) — ~10 failures

**Pattern:** Wrong relative pronoun or verb form

| Input | Expected | Got | Root Cause |
|-------|----------|-----|------------|
| "The book whose cover" | "книга покрытие которой" | "книга который автомобиль" | Wrong relative pronoun |
| "The city in which he lived" | "в котором он жил" | "в котором он дил" | Verb form wrong |
| "The girl whom he loved" | "Девушка кому" | "Девушка Дкто" | Wrong relative pronoun |

**Root Cause:** LTPRO.EXE has specific rules for relative clause formation. The Lua port doesn't fully implement these.

---

## Top Priority Fixes (Ordered by Impact)

### 1. Preposition Case Government (~15 failures)
LTPRO.EXE has a table mapping prepositions to required noun cases:
- "at" → accusative (motion) or prepositional (location)
- "from" → genitive
- "to" → dative (pronouns) or accusative (nouns)

**Implementation:** Add preposition-noun case government rules to the compiler.

### 2. Verb Tense/Aspect Resolution (~20 failures)
LTPRO.EXE resolves verb forms based on auxiliary chains:
- can/must/should + V → infinitive
- was/were + V → past tense
- has/had + E → perfect

**Implementation:** Add auxiliary chain resolution rules to the parser.

### 3. Numeral-Noun Agreement (~10 failures)
LTPRO.EXE applies agreement rules:
- "two" + feminine noun → "Две" (not "Два")
- "three" + noun → genitive plural

**Implementation:** Add numeral agreement rules to the compiler.

### 4. Pronoun Case Government (~8 failures)
LTPRO.EXE assigns pronoun cases based on verb government:
- "give" + pronoun → dative
- "about" + pronoun → prepositional

**Implementation:** Add pronoun case government rules to the compiler.

### 5. Missing Alternative Translations (~10 failures)
LTPRO.EXE outputs alternatives in format: `{N.alternative}`

**Implementation:** Fix multi-meaning output format in compiler.

---

## Estimated Fix Impact

| Fix Category | Failures Fixed | New Total |
|--------------|----------------|-----------|
| Preposition case government | +15 | 80/300 |
| Verb tense/aspect | +20 | 100/300 |
| Numeral agreement | +10 | 110/300 |
| Pronoun case | +8 | 118/300 |
| Alternative translations | +10 | 128/300 |
| Clause boundaries | +12 | 140/300 |
| Existential "there" | +6 | 146/300 |
| Negation | +4 | 150/300 |
| Relative clauses | +10 | 160/300 |

**Projected:** 160/300 passing after all fixes (53%)
