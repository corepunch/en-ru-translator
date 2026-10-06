# Native stage implementation — 2026-10-06

The independent Lua path now reconstructs the two planned lexical examples and
executes native T1 scheduling over captured nodes. Full translation parity is
still incomplete: production paragraph matches improved from **29/77 to 44/77**;
33 differences remain. Full output-file formatting is not yet implemented in Lua.

## Executable evidence

`tools/ltpro_trace.py` instruments disposable copies of the frozen LTPRO image.
It uses the installed DOSBox-X and patches four verified instruction sequences:

| File address | Boundary | Displaced instructions |
|---|---|---|
| `11C1B` | Lexical vector constructed, before T1 normalization | Save AX as count; initialize DI |
| `11D5F` | T1 rule matched, before dispatch | Save selector; initialize selector search |
| `1254A` | T1 and question preprocessing finished | Initialize T2 table pointer |
| `13700` | T2 finished | Initialize T3 table pointer |

The hook preserves flags, general registers, DS and ES. It dumps the vector,
cached tags, each record's first `282h` bytes, and selected T1 rule/selector/endpoint.
Original assets stay untouched; copied assets are checked after execution.
The manifest retains raw bytes and normalizes node identity by physical address,
including aliases and identity across boundaries.

All **77 complete output files** equal the original oracle bytes on **both runs**.
Known semantic fields and match events repeat. Uninitialized bytes in sentinel
records remain in the raw captures but are not labeled semantic state.

There are **77 sentence-stage fixtures** from 76 files entering this grammar
entry. `He said: "Go."` enters twice. `ABC-123.` bypasses it. `Stop.` takes a native
early return, so no T1/T2 boundary is reached. These observations must remain
part of later document scheduling, rather than being treated as missing captures.

An initial append-only hook failed on longer inputs. Disassembly of C startup
`03A81..03AA1` showed that it resizes its DOS memory block to SS plus stack size,
ignoring the appended image length. The disposable copy now places its stack
above the hook, keeping that memory allocated. After this correction every oracle
output passes. No change to the source executable was needed.

## Lua implementation and verification

| Module | Behavior | Evidence and limits |
|---|---|---|
| `core/ltpro/dictionary.lua` | Lossless record ingestion, ordered duplicates, original bytes | Byte-preservation checks; native lookup/duplicate policy is still separate |
| `core/ltpro/readings.lua` | Metadata field writes, numeric prefixes, case masks, tag normalization, translated readings | **1,377/1,377** original-instruction comparisons; unknown-word decoding and lexical macros reject explicitly |
| `core/ltpro/lexical.lua` | Exact-word dictionary/node slice with native metadata and links | **2/2** planned native lexical snapshots; tokenization, multiword lookup, annotations, unknowns and derived searches remain incomplete |
| `core/ltpro/nodes.lua` | Raw record import, physical pointer identity, linked records and null-parent boundary construction | Alias/invalid-link checks and native calloc-constructor fixtures; records retain unnamed bytes |
| `core/ltpro/first_pass.lua` | T1 normalization, rule order, handler writes, cache rebuilds and early termination | **77/77** DOS sentence-stage fixtures and **36/36** native rule-selection events, including intermediate fields |
| `core/ltpro/cleanup.lua` | Cleanup used by question preprocessing | Verified within the captured T1 question paths; only selectors appearing in the nine extracted records are implemented |

T1 has 15 extracted selector entries plus its default. All bodies are implemented.
The unchanged grammar corpus observes **0, 1, 10, 11, 20 and 63**. An additional
**648/648** generated-node instruction fixtures exercise all selector bodies:
576 use the unchanged table, and 72 isolate records that earlier rules mask.
Selector 8 has no supplied T1 record; 12 of those fixtures select it synthetically
and establish local instruction behavior, not English-input reachability.

Selector 12 runs the original `0687:0812` boundary constructor (`0AA82..0AB01`)
in the harness. Only its C calloc primitive is substituted. The Lua port preserves
the 15h-byte zeroed record's tag, marker, type and source string; inserts it into
the native link position; uses the old vector for remaining edits; then rebuilds.
Fixtures cover allocation success, calloc failure and the native count limit.
The wider allocator lifecycle and non-null-parent constructor path are still
unported. The question
tests cover `Who saw the dog?` and `What is this?`, not every question branch.
These passing fixtures do not establish all-input equivalence.

