# Case Study: Translating Zork — Adventure Game Text

This document walks through improving the translator for adventure game text, using the opening
sentences of Zork as a concrete example. It shows how to identify problems, add vocabulary,
and add rules — and serves as a template for future domain-specific improvements.

## The sentences

```
You are standing in an open field west of a white house, with a boarded front door.
There is a small mailbox here.
```

These are the first two sentences the player reads when Zork starts. They exercise many
translation challenges: compound nouns, directional phrases, existential constructions,
and adjective agreement.

---

## Step 1: Baseline (before any changes)

```sh
lua init.lua "You are standing in an open field west of a white house, with a boarded front door."
lua init.lua "There is a small mailbox here."
```

**Output:**
```
Вы стоите в западе запада открытого белого дома, с обшитей передней дверью{1.вход}.
Есть небольшой почтовый ящик здесь.
```

---

## Step 2: Problem analysis

### Sentence 1 problems

| Fragment | Output | Expected | Root cause |
|----------|--------|----------|------------|
| `field` | область | поле | BASE.DIC entry for *field* = "область" (abstract field/domain); adventure game needs "поле" (open meadow) |
| `west of a white house` | западе запада ... белого | к западу от белого дома | *west* has tag N+A+D — the T5 `ANN` reorder rule fires on (open, field, west), duplicating *west*. Then *of* (preposition Р) governs genitive but *west* as N+D doesn't pass case down. |
| `with a boarded front door` | с обшитей передней дверью | с заколоченной передней дверью | (1) "обшитый досками" is a multi-word adjective token; `paradigms.adjective` strips 2 bytes for stem but multi-word form has wrong stem boundary. (2) `find_adjective` returns a 1-based index where a 0-based index is expected — off-by-one means the wrong paradigm table is selected, giving "-ей" instead of "-ой". |

### Sentence 2 problems

| Fragment | Output | Expected | Root cause |
|----------|--------|----------|------------|
| Word order | Есть ... здесь | Здесь есть ... | The existential rule (`*~<RQJUVXYB,C>[yVUXY]`) moves "There is" → `y` but leaves the locative adverb (*here*) at the end. Russian prefers locative-first in presentative sentences. |

---

## Step 3: Fixes applied

### 3a. New vocabulary — `data/DUNGEON.DIC`

A domain-specific overlay dictionary loaded with `--dict=data/DUNGEON.DIC`. It is read
after `BASE.DIC`; entries with the same key override the base dictionary.

**Key entries for these sentences:**

```
# Override: correct translation for open field
field*Nполе

# Override: directional phrases with explicit genitive case
# Format: P (preposition) + Р (genitive case) + surface text
# This makes the following NP ("white house") inflect in the genitive.
west of*PРк западу от

# Override: boarded — replace multi-word adjective with single inflectable form
boarded*Aзаколоченный

# Compound noun — LTGOLD NNW phrase format (NNW normalised to W by loader)
front door*NNWAпередняяNдверь
```

**Compass directions** (plain adverb D-tag, no case government):
```
north*Dна севере
south*Dна юге
east*Dна востоке
west*Dна западе
```

**Directional phrases** (preposition P-tag, governs genitive):
```
north of*PРк северу от
south of*PРк югу от
east of*PРк востоку от
west of*PРк западу от
```

### 3b. Word-order rule — existential locative sentences

Added to the cleanup block in `core/rules.lua` (after T6):

```lua
-- "There is [NP] here" → "Здесь есть [NP]"
-- Digit actions move the locative adverb (D) from the last position to first.
-- Three rules cover NP with 0, 1, or 2 pre-noun adjectives.
{ 0x00, "yTAAND", "612345" },   -- y T A A N D → D y T A A N
{ 0x00, "yTAND",  "51234"  },   -- y T A N D   → D y T A N
{ 0x00, "yTND",   "4123"   },   -- y T N D     → D y T N
```

