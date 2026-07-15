# Sentence Parsing Comparison: LTPRO.EXE vs Lua Port

## Overview

This document compares how LTPRO.EXE and the Lua port parse English sentences into tokens, match them to dictionary entries, handle multi-word phrases (W-tokens), and process complex grammatical constructions.

---

## 1. Input Processing

### LTPRO.EXE
```
Input: "She can speak Russian."
  ↓
Tokenization: Per-word, sequential
  ↓
Dictionary lookup: Per-entry, against loaded .DIC files
  ↓
Dictionary-code decode: Per-entry (`0xb0ff`)
  ↓
Sentence rules: T1-T8 over the assembled token buffer
  ↓
Output: Russian tokens
```

### Lua Port
```
Input: "She can speak Russian."
  ↓
Tokenization: Sequential, with phrase backtracking
  ↓
Dictionary lookup: Per-word, with phrase extension
  ↓
Entry metadata decode: Immediate per token
  ↓
Rule application: Per-sentence, T1-T8 tables
  ↓
Output: Russian tokens
```

**Corrected finding:** LTPRO decodes each dictionary entry immediately, but
`0xb0ff` is not the T1-T8 engine. It populates fields on the current token node.
The T1-T8 dispatchers operate later on a token buffer and therefore retain
sentence context, as Lua does.

---

## 2. Token Structure

### LTPRO.EXE Token (~0x90 bytes)
| Offset | Size | Field | Purpose |
|--------|------|-------|---------|
| +0x00 | 2 | next_ptr | Pointer to next token |
| +0x02 | 2 | prev_ptr | Pointer to previous token |
| +0x0c | 1 | POS tag | Primary grammatical tag (N,V,E,G,A,T,X,Y,U,R,M,Z,I,P,J,L,D,F,B,K,C,W) |
| +0x0f | 1 | status | Word form marker (0x77='w', 0x3d='=', 0x25='%') |
| +0x12 | 1 | secondary | Secondary modifier (context-dependent) |
| +0x66 | 1 | derived_tag | Derived form tag from dictionary |
| +0x72 | 1 | context | Context byte (set by rule engine flags) |
| +0x74 | 1 | secondary_type | Secondary type (compared to K=0x4b) |
| +0x77 | 1 | constituent_flags | Constituent type (0x01=numNP, 0x02=PP, 0x06=NP) |
| +0x87 | 2 | paradigm_offset | Offset to paradigm data |

**Key:** Tokens are linked-list nodes, each ~0x90 bytes, allocated per-entry.

### Lua Token (string)
```lua
-- Token is a packed string: "TAG[numbers]русский"
-- Examples:
"Z001"           -- Z-tag (ambiguous V/N/A)
"N003дом"         -- Noun with Russian lemma
"V007говорить"    -- Verb with Russian lemma
"WV003говорить"   -- W-phrase with verb head
"WAэлектронныйNперевод"  -- W-phrase: adjective + noun
```

**Key:** Tokens are strings with embedded grammatical codes and Russian lemmas.

---

## 3. Dictionary Lookup

### LTPRO.EXE

**Loading:**
1. Open .DIC file via C runtime `fopen()` (0xce3e)
2. Read lines via `dos_read_line()` (0xbd35)
3. Find `*` separator via `strchr()` (0xbe20)
4. Extract tag (char after `*`) and convert to uppercase (0xbe40)
5. Store tag at token+0x66 (derived tag) and token+0x0c (POS tag)
6. Call dictionary-code decoder (0xb0ff) to populate token fields

**Format:** `word*TAG русский текст`
- Example: `speak*Vговорить`
- Multiple meanings: `economy*Nэкономика;экономия`

**W-phrase handling:**
- If tag == 'W' (0x57), jump to W-phrase handler (0xc034)
- W-phrases are stored as opaque strings: `WAэлектронныйNперевод`
- The `is()` function matches W-tokens against ANY class letter

### Lua Port

**Loading (`load.lua`):**
1. Split line on `*` separator
2. Build nested table structure:
   ```lua
   en_ru["word"].__lex = "Z001N"  -- packed grammatical tags
   en_ru["turn"]["off"].__lex = "Z..."  -- multi-word entry
   ```

**Tokenization (`utils.tokenize()`):**
1. Split input on word boundaries + punctuation
2. Look up each word in dictionary
3. For single-word matches: return packed grammatical code
4. For multi-word phrases: try extending match (backtracking)
5. Unrecognized words: prefix with `#` (e.g., `#unknown`)

**Phrase handling:**
```lua
-- Try longest match first
if prev[word].__lex then
  -- Phrase complete: replace token with phrase entry
  tbl[#tbl] = prev[word].__lex
  prev = prev[word]  -- keep for potential extension
else
  -- Phrase break: backtrack to last valid position
  i, prev = last, nil
end
```

---

## 4. W-Phrase Tokens

### LTPRO.EXE

**Creation:** W-phrases are stored in the dictionary as `W`-tagged entries:
```
front door*NNWAпередняяNдверь
```

**Structure:** `W` + sequence of `TAG Russian` pairs:
- `WAэлектронныйNперевод` = adjective "электронный" + noun "перевод"
- `WVговоритьNречь` = verb "говорить" + noun "речь"

