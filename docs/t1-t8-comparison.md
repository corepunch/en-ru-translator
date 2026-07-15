# T1-T8 Pipeline Comparison: LTPRO.EXE vs Lua Port

## Execution Flow

### LTPRO.EXE (Binary)
```
main_translate (0xcd5c)
  ├─ dict_read_loop → dict_entry_parse → dictionary-code decoder (0xb0ff)
  └─ After token-buffer assembly:
            ├─ T1 dispatch (0xe1f9) → pattern matcher (0xa67)
            ├─ T2 dispatch (0xeb4d) → pattern matcher (0xa67)
            ├─ T3 dispatch (0xfd03) → pattern matcher (0xa67)
            ├─ T4 dispatch (unknown) → pattern matcher (0xa67)
            ├─ T5 dispatch (0x127cb) → filtered matcher (0x1313:0x7fd)
            ├─ T6 records → filtered matcher (0x1313:0x7fd)
            ├─ T7 dispatch (0x144d1) → pattern matcher (0xa67)
            └─ T8 dispatch (0x1987f) → morph matcher (0x1c3d:0x135)
```

**Key:** `0xb0ff` processes each dictionary entry immediately, but it is not the
T1-T8 engine. It decodes grammatical code bytes into the current token node.
T1-T8 operate on the assembled token buffer and therefore see sentence context.

### Lua Port
```
init.lua
  └─ parser.loop(ts)
       ├─ remove_silent_tokens(ts)
       ├─ normalize_analyzer_tags(ts)
       ├─ resolve_attributive_forms(ts)
       ├─ apply_rule_sets(ts)  ← ALL tables run here
       │    └─ For each rule set (T1-T8):
       │         ├─ rule_set_preprocessors[ri](ts)  [if exists]
       │         └─ For each rule in set:
       │              └─ match_pattern(ts, pat, act, flags, ri)
       └─ resolve_post_rule_contexts(ts)
```

**Key:** Tables run ONCE PER SENTENCE, after all tokens are loaded.

## Execution-Scope Alignment

| Aspect | LTPRO.EXE | Lua Port |
|--------|-----------|----------|
| Entry-code decoding | Immediate per dictionary entry | Immediate metadata initialization per token |
| Table execution | Assembled token buffer | Assembled token stream |
| Pattern matching | Sentence context | Sentence context |

**Impact:** Z ambiguity must remain unresolved through dictionary decoding and be
resolved by T1 with surrounding-token context. Running T1-T8 on isolated entries
would diverge from the binary.

## Critical Difference #2: Pattern Matcher Architecture

### LTPRO.EXE Pattern Matcher (0x1313:0xa67)
- Interprets pattern bytes directly from table records
- Pattern data stored in data segment (file offset 0x26750+)
- Uses far pointers to table records (segment:offset)
- Returns match index (0 = no match, >0 = match position)
- Token buffer is a fixed-size array on the stack (0x842 bytes)

### Lua Pattern Matcher (parser.lua)
- `pattern_tokens()` iterator parses pattern strings
- `try_match_pattern()` walks token stream
- `match_pattern()` tries every starting position
- Returns boolean (match/no match)
- Token stream is a Lua table (dynamic size)

**Impact:** The Lua matcher is more flexible but may match differently due to:
- Different iteration order (all positions vs single pass)
- Different wildcard/boundary handling
- Different negation semantics

## Critical Difference #3: Action Execution

### LTPRO.EXE Actions
- T1-T4: Jump table dispatch based on flags (15/60/98 entries)
- T5-T6: Digit-action reordering (direct token manipulation)
- T7-T8: No actions (guard-only)

Actions are executed IMMEDIATELY after match, modifying the token stream in place.

### Lua Actions
- `find_and_replace()`: Updates grammatical tags on tokens
- `reorder_tokens()`: T5/T6 digit-action reordering
- `ts.constituent_flags[]`: T7/T8 flag storage

Actions are executed during the same pass, but the token stream is a Lua table.

**Impact:** The Lua port may apply actions in a different order due to:
- Multiple matches per rule (Lua tries all positions)
- Different token stream mutation semantics
- Constituent flag blocking logic

## Critical Difference #4: Table-Specific Behavior

