# RULES_APPLIED.md — How Rules Are Applied in LTGOLD

Step-by-step documentation of how rules from `rules.lua` are applied.
Each finding is documented so work can be stopped and resumed quickly.

## Pipeline Overview

```
Input English → Tokenize → Apply Rules → Compile → Russian Output
```

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

Rules are applied in 5 passes (each pass = one `table.insert(rules, {...})` in `rules.lua`).

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

## Step 3: Concrete Rule Traces

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
