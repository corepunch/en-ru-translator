# Testing Guide

This repository has two test tracks:

1. Engine correctness in Lua (unit + regression).
2. LTGOLD compatibility checks (optional, via DOSBox/LTPRO).

## Prerequisites

- Lua 5.3+
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

## Current Status Snapshot (2026-07-11)

- `test/*_test.lua`: all pass.
- `demo/compare.lua`: `Passed 25/25` on current branch.
- `LTGOLD/test_compare.sh --all`: `PASS=5 FAIL=5 SKIP=0`.

Historical baseline check:

- Commit `ae7b4ef` (`Fix source caps handling after token reordering`) gives
	`Passed 24/25` in `demo/compare.lua`.

Given the current project direction, keep both tracks:

- Lua correctness tests should move toward natural/correct Russian outputs.
- LTGOLD checks should remain as compatibility telemetry, not the only success criterion.