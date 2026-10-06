# Native stage implementation — 2026-10-06

The independent Lua path now reconstructs the two planned lexical examples and
executes native T1, T2, T3 and T4 scheduling over captured nodes. Full translation
parity is still incomplete: production paragraph matches improved from **29/77
to 44/77**; 33 differences remain. The production pipeline does not yet use the
native passes, because the native lexical analyzer is still a slice. Full
output-file formatting is not yet implemented in Lua.

## Executable evidence

`tools/ltpro_trace.py` instruments disposable copies of the frozen LTPRO image.
It uses the installed DOSBox-X and patches four verified instruction sequences:

| File address | Boundary | Displaced instructions |
|---|---|---|
| `11C1B` | Lexical vector constructed, before T1 normalization | Save AX as count; initialize DI |
| `11D5F` | T1 rule matched, before dispatch | Save selector; initialize selector search |
| `1254A` | T1 and question preprocessing finished | Initialize T2 table pointer |
| `13700` | T2 finished | Initialize T3 table pointer |
| `14168` | T3 rule-record test; dumps only when the next record is null, i.e. after the last T3 rule and its rebuild | Load rule pointer; read its pattern offset |
| `1607A` | T4 rule-record test in the separate `108F:000F` function (frame offset adjusted by -6); dumps only when the 9-byte record is null | Load rule pointer; read its pattern offset |
| `16786` | Reorder function `1279:000D` result load, its single exit (frame offset adjusted by +20h) | Load result 1; zero-length relative jump |

Every word record (`+0E` = `W`) is followed in the dump by its `+93` per-word
sub-rule records of `14Fh` bytes from `+94`, decoded as pattern and action.
A wrapped-call hook in the caller's frame was tried first for T4 and crashed
the program; the in-function record test is the working site.
The T3 site is the loop's own entry jump target, so it cannot sit at the
preceding rule advance (`14164`): a hook there is jumped into mid-instruction.
A first attempt did exactly that and silently skipped T3 while three
T3-independent outputs still matched; the raw trace exposed the missing record.
The original relocation table fills its MZ header exactly, so the instrumented
copy grows the header by one paragraph. Load addresses are header-relative and
the hook sites keep their original file offsets.

The hook preserves flags, general registers, DS and ES. It dumps the vector,
cached tags, each record's first `282h` bytes, and selected T1 rule/selector/endpoint.
Original assets stay untouched; copied assets are checked after execution.
The manifest retains raw bytes and normalizes node identity by physical address,
including aliases and identity across boundaries.

All **77 complete output files** equal the original oracle bytes on **both runs**
with the seven-site image. Every input that reaches T2 also reaches the T3, T4
and reorder boundaries: T1, T2 and T3 are one native function (`0E1F:0009`)
that returns 1 after the T3 table, no corpus input takes its early return in
T2 or T3, and the caller `12DC:033A` then runs T4 and the reorder function.
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
| `core/ltpro/second_pass.lua` | T2 scheduling, all 53 selector bodies the table uses plus unreferenced 17 and 53, linked-record moves, auxiliary links at `+62`, prefix strings at `+243`, stale `DS:C7B1` after handler rebuilds | **76/76** DOS T1→T2 fixtures; **962/962** generated-node instruction fixtures covering every selector |
| `core/ltpro/third_pass.lua` | T3 scheduling, the 36 selector bodies the table uses plus 8 unreferenced non-default bodies, the `back` endpoint adjustment, terminator-dependent selector 37 | **76/76** DOS T2→T3 fixtures; **872/872** generated-node instruction fixtures covering every selector |
| `core/ltpro/fourth_pass.lua` | The T4 function: cached-context adjective pre-pass, per-word sub-rule pre-pass with its 17 selector characters, the 9-byte-record loop from position 0 with a rebuild after each removing match, the 54 selector bodies the table uses plus 6 unreferenced ones, boundary insertion and record moves | **76/76** DOS T3→T4 fixtures (12 change tags); **1,690/1,690** generated-node instruction fixtures: every table selector plus 6 unreferenced bodies, both pre-passes, and all 289 dictionary sub-rules (578 cases) |
| `core/ltpro/reorder.lua` | T5/T6 reordering over native records; now reads the record's own `+11C` text and reports whether it rebuilt | **76/76** DOS T4→reorder fixtures (33 change tags); 358 isolated instruction cases as before |
| `core/ltpro/lexical.lua` (sub-rules) | Attaches up to ten `word pattern*$action` records per word in dictionary order, as `0A4F:1603` does after the multi-word test | Stage test; the corpus arrays captured from DOS are used directly by the T4 probe |

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

## T2 and T3 scheduling

