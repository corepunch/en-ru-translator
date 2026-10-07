# Full-program LTPRO reference corpus

77 inputs captured from the supplied unpacked `LTGOLD/LTPRO.EXE` through
DOSBox-X 2026.10.01 on 2026-10-06. Two complete runs produced identical output
bytes for every case. All ten historical reference paragraphs were reproduced.

The single Lua engine matches **77/77** inputs and **20/20** additional holdout
inputs and **26/26** lexical-macro inputs. The older 44/77 comparison files are retained as historical research
artifacts, not current results. See [testing](../../TESTING.md) for current commands.

The macro corpus was captured twice on 2026-10-07 from the unchanged original
assets; both runs produced identical bytes. It covers partial input, `=`/`%`,
supplied spellings, compound names, single-word W readings and redirects.

## Files

- `macro_cases.json` and `macro_reference.json`: the lexical-macro corpus with
  full capture provenance and raw outputs.
- `cases.json`: input sentences and categories; no hand-authored expected translations.
- `reference.json`: raw output as CP866 hex, decoded translation paragraphs,
  hashes, emulator version, configuration, command arguments and capture time.
- `comparison.json`: the retired translator’s results, expected paragraphs, per-case
  differences and the reference file's hash. This is a snapshot; rerun the comparison
  after changing the translator.
- `stages.json`: native lexical/T1/T2 snapshots and T1 rule-selection events,
  captured with a disposable instrumented copy. All 77 complete output files
  still match the original oracle on both runs. Native raw records, pointer
  identity, cache, rule IDs and handler IDs are retained.
- `capitalization-cases.json`, `capitalization-reference.json` and
  `capitalization-comparison.json`: 16 additional casing inputs and historical comparison results.

The separate native T1 port matches **77/77 sentence-stage fixtures** and all
**36 recorded rule-selection events**. There are 76 files entering grammar,
one of which enters twice; `ABC-123.` bypasses this grammar entry. These counts
describe stage coverage, not full translations. See the
[stage report](../../reference/LTPRO_STAGE_REPORT.md) for limits and reproduction.
Generated instruction fixtures add 648/648 local T1 comparisons across all
selectors. Synthetic selection of unused selector 8 and isolated table records
are reported separately from complete-program observations.

## Reproduce

From the repository root:

```sh
brew install dosbox-x
python3 tools/ltpro_capture.py
python3 tools/ltpro_pipeline_probe.py --report /tmp/translator-comparison.json
```

Capture runs the program with `/I INPUT /O OUTPUT /F- /B- /N`. Every input receives
a new LTPRO process; cases are grouped into batches of 16 within DOSBox-X. Every
batch has a new temporary DOS mount containing copies of these supplied files:

```text
LTPRO.EXE
BASE.DIC
BASE.RUS
ERPREFIX.PRE
LTGOLD.CNF
LTPRO.CMD
```

The source files are not mounted or modified. `ERPREFIX.PRE` and `LTGOLD.CNF` are
part of this working profile; a smoke run without the configuration produced no
translation file. The capture verifies that its copied assets remain unchanged.
SDL dummy video/audio drivers permit headless execution on the research machine.
No project dictionary overlays, patched EXEs, or manually corrected expected
translations are used.

Capture requires at least two identical runs before atomically replacing the
reference file. Missing or empty outputs, timeouts, asset mutations, or differing
runs fail the capture. Failure retains its temporary directory for diagnosis.
For additional options, run either Python tool with `--help`.

Comparison creates fresh engine state per case, loads the original BASE files,
and checks their hashes and the captured input/raw-output integrity before running.
It does not launch DOSBox-X or silently recapture. Its exit code is 1 when translation
mismatches exist, 0 for an exact corpus match, and nonzero on invalid provenance or
execution failures. The comparison does not require DOSBox-X to remain installed.
Python is used only for optional research tooling; the translator remains pure Lua.

## What is compared

Raw CP866 bytes are retained without cleanup. Paragraph comparison decodes CP866,
normalizes CRLF to LF, removes framing newlines, and excludes the separately
blank-line-delimited meanings appendix. It does not lowercase, collapse spaces,
correct spelling, or remove punctuation. Inline alternative meanings remain part
of the comparison. The complete meanings appendix and raw formatting remain in
the capture but are not scored by the paragraph comparison.

This preserves original oddities, including Latin `e` inside Russian verb forms.
For example, fresh LTPRO output for `The cat sat on the mat.` is
`Кошка посидeла в ковер{1.матрица}.`, which differs from both the old preferred
Russian expectation and the current Lua output. The oracle records the executable's
behavior, including its mistakes.

## Installation note

The Homebrew install encountered a conflict between `sdl2-native` and
`sdl2-compat`. The existing native links were temporarily removed, DOSBox-X was
installed, and the native links were restored. DOSBox-X uses its Homebrew-managed
compatibility library through its own dependency path. No force-overwrite of the
existing SDL2 installation was used.
