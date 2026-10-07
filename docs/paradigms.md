# Russian morphology

`core.generation` owns both low-level inflection and sentence word generation.
`core.russian` supplies Russian dictionary metadata and ending operations.
The engine reads morphology tables from the initialized data segment of the
unpacked executable; there are no separately maintained Lua copies.

The form functions accept a memory model, table ID, source segment/offset and
native grammatical arguments. They return a segment/offset pair, or `(0, 0)`
when no form exists:

```lua
local engine = require 'core.engine'
local generation = require 'core.generation'
local encoding = require 'core.encoding'
local m = engine.new_memory('LTGOLD/LTPRO.EXE', 'LTGOLD/BASE.RUS')
m:write_string(0xD000, 0, encoding.encode('дом') .. '\0')
local segment, offset = generation.noun_form(m, 0, 0xD000, 0, 1, 0, 1)
assert(encoding.decode(m:cstring(segment, offset)) == 'дома')
```

`noun_form` and `adjective_form` take gender, plural and case arguments;
`verb_form` additionally takes aspect, flags, person and past-tense state.
`participle_form` handles participial/gerund selectors; `pronoun_form` handles
pronoun agreement. These are native argument conventions, not a normalized
linguistic API. See the function definitions and differential fixtures for
case-index details.

Table rows contain a byte count to cut and a far pointer to space-separated
endings. `=` preserves the form and `-` rejects it. Operations count CP866 bytes.
Results share the DS:C858 scratch buffer, including writes on failed attempts
and bytes beyond the first NUL; callers must copy text if they need to keep it.
Original spelling quirks are retained for compatibility.

`tools/ltpro_morphology_probe.py` exercises every recovered table row and seeded
edge cases against the original instructions, using these production functions.
`demo/extract_morphology.lua` remains available for inspecting the binary tables.
