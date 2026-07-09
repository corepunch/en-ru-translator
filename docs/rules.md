# Rule Pattern Syntax

The patterns in `rules.lua` use a compact notation to match grammatical sequences.
See [Pipeline](pipeline.md) for how rules are applied.

## Basic Token Matching

| Syntax | Matches | Example |
|--------|---------|---------|
| `Z` | A verb token | `Z` matches any verb |
| `N` | A noun token | `N` matches any noun |
| `V` | An adjective token | `V` matches any adjective |
| `P` | A preposition token | `P` matches any preposition |
| `*` | Any sequence of tokens | `*Z` = anything then a verb |

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

## Complex Pattern Examples

Decoding actual rules from `rules.lua`:

```lua
-- Rule: "*Z[?#]*"
-- Matches: anything, verb, number/unknown, anything
-- Purpose: skip verb-number sequences

-- Rule: "*~<UVXY>Z*"
-- Matches: anything, (non-unique/non-verb/non-adjective/non-gerund)*, verb, anything
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

### Example Replacements

```lua
-- "@" = transform current token using the matched pattern
"@$V"  → transform current, then next as verb
"@N"   → transform to noun
"@@"   → transform twice (double transformation)

-- "$" = reference captured group
"$V"   → use captured verb
"$N"   → use captured noun
"$J$j" → use captured conjunction, comma, captured conjunction again

-- Literal Russian
"`быть`" → insert Russian word "быть"
```

<!-- TODO: Document all replacement token meanings.
     Understand the `$` capture reference system in detail.
     Map priority values (0x00-0x3F) to their meaning — do they control rule ordering?
     Document what `^`, `=`, `;` do exactly in replacements. -->
