# en-ru-translator

A pure Lua port of the LTGOLD / SARMA 2.0 English→Russian rule-based translator
(LinguaTech Systems, 1992). One engine handles lexical analysis, grammar,
Russian morphology and output. The original EXE supplies static data; Lua runs
the translation code without DOSBox or process snapshots.

## Run

Requires Lua 5.3+ and the supplied unpacked `LTPRO.EXE`, `BASE.DIC`, and `BASE.RUS`
in `LTGOLD/` (original assets are not tracked).

```sh
lua init.lua "She can speak Russian."
printf '%s' "Two books." | lua init.lua
lua init.lua --data /path/to/assets "The door is open."
lua init.lua --exe /path/to/LTPRO.EXE --dic /path/to/BASE.DIC --rus /path/to/BASE.RUS "Two books."
```

Input and output are UTF-8. Pass one sentence per invocation. `--help` lists
options; `--` ends option parsing. Options also accept `--name=value`.
Use `--meanings` (API: `meanings = true`) to append the meanings glossary.
The API also exposes it as `state.meanings_text` (UTF-8) and `state.meanings`
(CP866); sentence-only output remains the default.

## Lua API

```lua
local engine = require 'core.engine'
local text, state = engine.translate('He is in the house.', {data_dir = 'LTGOLD'})
assert(text == 'Он - в доме.')
```

`translate` returns UTF-8 plus diagnostic state. `run` returns CP866 plus the same
state. Options `executable`, `dictionary`, and `russian` accept paths or raw bytes.
Option `transliterate = false` corresponds to LTPRO’s `/L-`: bare `=`
readings remain empty, while `%` still transliterates. Each call builds fresh mutable state. Diagnostic state exposes `root` (the Lua
record list), `elements`, `tags`, `stages`, and `output` (CP866 text). Unsupported
lexical branches raise errors.

Duplicate dictionary keys retain file order; the first entry wins by default.
API callers can set `dictionary_entry = function(key, entries) return index end`
to choose a different entry. This also applies to redirects and suffix stems;
the dictionary records are preserved and should be treated as read-only.

## Structure

The flat `core/` directory groups code by functionality: `lexicon`, `grammar`,
`phrasing`, `matching`, `reorder`, `senses`, `constituents`, `agreement`, `syntax`,
`generation`, and `output`. `nodes` owns linked Lua records; every stage uses
ordinary tables and strings. `assets` decodes static EXE tables, and `engine`
loads assets and composes the stages. See [the pipeline](docs/pipeline.md).

The older parser/compiler, custom dictionary overlays and debug CLI were retired.
`init.lua` always uses the recovered engine; the old `--ltpro` switch and
`core.ltpro.*` namespace are removed. Historical overlay files in `data/` remain
as reference material and are not loaded. The overlay editing utilities were
also retired. Original binary names remain in research tooling for provenance.

## Verification and limits

The recovered engine matches the **77 original + 20 holdout + 26 lexical-macro captured inputs**.
That establishes corpus parity, not universal equivalence. The `=` and `%` lexical macros,
contextual transliteration, and dictionary redirects are ported. Some suffix
fallback branches and inline input directives remain unsupported; this
is a single-sentence API. See [testing](TESTING.md) for reproducible checks and
[research evidence](reference/LTPRO_CLI_REPORT.md) for capture details.

```sh
sh test/run_all.sh
python3 tools/ltpro_pipeline_probe.py
```

The test suite uses the original assets. Python is needed only for research
probes, and DOSBox-X only when capturing new executable references.

CP866 conversion is also available as a Unix filter:

```sh
printf 'Привет' | lua bin/encoding.lua encode > greeting.cp866
lua bin/encoding.lua decode < greeting.cp866
```