### T1-T3: Standard Pattern Matching
| Aspect | LTPRO.EXE | Lua Port |
|--------|-----------|----------|
| Pattern matcher | 0xa67 (shared) | `try_match_pattern()` |
| Token preprocessing | Replaces `[]<>?` with `/` or `_` | None |
| Action dispatch | Jump table (flags-based) | Direct `find_and_replace()` |
| Match scope | Single pass, left-to-right | All positions, left-to-right |

### T4: Idioms/Cleanup
| Aspect | LTPRO.EXE | Lua Port |
|--------|-----------|----------|
| Record format | 9 bytes (1-byte flags) | Same as T1-T3 |
| Special handling | None documented | None implemented |

### T5-T6: Word-Order Reorder
| Aspect | LTPRO.EXE | Lua Port |
|--------|-----------|----------|
| Pattern matching | Filtered matcher (`0x1313:0x7fd`) | Dedicated filtered-tag matcher |
| Action type | Digit strings ("34", "4545") | Digit strings |
| Termination | Fixed count (T5) / sentinel (T6) | Sequential |
| Reorder mechanism | Direct token manipulation | `reorder_tokens()` |

**Impact:** T5-T6 do not call the standard matcher at `0x1313:0xa67`. The
dispatch filters analyzer records, calls the reorder-specific matcher at
`0x1313:0x7fd`, and applies digit actions directly. Lua now mirrors that
separation: it projects each token to its reorder tag (including the head of a
packed `W` entry), performs flat tag matching, and moves token metadata with the
matched constituents.

### T7-T8: Structural Guards
| Aspect | LTPRO.EXE | Lua Port |
|--------|-----------|----------|
| Actions | None (guard-only) | None (guard-only) |
| Flag storage | Token+0x77 (constituent flags) | `ts.constituent_flags[]` |
| T8 matcher | Morph segment (0x1c3d:0x135) | Standard pattern matcher |
| Blocking logic | Implicit (no action) | Explicit (same-table blocking) |

**Impact:** T8 in LTPRO.EXE uses a DIFFERENT pattern matcher (morph segment). The Lua port uses the standard matcher, which may cause different match behavior.

## Critical Difference #5: Preprocessors

### LTPRO.EXE
- T1: Replaces `[]<>` with `/`, `?` with `_` (token preprocessing)
- T5/T6: Filters analyzer records by secondary tag (`g`, `/`, `%`, `=`) before
  using the reorder matcher. Lua has no equivalent secondary analyzer field, so
  it uses the resolved tag/head projection available in its token stream.
- T8: Checks morph token structures

### Lua Port
- T1: Normalizes `[]<>` tags and conditionally maps `?` when `_` provenance is available
- T1: `rule_set_preprocessors[1]`: X003 copula before Z→A resolution
- T3: `rule_set_preprocessors[3]`: q+Z → V resolution
- T6: `rule_set_preprocessors[6]`: A-head resolution before reorder

**Impact:** The preprocessors are DIFFERENT. LTPRO.EXE does character-level preprocessing; the Lua port does semantic preprocessing.

## Summary of Differences

| Category | LTPRO.EXE | Lua Port | Impact |
|----------|-----------|----------|--------|
| Execution scope | Entry decode + token-buffer rules | Entry metadata + token-stream rules | Aligned stage boundary |
| T1 preprocessing | Character replacement | Character normalization + semantic resolution | Secondary analyzer fields remain incomplete |
| T5-T6 matching | Filtered reorder matcher | Filtered tag/head projection | Secondary analyzer fields remain unavailable |
| T8 matcher | Morph segment (0x1c3d) | Separate morph-tag projection | Compact binary morph fields remain unavailable |
| Action dispatch | Jump tables (flags) | Direct replacement | Same semantics |
| Guard blocking | Implicit | Explicit (same-table) | Same semantics |

## Recommendations for Parity

1. **Per-entry decoding:** Preserve immediate node-field initialization without moving T1-T8 out of sentence context
2. **T1 preprocessing:** Preserve the implemented analyzer-tag normalization and
   recover the binary's secondary `_` field if fuller unknown-token parity is needed.
3. **T5-T6 filtering:** Retain the dedicated filtered reorder path; add secondary
   analyzer fields if they are recovered from the binary.
4. **T8 matcher:** Extend the separate morph projection as compact-record field
   semantics are recovered; do not route T8 back through the standard matcher.
5. **Preprocessor alignment:** Align Lua preprocessors with LTPRO.EXE behavior
