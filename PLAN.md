# Translator development

The duplicate parser/compiler, custom overlay path, byte-memory runtime and DOS
heap emulation have been retired. The single engine lives in `core/` and uses
Lua records and strings throughout; see [the pipeline](docs/pipeline.md).

Further work should address the remaining lexical gaps: unsupported suffix
derivations, macros and inline directives. Preserve rule order and explicit
cache refreshes, and verify changes against native morphology and captured
sentence outputs.

Historical porting work and original addresses remain under `reference/`.
