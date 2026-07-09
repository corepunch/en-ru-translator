# Rule Pattern Syntax

The patterns in `rules.lua` use a compact notation to match grammatical sequences.
See [Pipeline](pipeline.md) for how rules are applied.

**Source:** Extracted from `LTGOLD.EXE` binary via `extract2.py`. Original format
documented in `LTGOLD/dic.txt` (SARMA DIC format, CP866 encoded).

## Basic Token Matching

| Syntax | Matches | Example |
|--------|---------|---------|
| `Z` | A verb token | `Z` matches any verb |
| `N` | A noun token | `N` matches any noun |
| `V` | An adjective token | `V` matches any adjective |
| `P` | A preposition token | `P` matches any preposition |
| `*` | Sentence boundary | Start or end of token stream (see below) |

### Sentence Boundary `*`

`*` is **not** a generic wildcard — it matches sentence boundaries:

- `*` at **start** of pattern = matches beginning of token stream (`j==1`)
- `*` at **end** of pattern = matches end of token stream (`j>#ts`)
- `~*` = negated boundary (matches if NOT at boundary)

**Example:** `*Z[?#]*` matches: **start-of-sentence** → verb → number/unknown → **end-of-sentence**

This means the pattern only fires when the verb+number sequence spans the entire sentence.

From `parser.lua:200`:
```lua
elseif t == 'wildcard' and xor(i, j==1 or j>#ts) then eat('@', f())
```

## Character Classes `[...]`

Matches **one** of the listed tags:

| Pattern | Matches |
|---------|---------|
| `[VZ]` | Adjective OR verb |
| `[?#]` | Unknown word OR number |
| `[TAO]` | Empty/adjective/or |
| `[UVXY]` | Unique verb/infinitive/adjective/gerund |
| `[,C]` | Comma OR conjunction |

## Any-Match `<...>`

Matches **zero or more** of any listed tag (like regex `*` but for character classes):

| Pattern | Matches |
|---------|---------|
| `<VXY>` | Zero or more adjectives/gerunds |
| `<dD,>` | Zero or more lowercase/comma |
| `<KDd>` | Zero or more (unique verb/lowercase/adverb) |
| `<TAOIH>` | Zero or more (empty/adjective/or/infinitive/subjunctive) |

## Negation `~`

Inverts the next match:

| Pattern | Matches |
|---------|---------|
| `~Z` | Anything EXCEPT a verb |
| `~[UVXY]` | Anything EXCEPT unique/infinitive/adjective/gerund |
| `~<,>` | Anything EXCEPT commas |

## Literal Words `` ` ``

Matches a specific English word:

| Pattern | Matches |
|---------|---------|
| `` `be` `` | The word "be" |
| `` `no` `` | The word "no" |
| `` `if` `` | The word "if" |
| `` `that` `` | The word "that" |

## Special Characters in Patterns

| Char | Meaning | Source |
|------|---------|--------|
| `:` | Colon — punctuation token | `utils.lua:50` extracts `[,%!%.;:]?` |
| `"` | Quote — punctuation token | Same extraction |
| `(` | Left paren — captured as literal | Used in `(G)` pattern |
| `)` | Right paren — captured as literal | Used in `(G)` pattern |
| `!` | Exclamation — punctuation token | `utils.lua:50` |
| `?` | Unknown word marker | `#word` prefix for unrecognized |
| `#` | Number marker | Attached to numeric tokens |
| `/` | Separator in patterns | `N[C/]G` — conjunction or slash |

## Complex Pattern Examples

Decoding actual rules from `rules.lua`:

```lua
-- Rule: "*Z[?#]*"
-- Matches: start-of-sentence, verb, number/unknown, end-of-sentence
-- Purpose: match sentences that are just a verb + number (e.g. "Runs 3")
-- Note: the two * markers mean this only matches if the pattern spans the full sentence

-- Rule: "*~<UVXY>Z*"
-- Matches: start-of-sentence, (non-unique/non-verb/non-adjective/non-gerund)*, verb, end-of-sentence
-- Purpose: match verbs not preceded by auxiliary verbs

-- Rule: "*<dD,>B<dD>[VZ]<$>,"
-- Matches: (lowercase/comma)*, "be" auxiliary, (lowercase/comma)*, adj/verb, "$" (case marker), comma
-- Purpose: match "be" constructions like "is being done"

-- Rule: "`if`~<,>`then`"
-- Matches: "if", (non-comma)*, "then"
-- Purpose: match "if...then" constructions

-- Rule: "*G[C,JPp]"
-- Matches: anything, gerund, conjunction/comma/subjunctive/preposition
-- Purpose: match gerund phrases

-- Rule: "*NZN<GFNwPDA>[,(*]"
-- Matches: anything, noun, verb, noun, (gerund/passive/noun/lowercase/preposition/adverb/article)*, comma/lparen/anything
-- Purpose: match SVO structures

-- Rule: "(G)"
-- Matches: captured gerund in parentheses
-- Purpose: match parenthesized gerund phrases

-- Rule: "V<TAO>NG"
-- Matches: verb, (empty/adjective)*, noun, gerund
-- Purpose: match verb phrases with following gerund

-- Rule: "p[*)]"
-- Matches: preposition, then one of: *, ), or unknown
-- Purpose: match preposition at boundary

-- Rule: "B<?>*"
-- Matches: "be" auxiliary, unknown*, end-of-sentence
-- Purpose: match "be" at end of sentence
```

