local encoding = require "encoding"

-- Exercise the pure boundary directly; CLI behavior is covered separately by
-- piping the same bytes through bin/encoding.lua.
local utf8 = "Привет, мир! ё"
local cp866 = encoding.encode(utf8)
assert(cp866 ~= utf8)
assert(encoding.decode(cp866) == utf8)
assert(encoding.decode(encoding.encode("ASCII")) == "ASCII")
print("encoding tests passed")
