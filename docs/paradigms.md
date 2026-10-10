# Russian morphology

`core.generation` owns both low-level inflection and sentence word generation.
`core.russian` supplies Russian dictionary metadata and ending operations.
LTPRO's morphology tables are in `core/rules.lua` (`rules.paradigms`, keyed by
data-segment offset), extracted byte for byte from the unpacked executable,
together with the pronoun table (`rules.lists[0x6344]` nominatives,
`rules.lists[0x6314]` oblique cases). A dictionary directory may carry its own
text copy: `openrussian/paradigms.txt` (one row per paradigm: cut count, endings
per slot) takes precedence for the OpenRussian dictionaries. Each `.RUS` record names its paradigm in the native byte
(`0x80|id`), assigned at build time by `tools/fit_paradigms.lua`.

Every table row has a list of the lemma endings it serves, in the same order as
the rows: `rules.lists[0x5130]` (masculine nouns, 66 rows), `0x53C4` (feminine,
35), `0x5522` (neuter, 33), `0x566C` (adjectives, 26), `0x58A8` (imperfective
verbs, 106), `0x5CCC` (perfective verbs, 113) and `0x6136` (the `0x61F2`
replacement table, 47). For example `noun-m` row 0 serves `в г д з к л м р с т`
(дом) and row 2 `г к х йл ок ик рок`. `russian.paradigm_candidates` returns the
rows whose list matches a lemma, longest ending first in LTPRO's order;
`tools/fit_paradigms.lua` takes the candidate unless OpenRussian's listed forms
show another row regenerates more of them. Nothing is stored beyond the
paradigm number: OpenRussian's dictionaries have no form file, and the tables
are LTPRO's own, never extended.

The form functions accept sentence state, table ID, a CP866 string and
grammatical arguments. They return a new string, or `nil` when no form exists:

```lua
local engine = require 'core.engine'
local generation = require 'core.generation'
local encoding = require 'core.encoding'
local state = engine.new_state('LTGOLD/BASE.RUS')
local result = generation.noun_form(state, 0, encoding.encode('дом'), 1, 0, 1)
assert(encoding.decode(result) == 'дома')
```

`noun_form` and `adjective_form` take gender, plural and case arguments;
`verb_form` additionally takes aspect, flags, person and past-tense state.
`participle_form` handles participial/gerund selectors; `pronoun_form` handles
pronoun agreement. These are native argument conventions, not a normalized
linguistic API. See the function definitions and differential fixtures for
case-index details.

Table rows contain a byte count to cut and a far pointer to space-separated
endings. `=` preserves the form and `-` rejects it. Operations count CP866 bytes.
Results are independent immutable strings. Failed forms return `nil` without
changing the input or a previous result. Original spelling and ending-selection
quirks are retained through direct string operations.

`tools/ltpro_morphology_probe.py` exercises every recovered table row and seeded
edge cases against the original instructions, using these production functions.
`demo/extract_morphology.lua` remains available for inspecting the binary tables.
