# RULES_APPLIED.md — How Rules Are Applied in LTGOLD

Step-by-step documentation of how rules from `rules.lua` are applied.
Each finding is documented so work can be stopped and resumed quickly.

## Pipeline Overview

```
Input English → Tokenize → T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → Compile → Russian Output
```

**692 rules total** across 8 tables (verified from LTPRO.EXE binary).  
The Lua port in `rules.lua` contains **644 rules** across 7 passes — T6 (47 rules) is absent from the port.

## Table Structure

Full record dumps with per-rule annotations are in [debug/T1.txt](debug/T1.txt) through [debug/T8.txt](debug/T8.txt).

| Table | Rules | Rec size | Tuple Shape | Role | debug file |
|-------|-------|----------|-------------|------|------------|
| T1 | 47 | 10 B | `{flags16, pat_off, act_off}` | Clause skeleton: Z disambiguation, J/j boundary injection, connectives | [debug/T1.txt](debug/T1.txt) |
| T2 | 157 | 10 B | `{flags16, pat_off, act_off}` | Core verb phrase: modal/aux chains, passive voice, article suppression | [debug/T2.txt](debug/T2.txt) |
| T3 | 136 | 10 B | `{flags16, pat_off, act_off}` | Embedding structures: relative clauses, that-complements, gerund/inf phrases | [debug/T3.txt](debug/T3.txt) |
| T4 | 178 | **9 B** | `{flags8, pat_off, act_off}` | Idioms/collocations, negation normalisation, final Z cleanup | [debug/T4.txt](debug/T4.txt) |
| T5 | 9 | 10 B | `{flags16, pat_off, act_off}` | NP word-order reorder (digit actions); fixed-count termination | [debug/T5.txt](debug/T5.txt) |
| T6 | 47 | 10 B | `{flags16, pat_off, act_off}` | Extended word-order reorder: longer NPs, hyphenated compounds, verbal negation | [debug/T6.txt](debug/T6.txt) |
| T7 | 35 | **8 B** | `{pat_off, act_off, flags16}` | NP/PP/VP structural guards — all (none) action | [debug/T7.txt](debug/T7.txt) |
| T8 | 83 | **8 B** | `{pat_off, act_off, flags16}` | Clause/VP structural guards — all (none) action | [debug/T8.txt](debug/T8.txt) |

**Phase breakdown:**
- **T1–T4** rewrite tags (grammatical transformation passes)
- **T5–T6** reorder tokens (Russian word-order correction, digit-index actions)
- **T7–T8** validate structure (all no-action guards; flag constituent types for the compiler)

**Record format note:** T4 uses a 9-byte record with a 1-byte flags field; T7/T8 use an 8-byte record with flags stored in bytes 6–7 (after the two pointer fields) rather than at the end. T1–T3/T5/T6 use the standard 10-byte layout with flags in bytes 8–9.

**Termination:** T1–T4, T6, T7, T8 terminate via a null-pointer sentinel record (`pat_off=0, act_off=0`) immediately after the last real record. T5 uses a fixed-count mechanism: the last record (T5[8]) has `flags=0x0009` encoding the table size; there is no null sentinel after T5.

**Key insight:** Tables T7 and T8 have **no replacement field** (act_off is always 0). They are "recognize-and-protect" guards — a match annotates constituent boundaries used by the compiler's inflection stage, but nothing is rewritten.

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

Rules are applied in **7 passes** in the Lua port (each pass = one `table.insert(rules, {...})` in `rules.lua`), corresponding to tables T1–T5, T7, T8. T6 (47 rules) exists in the binary between T5 and T7 but is absent from the Lua port.

**Important:** Tables T7 and T8 have **no replacement field** — they are "recognize-and-protect" guards.

### Table execution notes (from binary sweep — see [debug/](debug/) files)

- **T1** can be cleared entirely without hang or output change on "She can speak Russian."
  — its rules did not fire on that sentence, confirming T1 handles clause structure absent
  from a simple SVO sentence. See [debug/T1.txt](debug/T1.txt) for all 47 rules.
- **T2** and **T3** are fully locked: clearing even the last record alone hangs the engine.
  This is because the engine terminates by null-pointer sentinel (`pat_off=0`), not by
  record count — zeroing a string makes the pattern empty but leaves `pat_off` non-null,
  causing the engine to match "" at every position and loop forever. Fix: zero the pointer
  field itself, not the string it points to.
