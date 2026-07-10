# RULES_APPLIED.md — How Rules Are Applied in LTGOLD

Step-by-step documentation of how rules from `rules.lua` are applied.
Each finding is documented so work can be stopped and resumed quickly.

## Pipeline Overview

```
Input English → Tokenize → Table 1 → Table 2 → Table 3 → Table 4 → Table 5 → Table 6 → Table 7 → Compile → Russian Output
```

**644 rules total** across 7 tables (hand-counted).

## Table Structure

| Table | Rules | Tuple Shape | Role |
|-------|-------|-------------|------|
| 1 | 47 | `{priority, pattern, replacement}` | Clause-boundary detection, discourse connectives |
| 2 | 157 | `{priority, pattern, replacement}` | Modal auxiliaries, passive "with/by", relative clauses |
| 3 | 136 | `{priority, pattern, replacement}` | "that"-clauses, relative pronoun resolution |
| 4 | 177 | `{priority, pattern, replacement}` | Idiom/collocation lexicalization, tag normalization |
| 5 | 9 | `{priority, pattern, replacement}` | Late cleanup (copula agreement, "is the", "what X") |
| 6 | 35 | `{priority, pattern}` | Structural stabilizers — no rewrite (protect compounds) |
| 7 | 83 | `{priority, pattern}` | Final structural validation — no rewrite |

**Key insight:** Tables 6 and 7 have **no replacement field**. They are "recognize-and-leave-alone" rules that mark patterns as already resolved, preventing downstream rules from mis-firing.

## Step 1: Tokenization

**File:** `utils.lua:47-71`

Input: `"You are standing in an open field west of a white house, with a boarded front door."`

Output tokens (each is a string with grammatical tags + Russian translations):

```
1  R12Выr12у васmВам              R (pronoun)
2  X013-fесть ли\be                X (infinitive marker)
3  GстоятьNположение\stand         G (gerund)
4  PВПвb                           P (preposition)
5  T                               T (empty)
6  ZоткрыватьNWAоткрытый           Z (verb)
7  Nобласть                         N (noun)
8  NзападAзападныйDна западе        N (noun)
9  PР                               P (preposition)
10 T                               T (empty)
11 Aбелый                           A (adjective)
12 Nдом                             N (noun)
13 ,                               , (punctuation)
14 PТсJс помощью                   P (preposition)
15 T                               T (empty)
16 #boarded                         # (unknown)
17 WAпереднийNплан/Aпередний        W (phrase)
18 NNдверь;вход                     N (noun)
19 .                               . (punctuation)
```

**Key observations:**
- Each token starts with a grammatical tag (R, X, G, P, T, Z, N, A, W, #)
- Numbers after the tag are paradigm IDs (for inflection)
- Russian translations follow after the codes
- `\` separates different grammatical forms of the same word
- `;` separates synonyms

## Step 2: Rule Application

**File:** `parser.lua:229-242`

Rules are applied in **7 passes** (each pass = one `table.insert(rules, {...})` in `rules.lua`).

**Important:** Tables 6 and 7 have **no replacement field** — they are "recognize-and-leave-alone" rules that mark patterns as already resolved.

### Pattern Syntax — UNDOCUMENTED

The pattern matching syntax (`<>`, `[]`, `*`, `~`, `` ` ``) is **NOT documented** in the official SAR2BI/LTGOLD documentation. The only sources are:
1. The code itself (`parser.lua:125-227`)
2. The extracted rules (`rules.lua`)
3. Our reverse-engineering

This is a proprietary format that was never exposed to end users.

### Priority Values — UNCONFIRMED

The first byte in each rule (e.g., `0x14`, `0x3F`, `0x04`) is **NOT used** in the current Lua implementation (line 238 discards it). These are likely:
- Rule indices/IDs within each table
- Or priority values that control ordering

**Cannot confirm** without running the original LTGOLD/SARMA binary, which requires a TUI environment.

### How Pattern Matching Works

**File:** `parser.lua:125-227`

Each rule has: `{ priority, "PATTERN", "REPLACEMENT" }`