**Special behavior:**
- `is()` function matches W-tokens against ANY class letter (case-insensitive)
- T3 inserts W markers for participial phrases: "being" → W
- T6 reorders within W-constituents: ANW → 33, NNW → 2, NW → 3

### Lua Port

**Storage:** W-phrases are stored as opaque strings in token stream:
```lua
-- After dictionary lookup:
"WAэлектронныйNперевод"  -- single token
```

**Matching:**
```lua
local function tag_matches(t, class)
  if t:sub(1,1) == 'W' then
    -- W-tokens: case-insensitive match against any char in class
    local upper = t:upper()
    for i = 1, #class do
      if upper:find(class:sub(i,i), 1, true) then return t end
    end
    return nil
  end
  -- Non-W: case-sensitive check on leading character only
  ...
end
```

**Key behavior:** Both implementations retain W as an opaque lexical entry for
matching. Lua expands it only before compilation; LTPRO exposes its embedded
classes through its W-aware matching paths.

---

## 5. Complex Cases

### Case 1: Multi-Word Phrases

**LTPRO.EXE:**
- Dictionary entries with spaces: `turn off*Vвыключать`
- `dict_entry_parse` handles multi-word keys via nested lookup
- W-tag marks phrase boundaries

**Lua Port:**
- Nested table structure: `en_ru["turn"]["off"].__lex`
- Backtracking algorithm finds longest match
- Phrase metadata tracked in `tokens.phrases[]`

### Case 2: Z-Ambiguity Resolution

**LTPRO.EXE:**
- Z = unresolved V/N/A ambiguity
- T1 resolves Z based on context:
  - `*Z[?#]*` → no resolution (only unknowns)
  - `*~<UVXY>Z*` → guard (Z after non-verb)
  - `*VX` → resolve to N
  - `*Z:` → resolve to N
  - `*Ze` → resolve to NN

**Lua Port:**
- Same rules applied via `apply_rule_sets()`
- `find_and_replace()` handles Z resolution:
  ```lua
  if z and string.find('VNA', s) then
    local pos = ts[j]:find(s, 2, true)
    if pos then
      ts[j] = ts[j]:sub(pos)  -- extract specific form
    end
  end
  ```

### Case 3: Passive Voice

**LTPRO.EXE:**
- T2 handles passive constructions:
  - `*VX~<VXUY>B` → passive voice marker
  - `*~<RQJUVXYB,C>[yVUXY]` → auxiliary chain

**Lua Port:**
- Same rules in T2 section
- Compiler handles passive aspect via paradigm lookup

### Case 4: Clause Boundaries

**LTPRO.EXE:**
- T1 injects J (subordinator) and j (end-of-clause):
  - `*<dD,>B<dD>[VZ]<$>,` → J injection
  - `*<dD,>`if`~<,>`then` → J$j injection

**Lua Port:**
- Same rules applied
- J and j tokens mark clause boundaries for the compiler

---

## 6. Token Pipeline Comparison

### LTPRO.EXE Pipeline
```
1. Tokenize input word-by-word
2. For each word:
   a. Look up in dictionary
   b. Create token structure (~0x90 bytes)
   c. Store tag at +0x0c and +0x66
   d. Decode dictionary codes into the token node via 0xb0ff
3. Build/maintain the linked token buffer
4. Run T1-T8 against that buffer
5. Compiler processes tokens for output
```

### Lua Pipeline
```
1. Tokenize sequentially:
   a. Split on word boundaries
   b. Look up each word in dictionary
   c. Try phrase extension (backtracking)
   d. Create packed lexemes plus structured LTPRO-style node metadata
2. Apply preprocessors:
   a. Remove silent tokens
   b. Normalize analyzer tags (h→E1)
   c. Resolve attributive forms
3. Apply rule sets (T1-T8):
   a. For each rule in set:
      - Try pattern match at every position
      - On match: apply replacement
4. Post-process:
   a. Resolve post-rule contexts
   b. Remove silent tokens
5. Compiler processes tokens for output
```

---

## 7. Key Differences Summary

| Aspect | LTPRO.EXE | Lua Port |
|--------|-----------|----------|
| **Execution scope** | Per-entry code decode; sentence-level T1-T8 | Per-entry metadata decode; sentence-level T1-T8 |
| **Token structure** | Linked-list nodes (~0x90 bytes) | Packed lexemes plus linked structured metadata |
| **Dictionary format** | `word*TAG русский` | Nested Lua tables |
| **Phrase handling** | W-tag markers | Backtracking algorithm |
| **Rule application** | Entry codes immediate; T1-T8 over token buffer | Entry metadata immediate; T1-T8 over token stream |
| **Pattern matching** | Single-pass, left-to-right | All positions, left-to-right |
| **W-phrase matching** | Case-insensitive, any class | Case-insensitive, any class |
| **Z-resolution** | Context-dependent in T1 | Context-dependent in T1 |
| **Token metadata** | Embedded in structure | Parallel arrays |

---

## 8. Recommendations for Parity

1. **Per-entry decoding:** Keep dictionary-code decoding separate from T1-T8
2. **W-phrase matching:** Preserve opaque W entries and their embedded-class view
3. **Token structure:** Extend the structured metadata as remaining binary fields are decoded
4. **Phrase backtracking:** Verify Lua's backtracking matches LTPRO.EXE's behavior
5. **Z-resolution timing:** Ensure Z-resolution happens at the same pipeline stage
