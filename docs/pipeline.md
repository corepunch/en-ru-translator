# Translation Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Input Text  │───▶│  Tokenize   │───▶│    Parse     │───▶│   Compile   │
│  (English)   │    │  + Lookup   │    │ (apply rules)│    │ (inflect)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                         │                  │                  │
                    BASE.DIC          rules.lua          paradigms.lua
                    BASE.RUS         (5 rule sets)      (noun/adj/verb)
```

## Stage 1: Dictionary Loading (`load.lua`)

Parses the LTGOLD dictionary format. Two dictionaries are loaded:

- **`BASE.DIC`** — English→grammatical codes. Format: `word*CODES` per line, CP866 encoded.
- **`BASE.RUS`** — Russian stems→codes. Used for inflection lookup during compilation.

Both are built into nested Lua tables:

```
en_ru["word"].__lex = "Z001N"  -- packed grammatical tags
en_ru["word"]["particle"].__lex = "..."  -- multi-word entries
```

Multi-word entries (e.g. "turn off") are stored as nested tables:
`en_ru["turn"]["off"].__lex = "Z..."`.

See [Dictionary Code Structure](dictionary.md) for details on the binary format.

## Stage 2: Tokenization (`utils.tokenize()`)

Converts raw English text into a sequence of grammatical tokens:

1. Splits input on word boundaries + punctuation
2. Looks up each word in the dictionary
3. For single-word matches: returns the packed grammatical code (`Z001N`)
4. For multi-word phrases: tries extending the match (e.g. "turn off" as single entry)
5. Unrecognized words get prefixed with `#` (e.g. `#unknown`)

Output: array of token strings like `{"Z001", "N003", ",", "P002", "Z015"}`

## Stage 3: Rule Application (`parser.lua` + `rules.lua`)

The core of the translation engine. Applies ~200 pattern-matching rules in 5 passes.

Each rule has the form:
```lua
{ priority, "PATTERN", "REPLACEMENT" }
```

**Rules are applied left-to-right across the token stream.** When a pattern matches,
the replacement tags are substituted. Rules handle:

- Grammatical transformations (e.g. verb tense, noun case)
- Word order adjustments for Russian syntax
- Preposition selection based on governed noun case
- Insertion of auxiliary words

### Rule Set Summary

| Set | Rules | Purpose |
|-----|-------|---------|
| 1   | ~50   | Core structural patterns (verb phrases, negation, conditionals) |
| 2   | ~160  | Detailed grammatical transformations (articles, pronouns, tenses) |
| 3   | ~140  | Preposition handling, conjunction processing, special constructions |
| 4   | ~100  | Passive voice, gerunds, complex verb forms |
| 5   | ~50   | Final cleanup and agreement rules |

### Pattern Matching Engine

`parser.lua` tokenizes patterns using `pattern_tokens()`:

- `select` token — matches one of `[...]` character classes
- `any` token — matches zero or more of `<...>` tags
- `wildcard` token — `*` matches anything
- `literal` token — `` `word` `` matches exact English word
- `char` token — single letter matches that grammatical tag
- `~` prefix — inverts the next match

`match_pattern()` tries matching at every position in the token stream. On match,
`replace()` fires, which calls `find_and_replace()` to update grammatical tags on
individual tokens.

See [Rule Pattern Syntax](rules.md) for the full pattern language reference.

## Stage 4: Compilation (`compiler.lua` + `paradigms.lua`)

Converts the tagged token stream into inflected Russian text.

For each token, `compiler.lua` dispatches to a type-specific printer:

| Printer | Handles | Action |
|---------|---------|--------|
| `N` | Nouns | Lookup paradigm, inflect for case/number/gender |
| `Z`/`V` | Verbs | Conjugate for tense/person/aspect |
| `A`/`S` | Adjectives | Decline to agree with governed noun |
| `P` | Prepositions | Set grammatical case for following noun |
| `R` | Pronouns | Set person/number, decline for case |
| `X` | Infinitives | Mark infinitive form |
| `U` | Unique verbs | Handle special forms ("must", "can") |
| `F` | Passive participles | Past passive form |
| `G` | Gerunds | Present participle form |
| `T` | Separators | Output empty string |

State is tracked across tokens: `gender`, `number`, `person`, `case`, `aspect`,
`tense`, `voice`. This allows later tokens to agree with earlier ones.

See [Morphological Paradigms](paradigms.md) for the inflection tables.

## Debugging

To debug rule application, uncomment print statements in `parser.lua:222-223`:

```lua
print("Applying "..m, r)
```

To see token output, check `parser.lua:248`:

```lua
echo('blue', "%s", type(n)=='table' and utils.debug(n) or utils.decode(n))
```

To see compiled output, `compiler.lua:155` prints the final Russian text.
