# Dictionary Code Structure

Each word in `BASE.DIC` / `BASE.RUS` has a packed binary code attached after `*`.
The code is a sequence of CP866 bytes encoding grammatical information.

See [Pipeline](pipeline.md) for how dictionaries are loaded.

**Source:** Extracted from `LTGOLD.EXE` via `extract.py` and `load.lua`. Format
documented in `LTGOLD/dic.txt` (SARMA DIC format, CP866 encoded, in Russian).
Additional notes in `LTGOLD/README.CYR` and `LTGOLD/NEWLTGE.DOC`.

## BASE.DIC (English) Code Format

```
word*GRAMMATICAL_CODE
```

The grammatical code is a string of characters like `Z001N`, `N003P`, `V002A`, etc.
Each character is a grammatical tag, optionally followed by a 3-digit paradigm ID.

### Grammatical Tags

From `load.lua:35-37` (commented-out reference):
```lua
-- N="noun", V="verb", A="adjective", D="adverb", E="past participle",
-- W="phrase", I="idiom", P="preposition", n="noun plural"
```

| Tag | Part of speech | Notes |
|-----|---------------|-------|
| `Z` | Verb | Followed by paradigm ID (e.g. `Z001`). Maps to `V` internally |
| `N` | Noun | Followed by paradigm ID |
| `V` | Adjective | Same as `A` (used interchangeably) |
| `A` | Adjective | Same as `V` |
| `P` | Preposition | May have case government info (e.g. `PР` = preposition governing Род. падеж) |
| `D` | Adverb | |
| `E` | Past participle | |
| `G` | Gerund / present participle | |
| `S` | Adjective (alternate) | |
| `C` | Conjunction | |
| `X` | Infinitive marker | |
| `U` | Unique verb form | "must", "can", "shall" etc. |
| `F` | Passive participle | |
| `R` | Pronoun | `R013` = person 0, number 1, case 3? |
| `Q` | Question word | |
| `J` | Subordinating conjunction | |
| `T` | Empty / separator | |
| `#` | Number | |
| `?` | Unknown word | |
| `n` | Noun (plural) | lowercase = modifier |
| `w` | Lowercase modifier | |
| `W` | Phrase marker | Multi-word entry indicator |
| `I` | Idiom marker | |

### Example Codes

```
restoration*Z001N002N   → verb (paradigm 001) + noun (paradigm 002) + noun again
bright*V003A001         → adjective (paradigm 003) + adjective (paradigm 001)
no*P                    → preposition (no paradigm ID)
```

## BASE.RUS (Russian) Code Format

The Russian dictionary stores binary codes (not character strings). Each entry's
code bytes encode grammatical properties used during compilation.

### Byte Layout

| Byte | Mask | Meaning |
|------|------|---------|
| `byte(1)` | — | Part-of-speech tag (first char of grammatical code) |
| `byte(2)` | — | Flags: `0x80` = adjective paradigm in byte(3), else in byte(4); `&2` = aspect flag |
| `byte(3)` | `&3` | Gender (0=male, 1=female, 2=neutral) OR adjective paradigm ID |
| `byte(3)` | `&0x4` | Plural flag (noun) |
| `byte(4)` | `&~0x80` | Paradigm ID (noun declension or verb conjugation pattern) |
| `bytes(5+)` | — | Additional stems (e.g. perfective verb stem at byte 6+) |

### Key Access Patterns in `compiler.lua`

```lua
-- Noun gender
e.gender = compiler.base[word]:byte(3) & 3

-- Noun paradigm ID
paradigm_id = compiler.base[word]:byte(4) & ~0x80

-- Verb aspect
is_perfective = compiler.base[word]:byte(2) & 2

-- Adjective paradigm selection
if compiler.base[word]:byte(2) == 0x80 then
  paradigm_id = compiler.base[word]:byte(3)
else
  paradigm_id = compiler.base[word]:byte(4)
end
```

### Gender Values

`byte(3)&3` from `BASE.RUS` entry:
- 0 = male
- 1 = female
- 2 = neutral

### Paradigm ID Selection

For nouns: always `byte(4)&~0x80`

For adjectives: depends on `byte(2)`:
- If `byte(2) == 0x80`: paradigm ID is in `byte(3)`
- Otherwise: paradigm ID is in `byte(4)`

The `adj()` function in compiler.lua also falls back to `find_adjective()` which
matches the adjective's ending against known male adjective forms to determine
the paradigm.

<!-- TODO: Document full byte layout of BASE.RUS entries.
     Verify byte(3) gender values — are 0/1/2/3 mapped correctly?
     Understand the adjective paradigm selection logic (byte(2)==0x80).
     Document the extra stem bytes (5+) for verbs with different perfective forms. -->

## Data Files

| File | Format | Content |
|------|--------|---------|
| `LTGOLD.EXE` | DOS MZ EXE | Original translator binary |
| `BASE.DIC` | CP866 `word*codes` | English dictionary |
| `BASE.RUS` | CP866 `word*codes` | Russian dictionary |
| `BUSINESS.DIC` | CP866 `word*codes` | Business terminology |
| `COMPUTER.DIC` | CP866 `word*codes` | Computer terminology |
| `ERPREFIX.PRE` | Binary | Prefix rules |
| `LTGOLD.dat` | Binary | Extracted data section |
| `morph.txt` | UTF-8 | Morphological suffix data (872 lines) |
| `dic.txt` | UTF-8 | SARMA DIC format documentation (Russian) |

## Encoding

**CP866** (DOS Cyrillic) is used throughout. The translation engine stores all
grammatical tags and dictionary entries as raw CP866 bytes internally. UTF-8
conversion is only done for display via `utils.decode()`.

Key CP866 ranges:
- `0x80-0x9F` — А-Я (uppercase)
- `0xA0-0xAF` — а-п (lowercase first half)
- `0xE0-0xEF` — р-я (lowercase second half)
- `0xF0` — ё