Both passes share the T1 frame and vector. Unlike T1, which stops after its
first default rewrite, T2 and T3 scan every rule from position 1 while
`DS:C7B1 - 1 > position`, continue after each match endpoint, and rebuild once
per rule only when the replacement routine removed a node. Fourteen T2 and
eleven T3 handler bodies call the vector rebuild themselves without storing
the returned count, so `count` is modeled as a separate variable from the
vector; selectors 51–54 (T2) and 34 (T3) do store it. A Lua read of a vector
slot beyond the rebuilt vector is reported as an event rather than guessed.

Field semantics observed in these handlers: `+62` is a far pointer to the
auxiliary record (set to the X/Y node and written through by T2 selector 49),
`+98` addresses the record's own `+11C` translation (the `strrchr` reading
tests), `+243` receives the prefixes `неужели ` and `не `, and `+6A`'s low six
bits select the verb frame while bit 6 is the aspect bit T3 reads. Several
descending searches stop at `position-1` when no node carries the sought tag,
and T3 selector 6 never tests the head itself; the ports keep these quirks.

The generated probes empty the preceding tables (and the question cleanup
table for T3) in a disposable image, so T1 normalization is the only earlier
transformation, then isolate each original record or run the complete table.
Synthetic selectors exercise bodies no supplied record selects.

## T4

The caller `12DC:0342` runs `0E1F:0009` (T1–T3), then `108F:000F` (file
`142FF..1608F`) with its own `848h`-byte frame, then the reorder routine
`1279:000D` already ported in `reorder.lua`. `108F:000F` rebuilds the vector,
then runs two pre-passes before its 178-record, 9-byte-record rule loop. The
first rewrites `N` readings to `A` where the cached tags read `NN`, `NAN`,
`NdN`, `NHN` or `N-N` and the translation carries `A.` or an `A` reading with
a non-ASCII first byte, advancing by one, three or four positions. The second
applies per-word sub-rules: the **289** dictionary records of the form `word
pattern*$action` (for example `in <TAOHI>!врм!*$PРв течение`), which the
loader at `0A4F:1603` (file `F4F3`) stores, ten at most per word, in
`14Fh`-byte records (pattern at `+0`, action at `+50h`) addressed from node
`+94` with the count at `+93`. The smallest match endpoint wins; the action's
first backslash-separated part rewrites the word's tag and translation, the
second part feeds the replacement routine, and the character after a second
backslash selects one of 17 small handlers. The rule loop differs from T2/T3:
it starts at position 0, rebuilds after every removing match, and a cleared
flag ends the current rule. Two selectors insert `t`, `^` or `|` boundary
records; one moves a record before the head; one reads the head's linked
`next` record rather than the vector neighbour.

The uninitialized native result word read at `14918` is modeled as zero on
entry; no corpus or generated case has contradicted that.

## Reorder boundary

The reorder function swaps linked records in place but rebuilds its vector,
`DS:C7B1` and the `DS:C5AE` tag cache only when it blanked a record (a
determiner, or a hyphen handler's removal). `He must not go.` therefore
leaves the native cache reading `*RUKV*` while the records already read
`R K U V`; the port reports whether it rebuilt, and the probe compares the
cache accordingly. Whether later stages read that stale cache is not yet
established.

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
python3 tools/ltpro_second_pass_probe.py
python3 tools/ltpro_second_pass_native_probe.py --variants 2 --full-table 8
python3 tools/ltpro_third_pass_probe.py
python3 tools/ltpro_third_pass_native_probe.py --variants 2 --full-table 8
python3 tools/ltpro_fourth_pass_probe.py
python3 tools/ltpro_fourth_pass_native_probe.py --variants 2 --full-table 8
python3 tools/ltpro_reorder_probe.py
python3 tools/ltpro_native_probe.py
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
comparisons and the independent Lua slice agree through T4 and the reorder pass.
After reordering, the driver `0687:066C` calls `151F:2740` (numeric records),
`1C3D:1B3F`, `1986:000E` (T8) and `17AA:1D31`; T7 (`1313:1364`) is reached
from one of those, not from the driver directly. The next dependency
is the complete native lookup/analyzer state (multi-word phrases, suffix and
prefix analysis, unknown words, annotations), then the T5/T6 reorder caller,
T7/T8 constituent creation and generation. Most lexical branches, the later
passes' callers, generation, global allocation state, document lifecycle and
full-file output remain open.

Keep the existing multi-week planning assessment. These measurements do not
justify a tighter delivery range: T1–T4 are verified over captured nodes, but
the lexical analyzer, T7/T8 and generation contain many more unresolved state
transitions. The static ledger
is an inventory rather than a completed writer/reader map. Phase 1's observability
and initial slice are delivered; its full semantic mapping gate remains open.