The pattern is tokenized by `pattern_tokens()` into:
- `char` — single letter (Z, N, V, etc.)
- `select` — `[...]` class
- `any` — `<...>` zero-or-more
- `wildcard` — `*` (sentence boundary)
- `literal` — `` `word` `` exact match

### Matching Algorithm

**File:** `parser.lua:195-227`

```lua
match_pattern(ts, pattern, replacement)
  for each position i in token_stream:
    if try_match_pattern(ts, pattern, i, replacement):
      print("Applying pattern")
      apply the replacement
```

`try_match_pattern()` iterates through pattern tokens:
- For `char`: check if token starts with that letter
- For `select`: check if token starts with one of the letters
- For `any`: skip zero or more tokens matching the class
- For `wildcard`: check if at start (j==1) or end (j>#ts)
- For `literal`: check if token matches the English word

### Replacement Logic

**File:** `parser.lua:179-189`

When a match is found, the replacement is applied:

```lua
replace(ts, j, pattern_char, token_type, replacement_char)
  if ' ': set token to space
  if '.' or '$': no-op (keep token unchanged)
  if '@': call find_and_replace(ts, j, pattern_char)
  otherwise: call find_and_replace(ts, j, replacement_char)
```

`find_and_replace()` searches the token's translations for the target tag:
```lua
find_and_replace(ts, j, target_tag)
  -- If token is a verb and target is adjective/noun/verb:
  if token has 'Z' and target in 'VNA':
    transform verb to target form
  -- Otherwise:
    if token has target_tag:
      replace token with that form
```

### Lowercase Tags — "Already Processed" Markers

Uppercase tags have lowercase counterparts (`d, g, j, k, l, n, w, x, y, e, u, v, b, p, a, c, m, q, r, s, t`). These indicate "this token's category has already been resolved/consumed by an earlier rule."

Example from Table 4 (end of pass):
```lua
{ 0x12, "n", "N" },   -- normalize plural noun back to canonical form
{ 0x1B, "g", "G" },   -- normalize gerund back to canonical form
```

This is a standard technique in hand-written cascaded rule systems: casing is used as a cheap "already handled" flag rather than a separate boolean field.

## Step 3: Tag Reference

Source: **dic.txt** (SARMA 2.0 Russian documentation, authoritative tag legend).
Note: `#`, `|`, `*` meanings differ between dictionary context and rule-pattern context
(see notes per row).

### Complete Tag Table

#### Uppercase tags

| Tag | dic.txt meaning | Role in rules / notes |
|-----|-----------------|-----------------------|
| `A` | Adjective, ordinal numeral | Adjective in patterns |
| `B` | Infinitive particle 'to' (with perfective verb) | Pairs with `` `be` `` → "to be"; NOT the copula itself — `X` is the copula |
| `C` | Coordinating or disjunctive conjunction ("and", "but", "or") | Clause-joining slot |
| `D` | Adverb, parenthetical word/phrase | Adverb |
| `E` | -ed verb forms and their irregular variants | Past participle / simple past |
| `F` | Active present participle — **generated by analyzer** | Generated, not dictionary-sourced; maps to `passive()` printer in compiler.lua (possible mismatch) |
| `G` | -ing verb forms | Gerund / present participle |
| `H` | Any digits and their combinations | Numeric token |
| `I` | Cardinal numerals | Numeral |
| `J` | Conjunctions, phrase-boundary separators | Subordinating conjunction / complementizer |
| `K` | Negative particle 'not' | Negation |
| `L` | Relative word meaning ', который' (which/who) | Relative pronoun (resolved) |
| `M` | Indirect pronoun | Object pronoun ("him", "her", "them") |
| `N` | Singular noun | Noun |
| `O` | Demonstrative pronoun | Demonstrative pronoun ("this", "that", "these") |
| `P` | Preposition | Preposition |
| `Q` | Question word | Interrogative word |
| `R` | Personal pronoun | Personal pronoun ("I", "you", "he") |
| `S` | Demonstrative pronoun (second class) | Second class of demonstratives; see `S` vs `O` note below |
| `T` | Determiner (article) | Article / determiner; maps to `separator()` → empty output |
| `U` | Modal verb | Modal auxiliary ("must", "can", "shall") |
| `V` | Main (content) verb | Content verb; finite predicate position |
| `W` | — (not in dic.txt) | Multi-word phrase marker; inferred from tokenizer |
| `X` | Auxiliary verb 'be' | Auxiliary 'be' (is/are/was/were) |
| `Y` | Auxiliary verb 'have' (possession sense) | 'have' as perfect auxiliary |
| `Z` | Ambiguity V-N-A | Unresolved word that could be verb, noun, or adjective |

#### Lowercase tags — "already processed" or derived forms

| Tag | dic.txt meaning | Role in rules |
|-----|-----------------|---------------|
| `a` | Sub-class of adjective-adverbs ("more", "less") | Adjectival-adverb |
| `b` | Infinitive particle 'to' (with imperfective verb) | Lowercase of `B`; "to" + imperfective verb |
| `d` | Adverb/adjective ambiguity | Dual-category token |
| `e` | Coincidence of infinitive / past participle / past tense forms | Ambiguous verb form (could be infinitive, participle II, or simple past) |
| `f` | Determiner-expression (followed by a noun phrase) | Determiner-like expression (e.g. "a lot of") |
| `k` | Negative particle 'no' | "no" (attributive negation), vs `K` = "not" |
| `l` | Movable relative word meaning 'whose' — **generated by analyzer** | Genitive relative pronoun |
| `m` | Compound indirect pronoun | Compound object pronoun ("himself", "themselves") |
| `n` | Plural form of noun | Plural noun |
| `o` | — (not in dic.txt) | Likely lowercase of `O` (demonstrative) |
| `r` | Compound personal pronoun | Compound pronoun ("myself", "yourself") |
| `s` | — (not in dic.txt) | Lowercase of `S` (demonstrative pronoun variant) |
| `t` | Determiner — segment boundary marker — **generated by analyzer** | Boundary-marking determiner |
| `u` | Modal verb combination | Compound modal ("had better", "ought to") |
| `v` | Verb form in -s/-es (3rd person singular present) | 3sg present form |
| `w` | — (not in dic.txt) | Lowercase modifier (inferred: multi-word/compound flag) |
| `x` | Impersonal verb combination ("there is", etc.) | Existential/impersonal construction |
| `y` | Auxiliary verb 'have' (existential/copular sense) | "have" in non-possession sense |
| `z` | Ambiguity v-n | Unresolved word: verb-s-form or noun |

#### Special symbols

| Symbol | dic.txt meaning | In rule patterns | In rule replacements |
|--------|-----------------|-----------------|---------------------|
| `#` | Untranslatable unit (proper noun, designation) | Unknown/foreign word token | Keep as-is |
| `\|` | Fictitious separator | Clause boundary marker in token stream | Insert separator |
| `*` | Dictionary separator | **Sentence boundary** (start/end of token stream) — `N*` = noun at end of sentence, `*N*` = sentence of one noun | N/A |
| `?` | — (not in dic.txt) | Unknown/unrecognized word (not in dictionary) | — |
| `-` | — | Hyphen in compound words | — |
| `'` | — | Apostrophe / possessive marker | — |
| `"` | — | Quote mark | — |
| `:` | — | Colon punctuation | — |
| `,` | — | Comma punctuation | — |
| `(` `)` | — | Parenthesis (grouping in patterns) | — |
| `{` `}` | — | Brace grouping | — |
| `^` | — | Unknown — word-join or boundary marker | — |
| `=` | — | Unknown — case-setting operator? | — |
| `;` | — | Unknown — clause separator? | — |
| `&` | — | Unknown — coordination marker? | — |
| `+` | — | Unknown | — |
| `%` | — | Rare; appears in `<H%D,>Z` | — |
| `!` | — | Rare; appears in `"NI!мес!"` — inline Russian literal? | — |
| `_` | — | Token boundary; `_Z[_*]` | — |
| `@` | — | N/A in patterns | Apply grammatical transform to current token |
| `$` | — | Capture group in `<$>` — span captured for back-reference | Reference to captured span |
| `` ` `` | — | Literal English word: `` `be` `` | Literal Russian word: `` `быть` `` |
| ` ` | — | N/A | Insert space / suppress output |
| `.` | — | N/A | Keep current token unchanged |

### Key corrections vs. earlier documentation

- **`B` is NOT the copula** — it is the infinitive particle 'to'. The actual auxiliary 'be' is `X`. Rules like `B\`be\`` mean "to be" (infinitive marker + the word "be"). What we called "B = copula" should be re-read as "the `to` particle".
- **`F` = active present participle generated by the analyzer**, not a passive form. The `passive()` printer in compiler.lua may be misnamed or `F` was repurposed by the Lua port.
- **`K` = 'not'** (negation), not "modal marker". `k` = 'no'. These appear in patterns like `K`/`k` exactly as negation carriers.
- **`H` = any digits**, not possessive/genitive. The possessive marker (`'s`) has no dedicated tag — it is likely handled as punctuation `'`.
- **`I` = cardinal numeral**, not "second bare infinitive". Co-occurrence with `X` in rules is because numerals follow infinitives in constructions like "to be one of".
- **`M` = indirect object pronoun** ("him", "her", "them"), not "adverbial modifier". This is the object-case pronoun slot.
- **`O` = demonstrative pronoun** ("this", "that"), not "object-case marker".
- **`D` = adverb / parenthetical**, not "do-support auxiliary". The `d` lowercase = adverb/adjective ambiguity.
- **`Y` = 'have' (possession)**, `y` = 'have' (existential). Both are auxiliary 'have' but in different senses.
- **`Z` = ambiguity V-N-A** — dictionary words that are genuinely ambiguous between verb, noun, and adjective. Rules resolve them by context.

### `Z` vs `V` — Ambiguity Resolution

- `Z` = **unresolved V-N-A ambiguity** from dictionary (could be verb, noun, or adjective)
- `V` = **resolved main verb** — the finite predicate after context determines word class
- `z` = **unresolved v-n ambiguity** (3sg-s form could be noun or verb)

Rules promote `Z` → `V` (verb confirmed), `Z` → `N` (noun confirmed), `Z` → `A` (adjective confirmed).

### `S` vs `O` — Two Demonstrative Classes

Both are demonstrative pronouns per dic.txt. Likely split:
- `S` = demonstrative adjective-pronoun (modifies a noun: "this book")
- `O` = demonstrative standalone pronoun ("this one", "that")

Both dispatch to `adjective()` in the compiler, consistent with demonstrative adjective inflection.

### `B` vs `b` — Infinitive Particle Aspect

- `B` = 'to' before a **perfective** verb ("to arrive", "to finish")
- `b` = 'to' before an **imperfective** verb ("to go", "to be doing")

In rules: `B\`be\`` = "to be" (as infinitive); `bG` = "to be doing" (imperfective gerund construction).

## Step 4: Concrete Rule Traces

### Rule: `Z` → `N` (verb to noun)

Pattern: `Z`
Replacement: `N`

This rule matches any verb token and replaces it with its noun form.

**Before:** Token 6 = `ZоткрыватьNWAоткрытый` (verb "открывать" + noun "открытый")
**After:** Token 6 = `NWAоткрытый` (noun form "открытый")

### Rule: `N<"'#>N` → `A` (noun with modifiers to adjective)

Pattern: `N<"'#>N`
Replacement: `A`

Matches: noun, followed by zero-or-more quotes/numbers, then another noun.
Result: replaces with adjective form.

**Applied twice** to tokens 7 and 8.

### Rule: `X<KkdD'">G` → `$V` (infinitive+gerund to verb)

Pattern: `X<KkdD'">G`
Replacement: `$V`

Matches: infinitive marker, optional modifiers, gerund.
Result: uses captured group ($) and transforms to verb.

## Step 4: Compilation

**File:** `compiler.lua:126-157`

After rules are applied, the compiler processes each token:

```lua
compiler.compile(s)
  for each token w:
    if punctuation: append to previous word
    else:
      func = printers[w:sub(1,1)]  -- dispatch by first letter
      result = func(w, state)
      append result to output
```

### Printer Functions

Each grammatical tag has a printer that handles inflection:

| Tag | Printer | Action |
|-----|---------|--------|
| N | `noun()` | Look up paradigm, inflect for case/number/gender |
| Z/V | `verb()` | Conjugate for tense/person/aspect |
| A/S | `adjective()` | Decline to agree with governed noun |
| P | `preposition()` | Set grammatical case |
| R | `pronoun()` | Set person/number |
| X | `infinitive()` | Mark infinitive form |
| U | `unique()` | Handle special forms ("must", "can") |
| F | `passive()` | Past passive form |
| G | `gerund()` | Present participle form |
| T | `separator()` | Output empty string |

### State Tracking

The compiler maintains state across tokens:

```lua
e = {
  plural = false,      -- current number
  gender = 1,          -- current gender (0=male, 1=female, 2=neutral)
  person = 3,          -- current person (1/2/3)
  form = 1,            -- current grammatical case
  perfective = false,  -- verb aspect
  imperative = false,  -- verb mood
  word = 1             -- word position in sentence
}
```

This allows later tokens to agree with earlier ones (e.g., adjective agrees with noun gender).

## Step 5: Concrete Example

Input: `"You are standing in an open field west of a white house, with a boarded front door."`

### Tokenization

```
1  R    You        (pronoun)
2  X    are        (infinitive marker)
3  G    standing   (gerund)
4  P    in         (preposition)
5  T    [empty]
6  Z    open       (verb)
7  N    field      (noun)
8  N    west       (noun)
9  P    of         (preposition)
10 T    [empty]
11 A    white      (adjective)
12 N    house      (noun)
13 ,    ,
14 P    with       (preposition)
15 T    [empty]
16 #    boarded    (unknown)
17 W    front      (phrase)
18 N    door       (noun)
19 .    .
```

### After Rules

```
1  R    Вы        (you - pronoun)
2  G    стоять    (stand - gerund, X→G transformation)
3  P    в         (in - preposition)
4  T    [empty]
5  N    открытый  (open - Z→N transformation)
6  N    область   (field - noun)
7  N    запад     (west - noun)
8  P    Р         (of - preposition, case set)
9  T    [empty]
10 A    белый     (white - adjective)
11 N    дом       (house - noun)
12 ,    ,
13 P    с помощью (with - preposition)
14 T    [empty]
15 #    boarded   (unknown - kept as-is)
16 W    передний  (front - phrase)
17 N    дверь     (door - noun)
18 .    .
```

### Compilation Output

```
Вы стоите в открытый области запад белого дома, с помощью boarded передний дверью.
```

Translation: "You are standing in an open area west of a white house, with the help of boarded front door."

**Note:** This is a rough translation. The rules are working but there are still issues:
- "boarded" is not translated (unknown word)
- Word order could be improved
- Some grammatical cases may be incorrect

## Key Files Reference

| File | Lines | Role |
|------|-------|------|
| `init.lua` | 114 | Entry point, loads dictionaries, runs pipeline |
| `utils.lua` | 74 | Tokenization, CP866 conversion |
| `load.lua` | 74 | Dictionary parsing |
| `parser.lua` | 272 | Rule application engine |
| `rules.lua` | 669 | Pattern-matching rules (5 passes) |
| `compiler.lua` | 166 | Russian output generation |
| `paradigms.lua` | 423 | Inflection tables |

## Unresolved Questions

- [ ] How do the priority values (0x00-0x3F) affect rule ordering?
- [ ] What does `$` capture exactly in replacements?
- [ ] How are the 5 rule passes different from each other?
- [ ] What is the exact meaning of `W` tokens (phrases)?
- [ ] How does the `~` negation interact with `any` (`<...>`) tokens?

## Testing

To test changes, edit test sentences in `init.lua:81-97` and run:

```sh
lua init.lua
```

To see which rules are applied, the parser prints "Applying ..." for each match.
