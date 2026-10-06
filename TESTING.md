# Testing Guide

This repository has three test tracks:

1. Engine correctness in Lua (unit + regression).
2. Direct binary extraction and isolated native-instruction comparisons.
3. Full translation compatibility (historical captures or optional DOSBox runs).

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

## LTGOLD Compatibility (Optional)

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
- `lua demo/compare_ltpro.lua --cached`: `PASS=5 FAIL=5 MISSING=0`, improved from 3/10, using historical captures and original dictionaries. No fresh full-program run.
- Native morphology: 7,029/7,029 cases against each of LTPRO.EXE and LTGOLD.EXE.
- Native reorder: 358/358 cases against each binary.

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
```

These compare the isolated `core.ltpro` ports, not the complete translation pipeline.
String/free primitives are substituted and unsupported instructions fail. Every
reorder pattern is included, followed by deterministic randomized fixtures. The
morphology corpus exercises every recovered table row and randomized edge cases.
Passing probes do not establish all-corpus parity or validate the surrounding
legacy compiler state. Both probes exit nonzero on a mismatch.

The explicit `--cached` comparison uses historical `LTGOLD/refs` captures and the
original `LTGOLD/BASE.DIC`/`BASE.RUS` by default. `--data=data` instead checks project
dictionaries. It compares exact translation text, excluding the separate meanings
appendix and capture line endings; missing captures fail. It does not launch DOSBox.

See [the current audit](reference/LTPRO_COMPARISON.md) for binary identity,
verified extraction fixes, runtime mismatches, evidence, and remaining work.
