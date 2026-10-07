# Testing Guide

This repository has three test tracks:

1. Engine correctness in Lua (unit + regression).
2. Direct binary extraction and isolated native-instruction comparisons.
3. Full translation compatibility against reproducible DOSBox-X captures.

## Prerequisites

- Lua 5.3+
- Optional instruction probes: Python 3 and Capstone, already available on the research machine.
- Optional for LTGOLD compatibility: `dosbox-x` plus `LTGOLD/LTPRO.EXE`

## Fast Path

Run the standard framework tests from repo root:

```sh
./test/run_all.sh
```

What this runs:

- `test/*_test.lua` (module-level tests)
- `demo/compare.lua` (sentence-level regression against stored expectations)
- No `dosbox-x` invocation.

Exit code is non-zero if any step fails.

## Individual Commands

Run module tests only:

```sh
for f in test/*_test.lua; do lua "$f"; done
```

Run sentence regression only:

```sh
lua demo/compare.lua
```

## Native stage probes

Compare the native T1–T4 and reorder ports with the captured DOS stage boundaries,
and with original-instruction runs over generated nodes (requires Capstone):

```sh
python3 tools/ltpro_first_pass_probe.py
python3 tools/ltpro_second_pass_probe.py
python3 tools/ltpro_third_pass_probe.py
python3 tools/ltpro_fourth_pass_probe.py
python3 tools/ltpro_reorder_probe.py
python3 tools/ltpro_first_pass_native_probe.py
python3 tools/ltpro_second_pass_native_probe.py --variants 2 --full-table 8
python3 tools/ltpro_third_pass_native_probe.py --variants 2 --full-table 8
python3 tools/ltpro_fourth_pass_native_probe.py --variants 2 --full-table 8
```

The captures in `test/ltpro/stages.json` come from `tools/ltpro_trace.py`,
which needs DOSBox-X and the frozen assets.

## Native generation and output

The generation/output ports use the same memory model as the post-reorder stages.
See [the generation report](reference/LTPRO_GENERATION_REPORT.md) for the full
command matrix and the remaining end-to-end gaps. Quick checks:

```sh
lua test/ltpro_generation_test.lua
python3 tools/ltpro_function_probe.py 17AA:1D31 --words 2 --stages generation
python3 tools/ltpro_output_probe.py
python3 tools/ltpro_output_probe.py --function meanings
python3 tools/ltpro_output_probe.py --function cleanup
python3 tools/ltpro_memtrace.py --cache .cache/ltpro-output
python3 tools/ltpro_post_chain.py --cache .cache/ltpro-output --until meanings
```

Only the memory trace command launches DOSBox-X. Old captures lack the output
and meanings boundaries and must be refreshed for the longer chain. The chain
matches all 77 DOS transitions in each of two fresh captures; production paragraph
parity remains 44/77 because lexical analysis and startup/integration are incomplete.

## Fresh LTPRO compatibility corpus

Compare the current translator with the 77 captured executable outputs:

```sh
python3 tools/ltpro_compare.py --report test/ltpro/comparison.json
```

This requires Python 3, Lua, and the original assets in `LTGOLD/`, but does not
launch DOSBox-X. It verifies asset, input, and raw-output hashes and starts a fresh
Lua process per case. Mismatches produce a nonzero exit code.

To regenerate references from the executable:

```sh
brew install dosbox-x
python3 tools/ltpro_capture.py
```

The capture copies `LTPRO.EXE`, `BASE.DIC`, `BASE.RUS`, `ERPREFIX.PRE`, `LTGOLD.CNF`,
and `LTPRO.CMD` into isolated temporary DOS mounts. It requires two identical runs
before replacing the references and records raw CP866 output, hashes, commands,
configuration, and emulator version. Exact paragraph comparison excludes only
newline framing and the separate meanings appendix; raw output remains available.
See [the corpus documentation](test/ltpro/README.md) for details and current results.

## Legacy LTGOLD compatibility wrapper (Optional)

Use this only when creating or refreshing reference strings. It is not part of
normal test runs.

Run the 10-sentence compatibility suite:

```sh
cd LTGOLD
./test_compare.sh --all
```

Run one sentence:

```sh
cd LTGOLD
./test_compare.sh "She can speak Russian."
```

Refresh captured references from LTPRO:

```sh
cd LTGOLD
./test_compare.sh --capture
```

Reference files are in `LTGOLD/refs/`.

## Reading Failures

`test/*_test.lua` failures:

- Lua stack trace with file and line.
- Example: `attempt to index a nil value` in a paradigm helper.

`demo/compare.lua` failures:

- Per-case diff with `LUA` output and expected `LTGOLD` line.
- Final summary: `Passed N/M` and non-zero exit on failures.

`LTGOLD/test_compare.sh --all` failures:

- Prints `FAIL [sentence]` plus `LTPRO:` and `Lua:` lines.
- Final summary: `Results: PASS=X FAIL=Y SKIP=Z`.

## Current Status Snapshot (2026-10-06)

- Native reader, reorder, inflection, encoding, utilities, parser, token-stream, and paradigm tests pass.
- `test/translator_test.lua` fails its old custom `The cat sat on the mat.` expectation after removing unsupported rules. The expected string has not been replaced with the current incorrect output; `./test/run_all.sh` therefore exits nonzero.
- `demo/compare.lua`: `Passed 25/25` on current branch.
- Fresh DOSBox-X corpus: **44/77 match**, 33 differ, zero runtime errors. Two complete
  runs produced identical output bytes. All ten historical paragraphs were reproduced.
