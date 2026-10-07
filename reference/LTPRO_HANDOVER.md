# LTPRO parity handover — updated 2026-10-07

This records where the native-parity port stands after the post-reorder
stages (T5–T8) were completed, how it is verified, and what remains before
an LTPRO output file can be produced by Lua alone. Addresses and data
structures are in [the native map](LTPRO_NATIVE_MAP.md); the method and
earlier stages in [the stage report](LTPRO_STAGE_REPORT.md).

## State of the sentence pipeline

The driver `0687:05D5` runs, per sentence:

| Step | Native | Lua | Verification |
|---|---|---|---|
| Lexical analysis | `0A4F:3B12` | `lexical.lua`, `phrases.lua`, `suffixes.lua` | **75/75** single-sentence snapshots, including subrules |
| T1–T3 | `0E1F:0009` | `first_pass`, `second_pass`, `third_pass` | 76–77 DOS fixtures each + generated instruction fixtures |
| T4 | `108F:000F` | `fourth_pass.lua` | 76 DOS fixtures + 1,690 instruction fixtures |
| T5/T6 reorder | `1279:000D` | `reorder.lua` | 76 DOS fixtures + 358 instruction cases |
| Numeric pass and reading choice | `151F:2740` | `senses.lua`, `russian.lua`, `endings.lua`, `records.lua`, `heap.lua`, `clib.lua` | **77/77** DOS transitions; mutation fuzz (below) |
| Constituents and rule pass (calls T7) | `1C3D:1B3F` | `constituents.lua`, `seventh_pass.lua`, `lexmatch.lua` | **77/77**; fuzz |
| T7 | `1449:0004` | `seventh_pass.lua` | **208/208** native calls; fuzz |
| T8 | `1986:000E` | `eighth_pass.lua` | **77/77**; fuzz |
| Generation | `17AA:1D31` → `17AA:0475` | `generation.lua`, `forms.lua` | **77/77** DOS transitions; mutation fuzz |
| Sentence output / meanings | `0687:0BB7`, `0687:01C8` | `output.lua` | **77/77** DOS chains on two captures |
| Sentence cleanup | `0687:0A50` | `records.clear` | native comparison in 200 mutated chains |

The post-reorder ports run on a byte-level model of DOS memory
(`core/ltpro/memory.lua`): far pointers keep their segment:offset form,
strings are split in place, records are allocated by a port of the Borland
heap at the native addresses, and BASE.RUS is read through emulated DOS
handle 5. Running the Lua numeric, constituent and T8 stages back to back
from the DOS snapshot taken after reordering reproduces **every non-stack
byte** of the DOS snapshot taken after T8 for all 77 corpus inputs (records,
alternatives, constituent array, heap headers, MCBs and globals).

### Answering "T5–T8": what works

- T5/T6 (reorder) — unchanged, verified earlier.
- The post-reorder driver stages in between: numeric/reading pass and the
  constituent stage, which have no table names but are required for T7/T8.
- T7 — both callers (rule pass selector 3 and T8).
- T8 — all 70 selectors (57 with bodies).

All are verified against the original instructions, not against Lua output.

## How it is verified

Native ground truth comes from the original executable twice over:

1. `tools/ltpro_memtrace.py` runs every corpus input in DOSBox-X with hooks
   at the five post-reorder driver boundaries; each hook writes the whole
   640 KiB of conventional memory. Output files stay byte-identical to the
   oracle. Snapshots are cached (zlib) in `.cache/ltpro-memtrace/` (not in
   git: they contain the original program and dictionaries).
2. `tools/ltpro_snapshot.py` runs each native stage in the 8086 harness
   from a snapshot and compares all memory with the next DOS snapshot:
   **152/154** transitions identical; the two others differ only in a timer
   interrupt frame in dead stack and a copy of dead-stack garbage that no
   code reads. The harness runs the C library natively, emulates INT 21h
   (read, lseek, ioctl, resize block) including the stack image DOSBox-X's
   kernel entry leaves, and models flags down to parity/aux carry.

Lua is then compared with that native code:

| Tool | What it checks |
|---|---|
| `tools/ltpro_function_probe.py FN --words N` | every corpus call of one native function replayed through its Lua port: writes and AX/DX |
| `tools/ltpro_post_chain.py` | Lua stage chain vs the DOS snapshot after T8 |
| `tools/ltpro_post_fuzz.py` | randomized record tags/fields, constituent elements and dictionary readings; native harness vs Lua on all non-stack memory |
| `tools/ltpro_heap_fuzz.py` | random malloc/calloc/free sequences vs the native heap |
| `tools/ltpro_coverage.py` | native instruction coverage of each stage over the corpus |
| `test/ltpro_post_stages_test.lua` | asset-free unit checks (memory model, tokenizer state, qsort tie order) |

Function-level results on the corpus (all pass): `151F:0B6B` 300,
`043A:074D/0850` 187, `1FCD:007F/057B/1031` 185–187, `151F:028B` 86,
`151F:000F` 220, `151F:09A3` 23, `151F:1F6F` 18, `151F:056E` 5,
`151F:0C03` 298, `151F:2029` 298, `151F:2740` 77, `1C3D:0135` 3,000,
`1C3D:05C5` 77, `1C3D:1B3F` 77, `1449:0004` 208, `1986:000E` 77, heap
21–56 calls each and 30×60-operation fuzz sequences.

Mutation fuzzing (`tools/ltpro_post_fuzz.py`, native harness vs Lua, all
non-stack memory), final code:

