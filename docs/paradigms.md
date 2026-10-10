# Russian morphology

`core.generation` owns both low-level inflection and sentence word generation.
`core.russian` supplies Russian dictionary metadata and ending operations.
LTPRO's morphology tables are in `core/rules.lua` (`rules.paradigms`: `noun-m`,
`noun-f`, `noun-n`, `adjective-m`, `adjective-f`, `adjective-n`,
`verb-imperfective`, `verb-perfective`, `replacement`), extracted byte for byte
from the unpacked executable, together with the pronoun table
(`rules.lists.pronouns` nominatives, `rules.lists.pronoun_cases` oblique cases). A dictionary directory may carry its own
text copy: `dictionary/paradigms.txt` (one row per paradigm: cut count, endings
per slot, with two fixes to LTPRO's data) takes precedence for the default dictionaries. Each `.RUS` record names its paradigm in the native byte
(`0x80|id`).

Every table row has a list of the lemma endings it serves, in the same order as
the rows: `rules.lists.endings_noun_m` (66 rows), `endings_noun_f` (35),
`endings_noun_n` (33), `endings_adjective` (26), `endings_verb_imperfective`
(106), `endings_verb_perfective` (113) and `endings_replacement` (the
`replacement` table, 47). For example `noun-m` row 0 serves `в г д з к л м р с т`
(дом) and row 2 `г к х йл ок ик рок`. `russian.ending_matches` returns the
rows whose list matches a word's end, longest ending first in LTPRO's order;
a new word's paradigm is chosen the same way.

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
