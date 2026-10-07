# Translator development

The duplicate parser/compiler, custom overlay path, byte-memory runtime and DOS
heap emulation have been retired. The single engine lives in `core/` and uses
Lua records and strings throughout; see [the pipeline](docs/pipeline.md).

## Issue #3: Lua feature completion

The completion contract is documented, tested translator features using Lua
records and strings. DOS memory operations, exact output parity, and unnamed
binary profile switches are not product features to emulate.

- [x] Generation and sentence output through one pipeline.
- [x] Optional meanings glossary through the API and CLI.
- [x] Adjective degrees, possessives, and surface derivational nouns.
- [x] Hyphen/slash compounds and intact bare-ending compounds.
- [x] Configurable ERPREFIX prefix derivation, including alternative readings.
- [x] Duplicate dictionary selection and redirects.
- [x] Lexical class word/annotation alternatives and span anchors.
- [x] Patterned phrase gaps, W selectors, and selectable phrase readings.
- [x] Protected/transliterated input spans and list-layout directives.
- [x] Subject-domain preferences through explicit options.
- [x] Feature documentation and full Lua/CLI regression coverage.

Run `sh test/run_all.sh`. Phrase inventory coverage checks 8,940 multiword W
inputs; it does not claim linguistic correctness for every phrase. See
`README.md` for the Lua-specific policies and `TESTING.md` for optional research
comparisons. Existing original captures remain unchanged.

Further work can improve translation quality and document additional linguistic
behavior independently of original executable addresses. Preserve rule ordering
and explicit cache refreshes when changing the existing grammar stages.

Historical porting work and original addresses remain under `reference/`.
