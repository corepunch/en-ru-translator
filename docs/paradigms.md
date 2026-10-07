# Russian morphology

`core.generation` owns both low-level inflection and sentence word generation.
`core.russian` supplies Russian dictionary metadata and ending operations.
The engine reads morphology tables from the initialized data segment of the
unpacked executable; there are no separately maintained Lua copies.

The form functions accept sentence state, table ID, a CP866 string and
grammatical arguments. They return a new string, or `nil` when no form exists:

```lua
local engine = require 'core.engine'
local generation = require 'core.generation'
local encoding = require 'core.encoding'
local state = engine.new_state('LTGOLD/LTPRO.EXE', 'LTGOLD/BASE.RUS')
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