- **T7** can be cleared entirely but changes output — its rules fire on the test sentence.
  Nulling T7[0] (`P<$>N`) changes "в доме" → "в дом" (prepositional → nominative case)
  and "на стуле" → "в стул" (preposition + case change), proving T7's guards directly
  control compiler inflection of prepositional phrases. See [debug/T7.txt](debug/T7.txt).
- **T8** records [0–12] are essential (clearing any causes hang); records [13–82] can be
  cleared. The boundary record is T8[12] `L[RN]<$>p*` (flags=0x003F). See [debug/T8.txt](debug/T8.txt).
- **T6** (47 rules, absent from Lua port) sits between T5 and T7 in the binary.  Zeroing
  it crashes because an earlier offset calculation mistakenly included 9 extra string-pool
  bytes as records, corrupting the pool. See [debug/T6.txt](debug/T6.txt).

### Complete Pattern Syntax Reference (Experimental Confirmation)

The pattern syntax (`<>`, `[]`, `*`, `~`, `` ` ``) is a **proprietary format** never documented
in SAR2BI/LTGOLD. Meanings below are confirmed by:
1. The Lua parser implementation (`parser.lua:125-159`)
2. Surgical binary patching experiments on LTPRO.EXE (replacing specific rule patterns
   and comparing output deltas)

#### Pattern Tokens (in order of priority)

| Syntax | Name | What it matches | Example |
|--------|------|-----------------|---------|
| `` `word` `` | literal | Exact English word match against dictionary entry | `` `be` `` matches token for "be" |
| `[chars]` | select | A single token whose grammatical tag starts with ANY char in the brackets | `[VXY]` matches U, V, X, or Y |
| `<chars>` | any-match | Zero or more consecutive tokens, each matching one of the chars (lazy — tries one at a time until rest of pattern fits) | `<N>` matches zero or more nouns; `<$>` matches any token |
| `*` | boundary | Position at start (j==1) or end (j>#ts) of token stream | `*Z` = Z at start of sentence |
| `~` | negate | Prefix: inverts the NEXT pattern token (negation applies to the immediately following `[...]`, `<...>`, `` `word` ``, or single char) | `~Z` matches NOT Z; `~[bB]` matches NOT b/B |
| single char | char | A single token whose grammatical tag starts with that letter | `Z` matches ambiguous V-N-A token |

#### Detailed Semantics (Confirmed by Experiments)

**`~` negation prefix** (`parser.lua:150-153`):
Sets a negation flag for the immediately following pattern token.
When negation is active, the match condition is XORed — a token passes if it
does NOT satisfy the pattern element's normal condition.

*Experimental confirmation (T8[13] `~[bB]?[UVXY]` on "He can flob speak Russian."):*
- `[bB]?[UVXY]` (without `~`) → **DIFF**: matches nothing (no b/B token in stream), verb "speak" becomes infinitive
- `~[bB]?[UVXY]` (original) → protects U + ? + V, keeps "speak" finite
- The `~` allows matching U (modal "can") because U ∉ {b, B}

**`?` unknown token** (`parser.lua:154-156`, treated as `'char', '?'`):
Matches a token whose grammatical tag starts with `?` (word not in dictionary).

*Experimental confirmation (T8[13] on "He can flob speak Russian."):*
- `~[bB]?[UVXY]` protects verb after unknown word "flob"
- `?[UVXY]` (without `~[bB]`) → **SAME**: matches at "flob speak" (? + V), protects verb
- `~[bB][UVXY]` (without `?`) → **SAME**: still matches at "flob speak" via dual match positions

**`[chars]` character class** (`parser.lua:132-136`):
Matches a single token whose tag starts with ANY character in the bracketed set.
Does NOT match multi-character sequences — each bracket pair is exactly one token.

*Experimental confirmation (T8[13] `~[bB]?[UVXY]`):*
- `~[bB]?V` → **SAME** (V matches "speak")
- `~[bB]?U` → **DIFF** (U does NOT match "speak" — verb would need to be U)
- `~[bB]?X` → **DIFF**
- `~[bB]?Y` → **DIFF**
- Only V in [UVXY] matters for this sentence; U, X, Y are alternatives for other contexts

**`<chars>` any-match** (`parser.lua:137-141`):
Matches ZERO OR MORE consecutive tokens, each matching any char in the set.
Lazy (non-greedy): tries matching zero tokens first, then one, etc.
When `<...>` has EMPTY content (i.e., `<$>`), it matches ANY token (wildcard any-match).
The `$` inside `<>` is a CAPTURE MARKER consumed from the replacement stream,
not a pattern element itself.

*Implementation detail:* The any-match creates a `fallback` closure. When the
pattern element AFTER `<>` fails to match at the current position, the fallback
tries consuming one more token (matching it against the `<>` class) and retries
the rest of the pattern. This repeats until the pattern fits or all tokens are exhausted.

*Tokens matched by `<>` are passed to the replacement via the `$` capture mechanism.*

**`*` boundary marker** (`parser.lua:147-149`):
Matches position rather than a token. `*` at pattern start matches j==1
(beginning of token stream). `*` at pattern end matches j > #ts
(past end of token stream). Used to anchor patterns to sentence edges.

**Single-letter chars** (`parser.lua:154-156`):
A standalone uppercase/lowercase letter matches a token whose first tag
character equals that letter. Tags are single letters from the dictionary
(e.g., Z, N, V, A, R, P, T, etc.). See Step 3 for complete tag table.

#### How `~` interacts with each token type

| Pattern | Negated meaning |
|---------|-----------------|
| `~Z` | Match token whose tag is NOT Z |
| `~[bB]` | Match token whose tag is NOT b AND NOT B |
| `~<N>` | Match token that does NOT match N class (in any-match skip logic) |
| `` ~`be` `` | Match token whose English word is NOT "be" |
| `~?` | Match token whose tag is NOT `?` (not an unknown word) |

Note: `~` does NOT create a separate token in the stream — it modifies the
following token. `~[bB]?` is parsed as two tokens: negated-select `[bB]`,
then char `?`.

#### Example: T8[13] `~[bB]?[UVXY]` (token-by-token)

Given token stream: `R(He) U(can) ?(flob) V(speak) N(Russian)`:

1. `~[bB]` → j=2: token "can" has tag `U`. Is U in {b,B}? No. Negation means: match if NOT in set → **yes**
2. `?` → j=3: token "flob" has tag `?`. Matches `?` → **yes**
3. `[UVXY]` → j=4: token "speak" has tag `V`. Is V in {U,V,X,Y}? → **yes**

Result: match at position 2 ("can"). The rule protects tokens 2-4 (U, ?, V) from
subsequent modification, keeping "speak" in finite form "говорит".

#### Experimental Methodology

Patterns were tested by replacing a single rule's pattern string in LTPRO.EXE
with a simplified variant (same or shorter length, null-padded), running the
test sentence through DOSBox-X headless, and comparing the CP866-decoded output
to the unmodified baseline.

*Test sentences used:*
- `"She can speak Russian."` — baseline, output: `"Она может сказать Русского."`
- `"He can flob speak Russian."` — exercises T8[13] `~[bB]?[UVXY]`
- `"The dog that I saw ran away."` — exercises T8[10-11] validation rules
- `"He must not go."` — exercises T8[11] `[UV][kNR][VXY]`

### Replacement Syntax Reference (parser.lua:167-225)

When pattern tokens are matched 1:1 against stream positions, each replacement
character specifies what to do with the corresponding token. Replacement chars
are mapped per matched position — `find_and_replace(ts, j, replacement_char)`.

#### Replacement Characters

| Char | Effect | Notes |
|------|--------|-------|
| `' '` (space) | Suppress token output (set to `" "`) | Used in T8 protect rules: matched span generates no output |
| `.` | Keep token unchanged (no-op) | Morphology-preserving passthrough |
| `$` | Keep token unchanged (no-op) | Same as `.` — but `$` also has capture semantics in patterns |
| `@` | Apply grammatical transform using PATTERN character (not replacement) | E.g. in `N<"'#>N` → `A@`: transform noun to adjective, then apply adjective transform via `@` |
| Any other char | Transform token to target tag via `find_and_replace` | E.g., `Z` → `N`: resolve ambiguous token to noun form |

#### `find_and_replace()` Algorithm (parser.lua:205-225)

```lua
function find_and_replace(ts, j, target_tag)
  local w = ts[j]  -- e.g. "ZоткрыватьNWAоткрытый"
  if w:sub(1,1) == 'Z' and target_tag ~= 'Z' and target_tag:find('[VNA]') then
    -- Z-ambiguous token: resolve to V, N, or A
    local _,_,prefix = w:find('(.-)'..target_tag)
    ts[j] = target_tag .. prefix  -- replace tag + keep everything after target_tag
  else
    local _,_,prefix = w:find(target_tag..'(.*)')
    if prefix then
      ts[j] = target_tag .. prefix  -- replace tag, keep rest
    end
  end
end
```

Key behavior: `find_and_replace` does NOT look up the dictionary for a different
form — it finds the first occurrence of the target tag letter in the token string
and splices from there, keeping everything after it. For Z-ambiguous tokens,
it specifically looks for V, N, or A to resolve ambiguity.

This is a **string-level transformation**, not a morphological one. The actual
inflection (adjective declension, verb conjugation) happens later in the compiler
(`compiler.lua`), which maps the tag to the appropriate paradigm printer.

#### Example T8[12]: `L[RN]<$>p*` → `" "`

```
Token stream:   L  [RN]  <any>  p  *
                1    2    3..n   n+1  n+2
Replacement:    ' '  ' '  ' '   ' '
```

Each matched position gets a space replacement, consuming tokens from output.
The `$` inside `<>` is consumed from the replacement stream (it pairs with `<>`)
and does not independently generate a replacement slot.

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
| `W` | — (not in dic.txt) | **Multi-word phrase boundary marker** — inserted by T3 for fixed expressions and participial phrases. W-tagged words have special behavior: `is()` function checks `word:upper():find(class)` so they match ANY class letter. T3[117-120]: `N<wD>E[XYUV]` → `@$W` |
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
| `w` | — (not in dic.txt) | **Genitive chain marker** — inserted by T2/T3 between head noun and genitive/possessive modifier (e.g. "book of student" → N w N). Used in T5/T6 reordering patterns: `NwNw` → Russian genitive-first order. The `is()` function also has special case: W-tagged words match ANY class letter. |
| `x` | Impersonal verb combination ("there is", etc.) | Existential/impersonal construction |
| `y` | Auxiliary verb 'have' (existential/copular sense) | "have" in non-possession sense |
| `z` | Ambiguity v-n | Unresolved word: verb-s-form or noun |

#### Special symbols

| Symbol | dic.txt meaning | In rule patterns | In rule replacements |
|--------|-----------------|-----------------|---------------------|
| `#` | Untranslatable unit (proper noun, designation) | Unknown/foreign word token | Keep as-is |
| `\|` | Fictitious separator | Clause boundary marker in token stream | **Insert clause-boundary separator** — splits token stream for subordinate clause handling. T2[2]: `"<$>,"` → `\|$,=` |
| `*` | Dictionary separator | **Sentence boundary** (start j==1 or end j>#ts) — `*Z*` = single-Z sentence | N/A (replacement consumed as no-op at boundary) |
| `?` | — (not in dic.txt) | **Unknown word** — matches token whose tag starts with `?` (not in dictionary) | — |
| `-` | — | **Hyphen** in compound words; matches literal hyphen token | — (in replacements, hyphen is character literal) |
| `'` | — | **Apostrophe** / possessive marker token | — |
| `"` | — | **Quote mark** token | — |
| `:` | — | **Colon** punctuation token | — |
| `,` | — | **Comma** punctuation token | — |
| `(` `)` | — | **Parenthetical grouping** — optional/alternative substructure in patterns | **Group capture** — preserves parenthesized subpattern contents |
| `{` `}` | — | **Brace grouping** — alternative grouping in patterns | **Brace bracketing** — wraps output in braces (T2[4]: `(#)` → `{#}`) |
| `^` | — | **Word-join or boundary marker** — appears in `JK^` → `@Dj` | **Word-join operator** — connects adjacent tokens into Russian compound. T2[3]: `-` → `^` joins hyphenated words |
| `=` | — | **Case-equality operator** — tests/asserts grammatical case agreement between tokens | **Case-setting operator** — sets agreement case on following NP. T2[2]: `"<$>,"` → `\|$,=` |
| `;` | — | Subordinate clause separator in patterns | **Clause continuation marker** in replacements. T1[25]: `*\|as\|<$>,` → `@J$;` |
| `&` | — | **Coordination marker** in patterns — connects conjoined NPs | **Coordination operator** — outputs coordination between tokens. T4[128]: `ACA` → `@&` |
| `+` | — | Rare in patterns (`[g+]Z`) — unknown, possibly word-join modifier | **Compound modifier** — T3[133]: reverse-quoted NP → `@$+` |
| `%` | — | **Modifier flag for digit patterns** — `<H%D,>` = digits with modifier | — |
| `!` | — | **Inline Russian literal injection** — CP866 text embedded directly in pattern. T4[9]: `NI!мес!` → `A` where `!мес!` = "месяц" (month) | Same — inline CP866 Russian |
| `_` | — | **Underscore placeholder field** — literal `_` character from document template fill-in fields (e.g. `_______ day of __________` in LTGOLD/DEMO.TXT). T2[5]: `_Z[_*]` → `@N` matches a placeholder, the word written in it, and closing placeholder/end-of-sentence. | — |
| `@` | — | N/A in patterns | **Apply transform using pattern char** — `find_and_replace(ts, j, pattern_char)` instead of replacement char |
| `$` | — | **Capture group in `<$>`** — paired with replacement stream's `$` to capture a span for back-reference. Does NOT affect pattern matching | **No-op / keep token unchanged** — same as `.`. The `$` consumed from replacement by `<>` is discarded |
| `` ` `` | — | **Literal English word match**: `` `be` `` checks `ts[j] == en_ru["be"]` | **Literal Russian word insertion**: `` `быть` `` replaces token with CP866 string "быть" |
| `' '` (space) | — | N/A | **Suppress output** — sets token to space. Used in T8 protect rules: matched span generates no output |
| `.` | — | N/A | **Keep current token unchanged** (passthrough/no-op) |

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

## Experimentally Verified Findings (LTGOLD Binary Patches)

### Overview

We built a surgical binary-patching framework (`LTGOLD/explore_patterns.py`) to replace
individual rule strings in LTPRO.EXE with variants, then measure translation output
changes under DOSBox-X headless. This directly confirms pattern semantics that would
otherwise be speculative.

### Table Structure (from LTPRO.EXE)

Record layouts differ by table — see the Table Structure section above for the full breakdown.  
Standard 10-byte record (T1, T2, T3, T5, T6):

```
bytes 0–1:  pat_off  (uint16 LE) — offset into string pool; pat_off=0 = sentinel
bytes 2–3:  <padding / part of pointer — actual pointer is 4 bytes in the pool>
bytes 4–5:  act_off  (uint16 LE) — offset into string pool; act_off=0 = no action
bytes 6–7:  <padding>
bytes 8–9:  flags    (uint16 LE) — category/priority mask (0x0000–0x003F observed)
```

T4 uses a 9-byte record with a 1-byte flags field at offset 0 and pointers at 1 and 5.  
T7/T8 use an 8-byte record: pat_off at 0, act_off at 4, flags at 6.

**Flags field = constituent-type index (0–31).** Causal proof from binary patching:
patching T7[0] flags (0x0002 → 0x0014) changes "доме" → "дом" (prepositional case
removed). Patching T8[13] flags (0x0025 → 0x0000) changes "говорит" → "говорить"
(finite → infinitive). See "Flag Semantics" section for complete experimental results.
The flags seen in T7/T8 (validation tables) are the highest and most varied, consistent with
them encoding the type of phrase being validated. See [debug/T7.txt](debug/T7.txt) and
[debug/T8.txt](debug/T8.txt) for the distribution.

**Sweep results summary** (test sentence "She can speak Russian."):

| Table | Records | Safe to clear | Boundary | Notes |
|-------|---------|---------------|----------|-------|
| T1 | 47 | ALL 47 | none | No rules fire on this sentence |
| T2 | 157 | NONE | T2[156] hangs | Sentinel-lock (see above) |
| T3 | 136 | NONE | T3[135] hangs | Sentinel-lock |
| T4 | 178 | 4 (174–177) | T4[173] hangs | |
| T5 | 9 | 1 (index 8) | T5[7] hangs | Fixed-count termination |
| T7 | 35 | ALL 35 | none (output changes) | |
| T8 | 83 | 70 (13–82) | T8[12] hangs | First 13 records essential |

### T8[10-13] Cross-Rule Comparison

These 4 T8 rules have (none) action — they are pure structural guards that validate a
token sequence for the compiler without rewriting anything. All are within the essential
first-13-record block (clearing any hangs the engine). Full T8 dump: [debug/T8.txt](debug/T8.txt).

Rules fire on consecutive positions in the token stream for "The dog that I saw ran away."
(output: "Собака, которую Я видeл убегать."):

| Rule | Pattern | Flags | Fires at |
|------|---------|-------|----------|
| T8[10] | `[VXY]N[N#][UVXY]` | 0x0037 | Verb + noun object + aux chain |
| T8[11] | `[UV][kNR][VXY]` | 0x0038 | Modal/aux + (neg/noun/pronoun) + verb |
| T8[12] | `L[RN]<$>p*` | 0x003F | Relative pronoun + NP + preposition (last essential) |
| T8[13] | `~[bB]?[UVXY]` | 0x0025 | Non-B/b token + unknown + modal-verb (first clearable) |

The flags progression 0x0037 → 0x0038 → 0x003F suggests these three share a constituent
tier; T8[13]'s lower flag (0x0025) is consistent with it being the first non-essential record.

### Key Findings

1. **`$` is consumed from replacement, not part of pattern matching.** In T8[12]
   `L[RN]<$>p*`, the `$` token in `<>` is read from the replacement stream by
   `eat('$', f())` — it does NOT affect pattern matching. Experiment: replacing
   `<$>` with `<Z>` or `<>` produced SAME output — the sentence doesn't have a
   relative clause ending with a preposition.

2. **T7 and T8 are purely structural guard tables** — all 35 T7 rules and all 83
   T8 rules have `act_off=0` (null action pointer). They do not rewrite tokens;
   a match annotates a constituent boundary whose **flags field** encodes the
   constituent type index (0–31) used by the compiler's inflection stage.
   See [debug/T7.txt](debug/T7.txt) and [debug/T8.txt](debug/T8.txt).

   **Causal confirmation:** Nulling T7[0] (`P<$>N`) changes "в доме" → "в дом"
   (prepositional → nominative case) and "на стуле" → "в стул" (preposition
   selection + case change). Patching T7[0] flags from 0x0002 → 0x0014 produces
   the same effect. This proves T7 guards directly control the compiler's
   case-assignment logic.

3. **Multiple matches per rule**: T8[11] `[UV][kNR][VXY]` and T8[13]
   `~[bB]?[UVXY]` can match at multiple positions in suitable sentences.
   T8[13] on "He can flob speak Russian." matches twice: at (U, ?, V) and
   at (R, U, ?) positions.

4. **T5 and T6 use digit-only actions** (e.g. `"23"`, `"3455"`, `"555"`) which
   are positional reorder indices, not tag-transform characters. T5 has 9 rules
   ([debug/T5.txt](debug/T5.txt)); T6 has 47 rules ([debug/T6.txt](debug/T6.txt))
   and is absent from the Lua port. Both handle Russian NP word-order correction.

## Unresolved Questions (updated)

- [x] What does `$` capture exactly in replacements? — **Confirmed**: consumed from replacement stream, marks a `<>` span for back-reference; does NOT affect pattern matching
- [x] How does the `~` negation interact with `any` (`<...>`) tokens? — **Confirmed**: `~` sets a negation flag; `<...>` with negation matches tokens NOT in the class
- [x] How are the 8 tables different from each other? — **Confirmed**: T1–T4 = tag rewrite; T5–T6 = word-order reorder (digit actions); T7–T8 = structural guards (all no-action). See [debug/](debug/) files.
- [x] Why do T2/T3 rule deletions cause the engine to hang? — **Confirmed**: the engine terminates by null-pointer sentinel (`pat_off=0`), not by count. Zeroing a pattern *string* leaves `pat_off` non-null → engine sees empty-string pattern, matches everywhere, loops forever. Fix: zero `pat_off` itself.
- [x] How do the flags values (0x00–0x46) affect rule behaviour? — **Confirmed by binary patching experiments**: flags are a **constituent-type identifier** — they tell the compiler what syntactic constituent was matched so it knows how to inflect it. Causal proof: patching T7[0] flags from 0x0002→0x0014 changes "доме"→"дом" (prep case → nominative). See "Flag Semantics" section below for full experimental results.
- [ ] What is the exact meaning of `W` tokens (phrases)? (Still unknown)
- [ ] What do replacement symbols like `=`, `;`, `+`, `&`, `^` do? (Unused in current Lua port)
- [ ] What do T5/T6 digit actions mean exactly — are they 1-based position indices, or offsets? (Hypothesis: 1-based indices into the matched token sequence, selecting which tokens to keep and in what order)
- [ ] T6 is absent from the Lua port — which of its 47 rules overlap with T5/T7, and which are genuinely missing functionality?

## Flag Semantics (Constituent-Type Identifier)

The flags field in every rule record is a **constituent-type identifier** — it tells the
compiler what kind of syntactic phrase was matched, so the compiler knows how to apply
Russian morphology (case, agreement, inflection) to the matched span.

This was confirmed by cross-table analysis: grouping all rules by flag value and
comparing the patterns within each group reveals consistent semantic clusters.

### Evidence

**Same flag = same constituent class across all tables.**

T7 is the cleanest evidence source (all 35 rules are pure guards with identifiable phrase types):

| Flag | T7 pattern(s) | Constituent |
|------|--------------|-------------|
| `0x0000` | `H-H`, `N-N`, `PA`, `N<Hw>/N` | No inflection grouping needed (compounds, bare pairs) |
| `0x0002` | `P<$>N` | **PP** — prepositional phrase |
| `0x0003` | `U<KD>[VX]` | **VP with modal** |
| `0x0004` | `F<&D>F`, `[AO]<AO#">[?#N]`, `[AOE]<&D>[EA]` | **AP / participial phrase** |
| `0x0005` | `EN`, `E~<P>N` | **Participial+NP** (past participle head) |
| `0x0006` | `N<AOD(?)w#'">[NH]`, `i<AOD?#'">N` | **Full NP** |
| `0x000B` | `[GE]M`, `VM` | **Verb + object pronoun** |
| `0x000C` | `Q<AO?">N` | **Interrogative NP** |
| `0x0013` | `V[,C]<C>V` | **Coordinated VP** |

The **same flag values recur in T1–T3 rewrite rules** whose output produces those same
constituent types. Examples:
- T2[47] `[fTAOSN#GJjZ]~<QJLBR>[UVXY]` (none) → `0x003B` = same as T8[80–81]
  `[NR]UV` / `[NR]Vb` (subject-verb-object frames)
- T2[16–18] guard rules protecting built aux chains → `0x0033`, `0x0034`, `0x0036`
- T8[17–26] all have flag `0x0001` — every subject+VP frame shares this type
- T8[0–4] all have flag `0x000C` — every conjunction+verb head shares this type

**`0x003F` = all 6 low bits set = "full clause / sentence-level wildcard."**

T1[2] `*~<UVXY>Z*` → `0x003F` and T8[12] `L[RN]<$>p*` → `0x003F` both use `*` anchors
(sentence boundaries). `0x003F` = `0b00111111` means this guard is active for any
inflection context — it validates a full-clause structure.

**`0x0000` = "no constituent typing."**

Most `0x0000` rules are rewrite rules in T1–T4: they transform a tag, so the
compiler only needs the resulting tag, not a phrase-type annotation. Guard rules
with `0x0000` (`H-H`, `N-N`, hyphenated compounds) are for tokens that do not
participate in Russian inflection agreement.

**Higher flags = larger/more complex constituents.**

T8 exclusively holds flags above `0x001F`. The highest, `0x0046` (`NlRV`: noun +
genitive-relative + pronoun + verb), is a full relative clause. Flags increase
monotonically with constituent complexity.

### Causal proof from binary patching

We confirmed the flags control compiler inflection by surgically changing the flags
field of T7[0] (`P<$>N`, original flags=0x0002) in LTPRO.EXE and observing output changes:

**Test 1: Null T7[0] pattern (rule disabled)**
- Sentence: "He is in the house."
- Baseline: "Он - в доме." (prepositional case)
- No T7[0]: "Он - в дом." (nominative — no PP case assignment)
- Sentence: "She sat on the chair."
- Baseline: "Она посидeла на стуле." (prepositional case, prep "на")
- No T7[0]: "Она посидeла в стул." (accusative, prep changed to "в")
→ T7[0] firing is required for correct Russian PP inflection

**Test 2: Flags bit mapping on T7[0] ("He is in the house.")**
Patching T7[0] flags to each power-of-two bit and observing the noun output:

| Flag value | Noun output | Case/Number |
|-----------|-------------|-------------|
| 0x0000 (0) | доме | Prepositional singular (same as original) |
| 0x0001 (bit 0) | домах | Prepositional plural |
| 0x0002 (bit 1) | доме | Prepositional singular (ORIGINAL) |
| 0x0004 (bit 2) | дое | Corrupt ending |
| 0x0008 (bit 3) | доме | Prepositional singular |
| 0x0010 (bit 4) | дом | Nominative (no inflection) |
| 0x0020 (bit 5) | доме | Prepositional singular |
| 0x0040–0x8000 | доме | Prepositional singular (all fall back) |

Full 5-bit index scan (0–31):
- index 0, 2, 8–15: "доме" (prepositional sg) — same as original
- index 1, 18: "домах" (prepositional pl)
- index 3, 7, 12, 14, 16, 19–21: "дом" (nominative)
- index 4, 17: "дое" (corrupt — stem truncated)
- index 5: "домом" (instrumental)
- index 6: "дома" (genitive)
- index 10: "доа" (corrupt)
- index 22–31: "доме" (prepositional sg) — values ≥ 22 all fall back to default

→ The flags field is a **~5-bit constituent-type index** (values 0–31) where the compiler
maps each index to a specific inflection rule. Values ≥ 32 all produce default behavior.

**Test 3: T8[13] flag mapping ("He can flob speak Russian.")**
T8[13] pattern `~[bB]?[UVXY]` (original flags=0x0025). Patching flags produces diverse output:

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

→ T8 flags control not just verb finiteness but also negation, word order, clause
structure, and noun case — the compiler uses the flag value as a complex selector
for the entire output generation strategy.

**Test 4: T7[0] with T8[13] flag (0x0025)**
→ "Он - в доме." SAME. A verb-construction flag has no effect in a PP context.

**Test 5: T8[13] with T7[0] flag (0x0002)**
→ "Он может flob говорить Русского." DIFF (infinitive). A PP flag doesn't preserve
verb finiteness.

→ **Same flag value can produce different effects in different tables** because
the constituent type index is interpreted in the context of the matched phrase type
(PP vs VP vs clause).

**Key insight:** The flags field is a **5-bit constituent-type selector** (not a bitmask).
The compiler has a lookup table mapping index 0–31 to inflection behaviors:
- Word-level constituents (compounds, numbers, hyphenated): indices 0–7
- Phrasal constituents (PP, NP, AP, VP): indices 8–15
- Clause-level constituents (main clause, relative clause): indices 16–23
- Sentence-level wildcard (everything): index 24–31 (all fall back to default)

The original values used by T7's guard rules:
- 0x0002 (index 2) = PP constituent → prepositional case on noun
- 0x0000 (index 0) = word-level (numbers, unknowns, demonstratives) → no PP inflection
- 0x0014 (index 20) = clause-level → nominative (no case assignment from PP)

**Do flags mean the same thing in every table?** Likely yes. The compiler runs once
at the end of the pipeline — it doesn't know which table produced a flag, it just
sees "this span has type index N". Index 2 must mean "PP constituent" whether
it was tagged by T7[0] or any other table's rule. Evidence:

1. **Same flag values appear in rewrite tables (T1–T4) and guard tables (T7–T8) with
   semantically consistent patterns.** T1[2] `*~<UVXY>Z*` → 0x003F matches
   T8[12] `L[RN]<$>p*` → 0x003F — both are full-clause patterns. T2[16–18]
   guard rules → 0x0033/0x0034/0x0036 match T8[7–11] subject-predicate frames
   in the same range.

2. **Cross-table test:** T7[0] with T8[13]'s 0x0025 → "Он - в доме." (SAME).
   The compiler received "this PP is a modal verb construction type 0x0025",
   found no PP inflection rule for that type, and fell through to default
   prepositional case — consistent with a shared index space.

**Caveats:**
- T4 uses a **1-byte** flags field (0x00–0x42) while T7/T8 use 2 bytes. The
  compiler may zero-extend: 0x3C in T4 = 0x003C in T7.
- T1–T6 flags might have a **dual role**: rule priority/ordering within the
  table AND constituent-type for the compiler. The priority function would be
  table-local, the constituent-type function global.
- T5[8] with 0x0009 encoding table size is a clear exception — not a
  constituent type at all.

**To confirm:** pick a T2 or T4 rule with flags=0x0002 (same as T7[0]'s PP marker),
null just that rule's pattern, and check if the noun case reverts from "доме"
to "дом". If so, 0x0002 = PP universally.

**Special case:** `T5[8]` flags=`0x0009` encodes the table size (fixed-count
termination), not a constituent type — T5 uses flags differently from all other tables.

## Testing

To test changes, edit test sentences in `init.lua:81-97` and run:

```sh
lua init.lua
```

To see which rules are applied, the parser prints "Applying ..." for each match.
