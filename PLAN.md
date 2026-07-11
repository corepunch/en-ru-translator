# W Token Refactoring Plan

## Problem

W tokens (multi-word phrase markers) are packed as opaque strings (`WAэлектронныйNперевод`)
and passed through all 8 rule-set passes with no first-class structure. This forces scattered
workarounds across `utils.lua`, `parser.lua`, `token_stream.lua`, and `compiler.lua`.

### Fragility inventory

1. **`is()` full-string scan** (`parser.lua:30`): checks `word:upper():find(tag_char)` to
   determine the primary tag of a W token. Works only because CP866 Cyrillic bytes (0x80–0xFF)
   never match ASCII — an accidental invariant.

2. **`iter()` can't see sub-constituents** of W tokens: `%a+` in its gmatch swallows `W` + the
   following tag letter together as `WA`, so `find(tok, 'A')` returns nil. The `A` constituent
   is invisible to rule matching.

3. **`expand_phrase_tokens()` gmatch pattern** (`parser.lua:550`):
   `([%a ][0-9]*[\127-\255]+)` — relies on `W` having no CP866 chars after it. The space in
   `[%a ]` was added as a hack for multi-word Russian (e.g. `WNспособность погашать`).

4. **`phrases=true` side-channel** (`token_stream.lua:4`): a boolean flag on expanded tokens,
   consumed only by `compiler.lua:127` for one specific behavior (nounless-phrase adj → lemma
   form). Not a general mechanism.

5. **`component_caps`** (`utils.lua:257`): collected during tokenization, stored as metadata,
   consumed during expansion. Implicit contract between 3 files.

6. **Reorder suppression** (`parser.lua:378`): inline `ts[pos]:match("^WV")` check rather than
   a data-driven property of the W token.

7. **Caps propagation** (`parser.lua:514–537`): inline `ts[i]:sub(1,1) == 'W'` loop for
   LTGOLD-compatible "init" caps bleed across consecutive W phrases.

## Plan

### Step 1 — Add a proper W token parser (`utils.lua`)

Add `parse_W(token)` that splits the packed string into structured constituents:

```lua
{
  tag = "A",  -- primary constituent tag
  constituents = {
    { tag = "A", text = "<CP866>" },
    { tag = "N", text = "<CP866>" },
  }
}
```

The parser walks the string character by character: skip `W`, then alternate between
reading an ASCII tag letter and CP866 Cyrillic bytes. Embedded paradigm indices (e.g.
`N001`) are handled by consuming ASCII digits before the Cyrillic run.

**Property:** `parse_W(W)` always succeeds (W tokens are well-formed by dictionary
construction). Returns `nil` for non-W tokens.

**Tests:** `test/parser_test.lua` — assert constituent count, tags, and text for
`WAadjNnoun`, `WVverbPprep`, `WNnoun`, `WAadjNWnounNnoun` patterns.

**No regressions** — no existing code calls this new function yet.

---

### Step 2 — Replace `is()` full-string scan with parsed primary tag (`parser.lua:30-33`)

Change from:
```lua
if word:sub(1,1) == 'W' then
  if word:upper():find(class:sub(i,i)) then return true end
end
```
to:
```lua
if word:sub(1,1) == 'W' then
  local parsed = parse_W(word)
  if parsed and class:find(parsed.tag, 1, true) then return true end
end
```

Same semantics — checks only the first constituent's tag letter against the class.
Data-driven, no magic. Removes the accidental ASCII-only invariant.

**Tests:** existing `make test` — behavior is identical for all current dictionary entries.

---

### Step 3 — Use `parse_W()` in `expand_phrase_tokens()` (`parser.lua:540-570`)

Replace the gmatch loop:
```lua
for word in ts[i]:gmatch("([%a ][0-9]*[\127-\255]+)") do
```
with iteration over `parse_W(ts[i]).constituents`.

This eliminates the fragile pattern and the implicit invariant about `W` having no
CP866 trail. The `component_caps` metadata distribution and `phrases=true` assignment
remain unchanged in this step.

**Tests:** `make test` + `demo/compare.lua` — output must be byte-identical.

---

### Step 4 — Cache parsed W data in token stream (`token_stream.lua`)

Add a `ts.W_data` table (keyed by position) so `parse_W()` is called once per W token
rather than re-parsing on every access. Populated lazily on first `parse_W()` call.

**Tests:** `test/token_stream_test.lua` — verify W_data is populated on access and
cleared on stream mutations.

---

### Step 5 — Replace `phrases` side-channel with `phrase_index` (`token_stream.lua`, `compiler.lua`)

Instead of `phrases = true` on every expanded sub-constituent, set `phrase_index = N`
where `N` is the position in the stream of the original W token (0 = not from a phrase).
The A printer in `compiler.lua:127` checks `s.phrase_index` instead of `s.phrases`.

This makes the mechanism extensible — other printers can consult `phrase_index` for
phrase-aware behavior without new side-channels.

**Tests:** `make test` — nounless-phrase A adjectives must still emit lemma form.

---

### Step 6 — Generalize reorder suppression (`parser.lua:373-385`)

Replace the inline `ts[pos]:match("^WV")` with a helper:
```lua
local function is_W_verb_head(ts, pos)
  local parsed = parse_W(ts[pos])
  return parsed and parsed.tag == 'V'
end
```

Makes the suppression condition explicit instead of embedded in the application loop.
No behavior change.

**Tests:** `make test` — T5/T6 reorder must be suppressed for WV phrases exactly as before.

---

### Step 7 — Generalize caps propagation (`parser.lua:514-537`)

Replace the inline `ts[i]:sub(1,1) == 'W'` loop with a helper:
```lua
local function is_W_token(ts, pos)
  return ts[pos]:byte(1) == 0x57  -- 'W'
end
```

Minimal change — just moves the magic byte check to a named function for readability.
Future readers can find all W-token decisions by grepping `is_W_token`.

**Tests:** `make test` — "init" caps must still leak across consecutive W phrases.

## What NOT to change

- **Dictionary format** (`data/BASE.DIC`, `data/*.RUS`): keep packed strings, no schema change.
- **Rule format** (`core/rules.lua`): `@W`, `.$NW`, `[NW]` etc. stay as-is.
- **8-pass rule application** (`core/parser.lua`): the rule engine itself is untouched.
- **`iter()` / `find()` / `matches()`**: these are LTGOLD core and work correctly for
  non-W tokens. Only `is()` changes.

## Files affected (final)

| File | Changes |
|------|---------|
| `core/utils.lua` | Add `parse_W()` function |
| `core/parser.lua` | Steps 2, 3, 6, 7: `is()`, `expand_phrase_tokens()`, reorder guard, caps helper |
| `core/token_stream.lua` | Steps 4, 5: `W_data` cache, `phrase_index` field |
| `core/compiler.lua` | Step 5: A printer uses `phrase_index` instead of `phrases` |
| `test/parser_test.lua` | Add unit tests for `parse_W()` |

## Verification

Each step is independently testable:

```sh
make test                          # all existing tests must pass
lua test/parser_test.lua           # new parse_W unit tests
lua demo/compare.lua               # zero diff against DEMO_REFERENCE
lua demo/demo_walk.lua             # word-by-word N/M progress
lua init.lua --diag=tag            # verify tag resolution unchanged
```
