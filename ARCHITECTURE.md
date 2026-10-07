# Architecture

`init.lua` is the command-line shell; `core.engine` is the single translation API.
The engine loads original assets, creates fresh state and invokes the stages:

```text
UTF-8 → CP866 → lexical lookup → grammar → phrasing → reorder
    → serialize nodes → senses → constituents/agreement → syntax
    → Russian generation → output → UTF-8
```

Modules return tables of functions. Grammar operates on ordinary linked Lua
tables; later stages use the byte memory model where aliasing, string mutation
and wrapped far pointers affect observable results. `matching` shares one pattern
interpreter across table and memory representations. Stage scheduling remains
explicit because cached tags and live tags can intentionally differ.

See [pipeline and module ownership](docs/pipeline.md), [dictionary formats](docs/dictionary.md),
[morphology](docs/paradigms.md), [rule semantics](docs/rules.md), and [verification](TESTING.md).

Keep runtime dependencies limited to Lua. Preserve rule order and CP866 byte
semantics. Use native differential probes when changing pointer, buffer, cache
or scheduling behavior; successful extraction alone does not prove equivalence.