## Replacement Tokens

The replacement string uses these conventions:

| Token | Action |
|-------|--------|
| `@` | Apply grammatical transformation to current token |
| `$` | Reference matched `<...>` group or `(` capture |
| `.` | Keep current token unchanged |
| `#` | Keep number/unknown token |
| `` `word` `` | Insert literal Russian word |
| `N`, `V`, `Z` etc. | Change current token's grammatical tag |
| `^` | Transform to noun form |
| `=` | Set case marker |
| `j` | Insert comma |
| `;` | Insert separator |
| ` ` (space) | Insert space in output |

### Example Replacements

```lua
-- "@" = transform current token using the matched pattern
"@N"   → transform to noun
"@@"   → transform twice (double transformation)
"@$V"  → transform current, then next as verb
"@P"   → transform to preposition
"@g"   → transform to gerund form
"@J"   → transform to conjunction

-- "." = keep current token unchanged
".V"   → keep verb as-is
".N"   → keep noun as-is
".A"   → keep adjective as-is
".$V"  → keep verb with case marker

-- "$" = reference captured group
"$V"   → use captured verb
"$N"   → use captured noun
"$J$j" → use captured conjunction, comma, captured conjunction again
"$P$;" → use captured preposition, captured separator

-- Literal Russian
"`быть`"    → insert Russian word "быть"
"`для`"     → insert Russian word "для"
"`Для`"     → insert capitalized Russian word

-- Combined
"@$V"   → transform current, use captured verb
"@$NV"  → transform current, use captured noun then verb
"@@\"$^NV" → double transform, quote, captured noun as noun, verb
```

### Priority Values

Each rule has a priority byte (first element, `0x00`-`0x3F`). These control
rule ordering within a pass — lower priority fires first. The actual mapping
of priority values to rule categories is not yet fully understood.

### Multiple Rule Tables

LTGOLD stores rules in **multiple separate tables** in `LTGOLD.dat`, not one.
Each table is processed sequentially. Found via `extract2.py`:

| Table | Offset | Entries | Record Size | Purpose |
|-------|--------|---------|-------------|---------|
| 1 | 3374 | 47 | 10 bytes | Core structural patterns (verb phrases, negation, conditionals) |
| 2 | 3854 | 157 | 10 bytes | Detailed grammatical transformations (articles, pronouns, tenses) |
| 3 | 5434 | 136 | 10 bytes | Preposition handling, conjunction processing, special constructions |
| 4 | 11981 | 178 | 9 bytes | Passive voice, gerunds, complex verb forms |
| 5 | 16610 | 9 | 10 bytes | Final cleanup rules |
| 6 | 16874 | 56 | 10 bytes | Noun agreement patterns |
| 7 | 17972 | 35 | 8 bytes | Preposition/case rules (no actions — pattern-only) |
| 8 | 19158 | 83 | 8 bytes | Final rules (no actions — pattern-only) |

**Record formats:**

10-byte record: `[pattern_offset:u16] [unknown:u16] [action_offset:u16] [unknown:u16] [flags:u16]`
9-byte record: `[flags:u8] [pattern_offset:u16] [unknown:u16] [action_offset:u16] [unknown:u8]`
8-byte record: `[pattern_offset:u16] [unknown:u16] [action_offset:u16] [flags:u16]`

Pattern and action are null-terminated C-strings stored in the same data block.
Offset 0 means "no pattern" or "no action".

**Tables with no actions** (tables 7, 8) likely match patterns but don't modify
tokens — they may set flags or control subsequent rule processing.

<!-- TODO: Document all replacement token meanings.
     Understand the `$` capture reference system in detail.
     Map priority values (0x00-0x3F) to their meaning — do they control rule ordering?
     Document what `^`, `=`, `;` do exactly in replacements.
     Determine how tables are referenced from code (function call chain). -->