The digit action string `"51234"` means: at matched positions [1..5], write
snap[5] first, then snap[1], snap[2], snap[3], snap[4] — i.e., move the last token
to the front.

> **Pattern caveat:** These rules use the T5/T6 digit-reorder mechanism. The `*` boundary
> anchor cannot be combined with a digit action (the action reader asserts `@` when it
> encounters `*`, crashing on any other char). Use specific tag sequences without anchors.

### 3c. Adjective paradigm bug fix — `core/paradigms.lua`

`find_adjective()` returned a 1-based Lua array index, but `paradigms.adjective()` treats
the return value as a 0-based table ID (it adds 1 internally). The off-by-one caused every
adjective not in `BASE.RUS` to select the wrong declension table, producing wrong soft-stem
endings ("-ей" instead of "-ой") for hard adjectives like *заколоченный*, *белый*, *открытый*.

```lua
-- Before (returns Lua 1-based index — wrong):
if t and adj:sub(-#w) == w then return i end

-- After (returns 0-based table_id — correct):
if t and adj:sub(-#w) == w then return i - 1 end
```

This is a general correctness fix that improves adjective inflection for all adjectives
whose base form is not in `BASE.RUS`.

---

## Step 4: Result

```sh
lua init.lua "You are standing in an open field west of a white house, with a boarded front door." \
  --dict=data/DUNGEON.DIC
lua init.lua "There is a small mailbox here." --dict=data/DUNGEON.DIC
```

**Output:**
```
Вы стоите в открытом поле к западу от белого дома, с заколоченной передней дверью.
здесь Есть небольшой почтовый ящик.
```

### What improved

| Before | After |
|--------|-------|
| западе запада открытого белого дома | к западу от белого дома |
| обшитей | заколоченной |
| область | поле |
| Есть ... здесь | здесь Есть ... |

### Known remaining issues

| Issue | Cause | Notes |
|-------|-------|-------|
| "здесь Есть" (wrong caps) | After word-order reorder, the source-word capitalization flag travels with the `y` token (from "There"), not with the new first token (D/здесь). | A compiler fix would need to normalize first-word capitalization after reordering. |
| "к западу от" doesn't move adjectives before the noun | The `ANN` T5 reorder rule can still fire on adjacent A+N+N patterns elsewhere in the sentence. | With `west of` absorbed as a phrase entry, the doubling is fixed for this sentence specifically. |

---

## How to add more vocabulary

1. Open `data/DUNGEON.DIC` (or create a new overlay file).
2. Add entries in the format `english_word*CODE` (UTF-8 is fine; the loader re-encodes to CP866).
3. Load with `--dict=data/DUNGEON.DIC`.

**Simple noun:**
```
tower*Nбашня
```

**Override an existing wrong translation:**
```
field*Nполе    # replaces BASE.DIC "область"
```

**Multi-word phrase:**
```
trap door*Nлюк
```

**Compound noun in LTGOLD W-format** (both adj and noun head inflect correctly):
```
front door*NNWAпередняяNдверь
```

**Directional preposition phrase** (governs genitive case):
```
east of*PРк востоку от
```

For tag codes and the full format spec, see [docs/dictionary.md](dictionary.md).

---

## How to add a rule

1. Open `core/rules.lua`.
2. Find the appropriate pass block:
   - **T1–T4** (`table.insert(rules, {...})` blocks 1–4): tag rewrites
   - **T6 cleanup** (block after T5): sentence-level transforms, existential fixes
   - **T5–T6** (blocks 5–6): word-order reordering (digit actions)
3. Add a `{ flags, "PATTERN", "REPLACEMENT" }` line.

**Example — suppress the article before unknown words:**
```lua
{ 0x00, "T#", " ." },   -- article + unknown word: suppress article, keep unknown
```

**Example — existential word-order reorder:**
```lua
{ 0x00, "yTND", "4123" },   -- y T N D → D y T N  ("Здесь есть ящик")
```

For the full pattern and replacement syntax, see [docs/rules.md](rules.md).
