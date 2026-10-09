local encoding = require "core.encoding"

-- Exercise the pure boundary directly; CLI behavior is covered separately by
-- piping the same bytes through bin/encoding.lua.
local utf8 = "Привет, мир! ё"
local cp866 = encoding.encode(utf8)
assert(cp866 ~= utf8)
assert(encoding.decode(cp866) == utf8)
assert(encoding.decode(encoding.encode("ASCII")) == "ASCII")
assert(encoding.encode('Ёё')=='\xF0\xF1')
assert(encoding.decode('\xF0\xF1')=='Ёё')
assert(encoding.encode("I’m, I‘m, I'm") == "I'm, I'm, I'm")
assert(encoding.decode(encoding.encode("‘Привет’")) == "'Привет'")
print("encoding tests passed")