- `lua demo/compare_ltpro.lua --cached`: `PASS=5 FAIL=5 MISSING=0`, improved from 3/10,
  using historical captures and original dictionaries; these ten cases are also
  included in the fresh corpus.
- Native morphology: 7,029/7,029 cases against each of LTPRO.EXE and LTGOLD.EXE.
- Native reorder: 358/358 cases against each binary.
- New LTPRO grammar ports: lexical matcher 4,780/4,780; replacement 2,048/2,048;
  T8 constituent matcher 1,403/1,403. These are isolated native-node checks, not
  production parser integration or full-program parity.
- Native stage corpus: all 77 instrumented output files match the original bytes
  on both runs. The new T1 port matches 77 sentence-stage fixtures and 36 native
  match events. Lexical vertical slices match 2/2; reading metadata matches 1,377/1,377.
- T1 controlled-node instruction fixtures: 648/648, covering every selector,
  allocation/link edits and limit/failure paths. Selector 8 is selected synthetically;
  it has no supplied T1 rule. These are local behavior checks.
- Additional native capitalization matrix: 16/16 exact paragraph matches.

Native stages and the lexical development path:

```sh
python3 tools/ltpro_trace.py --ids --output test/ltpro/stages.json
python3 tools/ltpro_first_pass_probe.py
python3 tools/ltpro_first_pass_native_probe.py
python3 tools/ltpro_lexical_probe.py
python3 tools/ltpro_readings_probe.py
python3 tools/ltpro_ledger.py
lua test/ltpro_stages_test.lua
python3 tools/ltpro_compare.py --cases test/ltpro/capitalization-cases.json --reference test/ltpro/capitalization-reference.json
```

Only the trace command invokes DOSBox-X. It patches disposable copies, reserves
the hook's memory against the original C startup's allocation shrink, checks
output hashes and copied assets, and requires repeatable semantic state. Its
default captures the two planned examples; `--ids` with no values captures all
77. `--resume` accepts only an identical instrumentation/oracle manifest. Raw
uninitialized bytes are retained, but only named semantic fields are required
to repeat. The stage probe compares rule-selection events, intermediate field
writes, final lexical fields, cache and early termination. Unknown-word and
macro decoding, global allocation state and unobserved handler branches remain
explicit gaps. The production translator still uses its legacy later passes.

Historical baseline check:

- Commit `ae7b4ef` (`Fix source caps handling after token reordering`) gives
	`Passed 24/25` in `demo/compare.lua`.

The current objective is LTPRO compatibility before translation improvements.
The 25 stored Lua expectations include intentional improvements and are not an
executable oracle. Keep them as behavior regression tests, without using their
passing status to claim LTPRO equivalence.

## Direct executable extraction audit

```sh
lua demo/audit_rules.lua
lua demo/audit_morphology.lua
lua demo/compare_binaries.lua
lua demo/compare_ltpro.lua --cached
```

The extraction audit reads the supplied unpacked `LTGOLD/LTPRO.EXE`, aligns records
without insertion cascades, validates sentinels/far pointers, and checks guard
metadata and all 43 suffix records. It now passes all 702 grammar and 43 suffix
records. The morphology audit passes all 431 records. Runtime equivalence is outside
these data checks. The cross-binary comparison deliberately exits 1: LTPRO and
LTGOLD differ in T1 record 26, while all recovered morphology and suffix data agree.

Regenerate the data deterministically from the supplied LTPRO image:

```sh
lua demo/extract_ltpro.lua > core/rules.lua
lua demo/extract_dispatch.lua > core/ltpro/dispatch.lua
lua demo/extract_morphology.lua > core/ltpro/morphology.lua
```

Execute original instructions on controlled fixtures, without DOSBox:

```sh
python3 tools/ltpro_native_probe.py
python3 tools/ltpro_native_probe.py --target ltgold
python3 tools/ltpro_morphology_probe.py
python3 tools/ltpro_morphology_probe.py --target ltgold
python3 tools/ltpro_matcher_probe.py
python3 tools/ltpro_replacement_probe.py
python3 tools/ltpro_constituent_probe.py
```

These compare the isolated `core.ltpro` ports, not the complete translation pipeline.
String/free primitives are substituted and unsupported instructions fail. Every
reorder pattern is included, followed by deterministic randomized fixtures. The
morphology corpus exercises every recovered table row and randomized edge cases.
Passing probes do not establish all-corpus parity or validate the surrounding
legacy compiler state. Every probe exits nonzero on a mismatch.

The three grammar probes target LTPRO only. They read all applicable patterns from
the binary and exercise positive/negative cases plus native node/cache differences.
Replacement comparisons include previous tags, text fields, and the cache. The
ports reject unused embedded-literal class/span syntax rather than treating unknown
native stack behavior as verified. `lua test/ltpro_grammar_test.lua` provides fast
fixed-observation checks without Python or the executable.

The explicit `--cached` comparison uses historical `LTGOLD/refs` captures and the
original `LTGOLD/BASE.DIC`/`BASE.RUS` by default. `--data=data` instead checks project
dictionaries. It compares exact translation text, excluding the separate meanings
appendix and capture line endings; missing captures fail. It does not launch DOSBox.

See [the current audit](reference/LTPRO_COMPARISON.md) for binary identity,
verified extraction fixes, runtime mismatches, evidence, and remaining work.
