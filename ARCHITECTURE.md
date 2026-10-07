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

`assets` decodes read-only rule and morphology tables from the original EXE.
`russian` indexes immutable BASE.RUS entries. Numeric record keys remain field
identifiers shared with the earlier grammar code; they do not address memory.
Native capture decoding lives in the research tools.

See [pipeline and module ownership](docs/pipeline.md), [dictionary formats](docs/dictionary.md),
[morphology](docs/paradigms.md), [rule semantics](docs/rules.md), and [verification](TESTING.md).

Keep runtime dependencies limited to Lua. Preserve rule order, CP866 text,
linguistic state, and captured output. Differential probes compare those results;
DOS allocation addresses and dead-buffer writes are not part of the Lua API.
