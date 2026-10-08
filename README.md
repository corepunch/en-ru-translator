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
record list), `elements`, `tags`, `stages`, and `output` (CP866 text).
Malformed directives and invalid callback selections raise descriptive errors.

Duplicate dictionary keys retain file order; the first entry wins by default.
API callers can set `dictionary_entry = function(key, entries) return index end`
to choose a different entry. This also applies to redirects and suffix stems;
the dictionary records are preserved and should be treated as read-only.

Hyphen and slash compounds first try an exact dictionary entry, then analyze
their components while retaining the separator. A compound containing a bare
derivational noun ending (such as `foo-ness` or `ment/foo`) stays intact as an
unknown noun. This is an intentional Lua feature policy, not DOS output parity.

Prefix analysis loads `ERPREFIX.PRE` from the asset directory when present.
Exact entries win; otherwise the longest prefix with a recognized stem is used.
Stem morphology runs before the translated prefix is attached. `re` uses a
separate word; other prefixes join the stem. Disabled `*` rows are ignored.
Use `--prefixes FILE` / API `prefixes = path_or_bytes` to supply data, or
`--no-prefixes` / `prefixes = false` to disable this fallback.

`--domain инф` (API: `domain = 'инф'`) prefers a reading marked with the
dictionary's `инф)` subject label. Other readings remain available as alternatives;
without a matching label, dictionary order is unchanged. Domain preferences
apply within the grammatical reading selected for each word.

Inline `{~text~}` spans preserve their contents verbatim, including spaces and
case; `{~=text~}` spans transliterate their contents. Each span is one opaque
record, so its contents bypass dictionary lookup and output capitalization.
Spans must close with `~}` and cannot nest. `{~\2` starts a list with two words
per row (counts 1–10 are supported); `{~\.` returns to sentence mode. List items
translate independently, with tabs between columns and newlines between rows.
A protected span counts as one item. Each section starts on a new line. List
results expose individual translation states in `state.sections` instead of one
sentence root; requested glossaries follow the complete list.

Phrase keys support literal words/punctuation and `~` gaps. A gap captures zero
or more words without crossing punctuation or protected spans; matching chooses
the longest phrase, preferring fewer gaps and more literal words on ties. A `~` in its reading
re-inserts captured words, which receive normal lexical analysis. A reading
without a gap consumes those words as part of the idiom (for example, the
possessive in `do your best`).

`W` phrase readings distribute tagged words, metadata, and `#literal#` text.
Slash-separated phrase readings default to the first alternative; the Lua option
`phrase_reading = function(key, readings) return index end` selects another.
The raw CP866 choices remain available as `node.phrase_readings` for diagnostics.

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

Development targets the translator's features using ordinary Lua records and
strings. Exact DOS output, memory behavior, and undocumented binary switches
are not a completion requirement. This remains a rule-based translator: broader
language quality and arbitrary multi-sentence input are outside issue #3's scope.

The standard suite covers the public features above, including lexical analysis
of all 8,940 supplied multiword `W` phrase entries. That inventory check guards
against analyzer failures; it does not establish translation quality for every
phrase. The historical **77 original + 20 holdout + 26 lexical-macro captures**
remain unchanged as research evidence. See [testing](TESTING.md) for the feature
checks and optional historical comparisons.

```sh
sh test/run_all.sh
```

The test suite uses the original assets. Python is needed only for research
probes, and DOSBox-X only when capturing new executable references.

CP866 conversion is also available as a Unix filter:

```sh
printf 'Привет' | lua bin/encoding.lua encode > greeting.cp866
lua bin/encoding.lua decode < greeting.cp866
```
