# Architecture

`init.lua` is the command-line shell; `core.engine` is the single translation API.
The engine loads original assets, creates fresh Lua state and invokes the stages:

```text
UTF-8 → CP866 → lexical lookup → grammar → phrasing → reorder
    → senses → constituents/agreement → syntax → Russian generation
    → output → UTF-8
```

Every stage operates on linked Lua records and owned strings. Auxiliary records
retain ordinary table identity. Constituents hold record lists and a separate
tag cache. Stage scheduling remains explicit because cached and live tags can
intentionally differ. There is no emulated address space, DOS heap, far-pointer
arithmetic, node serialization or shared string scratch buffer.

`assets` serves LTPRO's rule and morphology tables from `core/rules.lua`, extracted from the original EXE.
`russian` indexes immutable BASE.RUS entries. Word records use named properties such as `source`, `reading`, `tense`, `person`,
`gender`, `case_mask`, and `verb_flags`. `record_layout` maps native offsets at
fixture and packed dictionary decoding boundaries. Uninterpreted captured bytes
remain available to the research tools; production grammar uses named fields.

Phrasing selectors dispatch to Lua functions. Their return values describe the
scheduler action (`replace`, `stop_rule`, `advance_past_match`, and so on), while
the scheduler owns traversal and cache refresh. Syntax uses `nil` for missing
records and keeps its working frame between selectors. Constituent construction
compares literal tag letters; the matcher boundary retains numeric tag storage.
`grammar_values` names the recovered case masks, tenses, aspects, and known flags.

See [pipeline and module ownership](docs/pipeline.md), [dictionary formats](docs/dictionary.md),
[morphology](docs/paradigms.md), [rule semantics](docs/rules.md), and [verification](TESTING.md).

Keep runtime dependencies limited to Lua. Preserve rule order, CP866 text,
linguistic state, and captured output. Differential probes compare those results;
DOS allocation addresses and dead-buffer writes are not part of the Lua API.