`reference/LTPRO_ROUTINE_LEDGER.json` inventories **410 selectors**, their aliases,
grammar references, defaults and **282 distinct target addresses**. It also lists
called routines and candidate ES-relative field accesses from bounded local CFG
walks. These candidates still need pointer/context validation. The ledger does
not classify unobserved targets as unreachable or count aliases as separate ports.

## First divergence in the planned examples

`He is in the house.` enters native grammar as `*RXPTN*`. T1 preserves that cache.
Native word records hold source spelling, current and previous tags, numeric
metadata, and a separate translated string. The exact-word slice reproduces all
checked initialized word fields, strings and positions for this input. Its final
paragraph already matched before this work.

`If he comes then I go.` enters native grammar as `*JRVDRV*`. Native `comes` has
current tag V, previous tag V, person 3 and case mask 8. The legacy tokenizer
instead retains a packed lowercase `v...\\come` reading; it has no corresponding
native field/cache representation. That is the earliest representation divergence.

The decisive T1 event is record **27**, selector **0**, endpoint **4**. It changes
`then` from D to j and saves D as the previous tag. Crucially, the translated field
remains `затемCзатемJзатемjтогда`. The legacy parser reduced every j replacement
to a bare `j`, and the compiler made every j silent. Its observable divergence
therefore occurs in T1: it erases a real lexical reading.

The production correction preserves an existing j reading and emits its text;
bare structural j markers still produce an empty string. It uses dictionary/rule
data, without a sentence-specific exception. This correction gained case 052.

Native output and corrected Lua output are now both:

> Если он приходит тогда Я иду.

## Capitalization correction

The compiler discarded `init` capitalization metadata already produced by the
analyzer and parser, and capitalized lowercase sentence inputs unconditionally.
It now consumes that metadata and retains lowercase input. W phrase expansion
copies the phrase capitalization to its constituents, as seen in native
`"Fish meal"` → `"Рыбная Мука"`. The future copula receives the source pronoun's
capitalization, preserving `It will` → `Это Будет` and lowercase `it will` →
`это будет`.

This gained **14** frozen-corpus matches; together with the j correction the
score is **44/77**, with no regressions among the initial 29 passing cases.
`capitalization-reference.json` contains **16** additional lowercase, initial-cap,
all-cap, phrase, article and copula inputs, with identical raw files in two native
runs. Lua matches **16/16** paragraphs. The demo's 13 former preferred-style casing
expectations were replaced with the frozen executable's observed casing; **25/25**
demo regressions pass. Its dictionaries remain distinct from the frozen oracle.

## Reproduce

```sh
python3 tools/ltpro_trace.py --ids --output test/ltpro/stages.json
python3 tools/ltpro_first_pass_probe.py
python3 tools/ltpro_first_pass_native_probe.py
python3 tools/ltpro_lexical_probe.py
python3 tools/ltpro_readings_probe.py
python3 tools/ltpro_ledger.py
python3 tools/ltpro_compare.py --report test/ltpro/comparison.json
python3 tools/ltpro_compare.py --cases test/ltpro/capitalization-cases.json --reference test/ltpro/capitalization-reference.json
lua test/ltpro_stages_test.lua
```

The full comparison intentionally exits 1 while 33 differences remain. The
standard test runner still fails its previously known preferred cat/mat assertion;
that expectation and the oracle have not been rewritten to conceal the mismatch.

## Remaining work and planning implications

The method now has measured results: full-DOS field snapshots, original instruction
comparisons and the independent Lua slice agree. The next dependency is complete
native lookup/analyzer state, followed by T2/T3/T4 callers and constituent creation.
Most lexical and later-handler branches, generation callers, global allocation
state, document lifecycle and full-file output remain open.

Keep the existing multi-week planning assessment. These measurements do not
justify a tighter delivery range: T1 corpus coverage reached six selectors, while
T2/T3/T4 and T7/T8 contain many more unresolved state transitions. The static ledger
is an inventory rather than a completed writer/reader map. Phase 1's observability
and initial slice are delivered; its full semantic mapping gate remains open.
