# Translator development

The duplicate parser/compiler and custom overlay path have been retired. The
single engine lives in `core/`, grouped by function; see [the pipeline](docs/pipeline.md).

Further reduction should preserve native evidence while addressing the remaining
lexical gaps: unsupported suffix derivations, macros and inline directives.
Memory-backed stages still depend on pointer identity and shared buffers. Migrate
those only with differential tests covering the affected writes and scheduling.

Historical porting work and original addresses remain under `reference/`.