| Campaign | Cases | Result |
|---|---:|---|
| reorder → numeric + constituent + T8, record fields and dictionary readings (seeds 9, 31) | 3,000 | all identical |
| reorder → numeric, readings (seed 13) | 2,000 | all identical |
| numeric → constituent + T8, record fields (seed 7) | 1,500 | all identical |
| constituent → T8, record fields and constituent elements (seed 21) | 1,500 | all identical |

Fuzzing found three real porting errors, all fixed: qsort's width/comparator
globals (`DS:CA1E..CA23`) were not stored; alternatives were cloned from the
last clone instead of the original record (three or more senses); and the
number test in `0687:0892` compares the tag byte, not the pushed word.

Best native instruction coverage reached (corpus plus fuzz): T8 `1986:000E`
2,492/3,669; T7 875/1,131; constituent builder 1,903/1,998; rule pass
488/705; `151F:0C03` 1,257/1,525; `151F:2029` 407/604; `1C3D:0135` 326/419.

Reproduce (about 3 minutes for the capture, then minutes per tool):

```sh
python3 tools/ltpro_memtrace.py
python3 tools/ltpro_snapshot.py
python3 tools/ltpro_post_chain.py
python3 tools/ltpro_function_probe.py 1986:000E --words 3
python3 tools/ltpro_post_fuzz.py --start numeric --stages constituent T8 --cases 300
python3 tools/ltpro_heap_fuzz.py
lua test/ltpro_post_stages_test.lua
```

## Native behaviour that the ports reproduce deliberately

- `043A:0850` starts its index scan at an uninitialized local that holds the
  CS pushed by the INT 21h inside lseek (the C library's load segment). The
  port takes it as `m.library_segment`; any value above 32 behaves the same:
  the length of a two-letter block runs to the next first letter.
- T8 keeps three record pointers in its frame across handlers; case 1's
  `k` path uses the one left by an earlier handler.
- `1FCD:057B` writes through a null pointer when a refilled buffer has no
  newline; `151F:0C03` uses `0000:0001` when a partner lookup lacks `*`.
- The record count limit (`DS:C574` vs `DS:044D`) and the 42h-element array
  being written up to 44h elements are modeled through the memory model.

## Known gaps and approximations

1. **Stack contents are not modeled.** Observable consequences found so far
   are modeled explicitly (above). Two kinds remain approximate:
   - constituent element bytes `+1/+3` built on the stack (rule selector 10,
     T8 selectors 53–56 and 63): written as 0; no code reads them;
   - T8's frame pointers at entry (null here; natively stale stack). The
     corpus and 3,000+ fuzz cases never read one before a handler sets it.
   `tools/ltpro_snapshot.py`'s uninitialized-read detector (`watch_uninitialized`)
   found exactly one stack read of garbage in all post-reorder code over the
   corpus (the `0850` case above). Re-run it on new inputs when in doubt.
2. **strtok's saved pointer** `DS:CA24` points into a dead stack buffer after
   `1E71:006F`; its value is not reproduced and is excluded from comparisons.
3. **Profile-gated paths are not ported** and raise an error if reached:
   `043A:2307` (DS:BB9E), `1E71:0015` (DS:BBA0), the subject-domain filter of
   `151F:2029` (DS:BBA2). The frozen profile clears all three.
4. **Word alternatives inside lexical-matcher classes** (`[A`x`]`) are not
   ported in `lexmatch.lua` (no T7 rule uses them; error if reached).
5. **Coverage.** Corpus plus fuzz leave native code unexecuted, e.g. parts of
   `1FCD:057B` (buffer refill), `1313:000E` blank-record removal in T7, and
   T8/T7 handler branches whose patterns the fuzz did not hit. See the
   coverage output of `ltpro_post_fuzz.py --coverage`. These paths are ported
   by reading the code but are not yet differentially confirmed.
6. **Two Lua representations.** T1–T4 and reorder operate on node tables
   (`nodes.lua`), the later stages on the memory model. A converter from node
   tables to memory records is now provided by `bridge.lua`; `pipeline.lua`
   runs from raw text through both representations without a DOS snapshot.

## Generation/output continuation — 2026-10-07

The Lua chain now runs from the post-reorder snapshot through generation,
sentence text and the meanings appendix. It matches all 77 DOS transitions
in each of two newly captured runs, with the same documented memory exclusions.
All original final output hashes remain unchanged by instrumentation. See the
[generation report](LTPRO_GENERATION_REPORT.md) for tests and limitations.

Address corrections: the sentence driver starts at `0687:05D5` (file `A845`),
output at `0687:0BB7` (file `AE27`), appendix at `0687:01C8` (file `A438`),
and cleanup at `0687:0A50` (file `ACC0`). The previous `7427/6A38/72C0`
labels were load-image offsets, not offsets relative to segment `0687`.
The last routine frees sentence memory; it does not wrap output files.

## Snapshot-free CLI continuation — 2026-10-07

The new `lua init.lua --ltpro` entry matches **77/77 original outputs and 20/20
new captures**, starting with raw input. Static tables, heap and BASE.RUS index
come from assets through `initialize.lua`; `bridge.lua` connects node tables to
memory records. Lexical comparisons now include subrules and match 75/75
single-sentence fixtures; the reading decoder matches 2,184 native calls.

See [the CLI report](LTPRO_CLI_REPORT.md) for reproducible checks and limits.
The user-scoped target is CLI text input/output: DOS UI/startup behavior and
exact document/file formatting are not required. General sentence splitting,
unported lexical branches and broader mode/branch coverage remain open. The
older default translator is still 44/77; select `--ltpro` for the new engine.
