-- Self-contained checks of the post-reorder runtime pieces (no assets needed).
-- Full verification against native code: tools/ltpro_post_chain.py,
-- tools/ltpro_function_probe.py and tools/ltpro_post_fuzz.py (see
-- reference/LTPRO_HANDOVER.md).
local memory = require 'core.ltpro.memory'
local runtime = require 'core.ltpro.runtime'
local clib = require 'core.ltpro.clib'

local DS = 0x2AF7
local m = memory.new()
m.ds = DS
m.library_segment = DS - 0x22D5

-- Far pointers keep their segment:offset form; offsets wrap at 64K.
m:set_far(0x100, 0x1234, 0xFFFF)
local s, o = m:far(0x100)
assert(s == 0x1234 and o == 0xFFFF and m:far_linear(0x100) == 0x1234 * 16 + 0xFFFF)
m:write_string(0x2000, 0, 'abc\0')
assert(m:cstring(0x2000, 0) == 'abc')
local ss, so = m:strchr(0x2000, 0, 0)
assert(ss == 0x2000 and so == 3, 'strchr finds the terminator')
assert(select(2, m:strrchr(0x2000, 0, 0x62)) == 1)

-- CP866 letter classes (211E:113A/115A/117F).
assert(runtime.is_upper_cyrillic(0x80) and runtime.is_upper_cyrillic(0xF0) and not runtime.is_upper_cyrillic(0xA0))
assert(runtime.is_lower_cyrillic(0xA0) and runtime.is_lower_cyrillic(0xF1) and not runtime.is_lower_cyrillic(0xF2))
assert(runtime.is_cyrillic(0xAF) and not runtime.is_cyrillic(0xB0))
assert(runtime.ctype(0x37) == 2 and runtime.ctype(0x41) == 0x14 and runtime.ctype(0xA0) == 0)

-- 2104:0002 suffix test and 2104:008C tokenizer state in DS:BDA8..BDB0.
m:write_string(0x3000, 0, 'word\0' .. 'rd\0')
assert(runtime.ends_with(m, 0x3000, 0, 4, 0x3000, 5) == 2)
assert(runtime.ends_with(m, 0x3000, 0, 1, 0x3000, 5) == 0)
m:write_string(0x3100, 0, '<AB>NV`x`\0' .. '`~<[!\0')
local token
local ts, to = runtime.gettoken(m, 0x3100, 4, 0x3100, 10, function(t) token = t end)
assert(token == 'NV' and ts == 0x3100 and to == 4)
assert(m:u16(memory.linear(DS, 0xBDB0)) == 2)
assert(select(2, m:far(memory.linear(DS, 0xBDAC))) == 6)

-- Borland qsort keeps native tie order: sorting (length, index) pairs by
-- descending length, as 1E71:0BA0 does; expected order from the original
-- code run in the 8086 harness.
local pairs = {{2,0},{3,1},{2,2},{1,3},{3,4},{2,5},{3,6},{1,7}}
for i, p in ipairs(pairs) do
  m:set16(memory.linear(DS, 0xC808 + 4 * (i - 1)), p[1])
  m:set16(memory.linear(DS, 0xC80A + 4 * (i - 1)), p[2])
end
clib.qsort(m, DS, 0xC808, #pairs, 4, function(mm, seg, a, b)
  local v = (mm:u16(memory.linear(seg, b)) - mm:u16(memory.linear(seg, a))) & 0xFFFF
  return v >= 0x8000 and v - 0x10000 or v
end)
local got = {}
for i = 0, #pairs - 1 do got[#got + 1] = m:u16(memory.linear(DS, 0xC80A + 4 * i)) end
assert(table.concat(got, ',') == '4,1,6,5,2,0,3,7', table.concat(got, ','))
print('ltpro_post_stages_test: passed')
