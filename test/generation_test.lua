-- Asset-free regression checks for the native generation/output memory ports.
local memory = require 'core.memory'
local generation = require 'core.generation'
local output = require 'core.output'
local m = memory.new()
m.ds = 0x1000
local ds = memory.linear(m.ds, 0)
local function str(off, value) m:write_string(m.ds, off, value .. '\0') end
for c = 0, 255 do m:set8(ds + 0xBF77 + c, memory.ctype(c)) end
assert(generation.case(0) == 0 and generation.case(1) == 0)
assert(generation.case(0x26) == 1 and generation.case(0x20) == 5)

-- Failed morphology still overwrites the common stem buffer. Successful
-- strncat also writes a NUL at original-length + suffix-length (beyond the
-- result's first NUL), leaving intervening bytes intact.
m:set16(ds + 0x5238, 2)
m:set_far(ds + 0x523A, m.ds, 0x300)
str(0x300, 'x - =')
str(0x400, 'abcd')
str(0xC858, 'ZZZZZZZZZZ')
local s, o = generation.noun_form(m, 0, m.ds, 0x400, 1, 0, 1)
assert(s == m.ds and o == 0xC858 and m:cstring(s, o) == 'abx')
assert(m:u8(ds + 0xC85C) == string.byte('Z') and m:u8(ds + 0xC85D) == 0)
s, o = generation.noun_form(m, 0, m.ds, 0x400, 1, 0, 2)
assert(s == 0 and o == 0 and m:cstring(m.ds, 0xC858) == 'ab')

-- Finite person zero copies the infinitive and returns before touching the
-- paradigm or appending interrogative/conditional particles.
s, o = generation.verb_form(m, 0xFFFF, m.ds, 0x400, 0, 0x12, 0, 0, 0, 1)
assert(m:cstring(s, o) == 'abcd')

-- Shared W-reading expansion retains a literal annotation and drops the
-- remainder after its closing marker, exactly as both native output loops do.
assert(output.reading(m, 'Wabc#literal#ignored') == '   literal')
assert(output.reading(m, 'W{literal}ignored') == 'literal')
assert(output.reading(m, 'plain') == 'plain')
assert(not pcall(output.reading, m, 'W{unterminated'))

-- A boundary + translated word + punctuation: source capitals change only
-- Cyrillic output, leaving Latin letters untouched; the buffer is appended.
local rs, root, boundary, word, punct = 0x3000, 0, 0x100, 0x400, 0x700
local function addr(o) return memory.linear(rs, o) end
m:set_far(addr(root), rs, boundary)
m:set_far(addr(boundary), rs, word)
m:set8(addr(boundary) + 9, 2)
m:set8(addr(boundary) + 0x0E, 0x44)
m:set8(addr(boundary) + 0x0D, 0x2A)
m:set_far(addr(word), rs, punct)
m:set8(addr(word) + 0x0E, 0x57)
m:set8(addr(word) + 0x0B, 2)
m:set8(addr(word) + 0x0C, 0x4E)
m:write_string(rs, word + 0x12, 'CAT\0')
m:set_far(addr(word) + 0x98, rs, word + 0x11C)
m:write_string(rs, word + 0x11C, '\xAA\xAE\xE2e\0')
m:set8(addr(punct) + 0x0E, 0x44)
m:set8(addr(punct) + 0x0D, 0x2E)
m:set8(addr(punct) + 0x12, 0x2E)
str(0x5F7, ' '); str(0x800, 'prefix:')
assert(output.sentence(m, rs, root, m.ds, 0x800) == 0)
assert(m:cstring(m.ds, 0x800) == 'prefix: \x8A\x8E\x92e.')
assert(m:cstring(rs, word + 0x11C) == '\x8A\x8E\x92e')
print('generation_test: passed')
