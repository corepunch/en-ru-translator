# Binary research notes

The previous prescribed disassembly workflow has been removed. There is no required
disassembler, decompiler, tool order, installation procedure, or fallback policy.

The current comparison target is the supplied unpacked `LTGOLD/LTPRO.EXE`.
See [the LTPRO comparison](reference/LTPRO_COMPARISON.md) for binary identity,
verified file offsets, implementation differences, and remaining questions.
Historical LTGOLD addresses in older notes are not LTPRO file offsets.

Consolidated addresses, frames, record fields, globals, switch tables and
harness pitfalls are in [the native map](reference/LTPRO_NATIVE_MAP.md).
`tools/ltpro_disasm.py` prints a range as a condensed listing with frame
names; `tools/ltpro_rawtrace.py` runs one input through the instrumented
image when changing hook sites.
