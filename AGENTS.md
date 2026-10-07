# Agent instructions

## Icon generation

Never draw icons separately. Generate every icon in a set together as a single
strip or atlas in one ImageGen call. When visual states are needed, draw normal,
selected, pressed, hover, and disabled states together in that same atlas. Use
the authored state artwork directly; do not derive visual states through script
post-processing.

## Obtaining original LTPRO translations

When asked to check a translation or verify parity, obtain the original program's
output with `tools/ltpro_capture.py`, then compare it with the current Lua engine.
The original executable is the translation oracle. Do not infer its output from
the Lua translator, dictionary entries, natural Russian wording, or a proposed
expected translation.

Run from the repository root. Requirements are Python 3, `dosbox-x` on PATH,
Lua 5.3+, and these supplied files in `LTGOLD/`:

- `LTPRO.EXE`
- `BASE.DIC`
- `BASE.RUS`
- `ERPREFIX.PRE`
- `LTGOLD.CNF`
- `LTPRO.CMD`

For an ad hoc sentence check, use a separate temporary cases file and explicitly
set both `--cases` and `--output`. Running capture with its default arguments
replaces the main corpus reference; do not do that for an ad hoc check.

```sh
ltpro_check_dir=$(mktemp -d /tmp/ltpro-check.XXXXXX)
python3 - "$ltpro_check_dir/cases.json" <<'PY'
import json
import sys
from pathlib import Path

cases = [
    {
        "id": "weather-good-today",
        "group": "verification",
        "input": "The weather is good today.",
    },
]
Path(sys.argv[1]).write_text(json.dumps(cases, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
python3 tools/ltpro_capture.py \
  --cases "$ltpro_check_dir/cases.json" \
  --output "$ltpro_check_dir/reference.json" \
  --repeat 2 --timeout 60
python3 tools/ltpro_pipeline_probe.py \
  --cases "$ltpro_check_dir/cases.json" \
  --reference "$ltpro_check_dir/reference.json" \
  --report "$ltpro_check_dir/comparison.json"
```

Replace the example input with the user's exact sentence, preserving spelling,
capitalization, apostrophes, and punctuation. Each case must have a unique ID
containing only lowercase ASCII letters, digits, and hyphens, and must include
`id`, `group`, and `input`. The supplied capture profile requires input encodable
in CP866.

The capture tool copies the six assets into isolated temporary DOS mounts and
starts a fresh original LTPRO process for every input. It writes input as CP866
with CRLF and runs:

```text
LTPRO.EXE /I C0000.IN /O C0000.OUT /F- /B- /N
```

DOSBox-X runs headlessly with dummy SDL video/audio drivers. Capture requires at
least two byte-identical runs and checks that the copied assets were unchanged.
The JSON reference preserves raw CP866 output in hex, its SHA-256, the decoded
translation, asset hashes, command, emulator details, and capture provenance.
Translation extraction changes only CRLF/newline framing and excludes the
separate blank-line-delimited meanings appendix. Preserve original spelling,
case, punctuation, spacing, and inline alternative meanings.

The comparison probe validates provenance and runs the current Lua engine from
the same input and assets. Exit code 0 means exact paragraph parity; nonzero
means a mismatch, invalid provenance, or execution failure. Read the report to
distinguish these outcomes. A direct CLI check is also available with
`lua init.lua "The weather is good today."`, but that is the Lua result only.

Report the original LTPRO output and current Lua output separately, state whether
they match, and link the captured evidence when useful. If capture fails or the
required assets/emulator are unavailable, report that original LTPRO verification
could not be completed. Never present an assumed output as a verified capture.
