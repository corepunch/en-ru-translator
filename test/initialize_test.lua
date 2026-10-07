package.path = './?.lua;./?/init.lua;' .. package.path

local engine = require 'core.engine'
local memory = require 'core.memory'
local heap = require 'core.heap'
local russian = require 'core.russian'
local senses = require 'core.senses'
local generation = require 'core.generation'
local encoding = require 'core.encoding'

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local bytes = file:read('*a')
  file:close()
  return bytes
end

local exe = read('LTGOLD/LTPRO.EXE')
local rus = read('LTGOLD/BASE.RUS')
local m = engine.new_memory(exe, rus) -- exercise byte-string inputs
assert(m.ds == 0x22D5 and m.library_segment == 0)
assert(m.files[5] == rus and m.positions[5] == 0)

local ds = memory.linear(m.ds, 0)
assert(m:u8(ds + 0xBF77) == 0x20) -- copied static ctype table
assert(m:u8(ds + 0xBCE8) == 0 and m:u8(ds + 0xBCE9) == 8)
assert(m:u16(ds + 0x044D) == 512)
assert(m:u16(ds + 0xBBB6) == 1 and m:u16(ds + 0xBB9E) == 0)

local dseg, doff = m:far(ds + 0xC8B4)
assert(not memory.null(dseg, doff))
local d = memory.linear(dseg, doff)
assert(m:u8(d + 0x5C) == 0x52 and m:u16(d + 0x60) == 0x20)
assert(m:u32(d + 0x66) == 160089 and m:u16(d + 0x6A) == 5)
local iseg, ioff = m:far(d + 0x7C)
local index = rus:sub(160089 + 1)
for i = 1, #index do
  assert(m:u8(memory.linear(iseg, ioff + i - 1)) == index:byte(i), 'index byte mismatch at ' .. i)
end

-- Exercise calloc/free and confirm newly allocated records use the native
-- 26Bh-byte layout on the initialized Borland heap.
local scratch_seg, scratch_off = heap.calloc(m, 1, 24)
assert(scratch_seg ~= 0 and m:u8(memory.linear(scratch_seg, scratch_off)) == 0)
heap.free(m, scratch_seg, scratch_off)

local key = encoding.encode('дом') .. '\0'
m:write_string(m.ds, 0xF000, key)
local key_seg, key_off = heap.strdup(m, m.ds, 0xF000)
local line_seg, line_off = russian.lookup(m, m.ds, 0xC8B4, key_seg, key_off, 0)
assert(not memory.null(line_seg, line_off))
assert(m:cstring(line_seg, line_off):find(encoding.encode('дом') .. '*N', 1, true),
  'BASE.RUS lookup did not find дом')

local record_seg, record_off = heap.new_record(m, 0, 0, 0x4E, key_seg, key_off)
assert(record_seg ~= 0)
local record = memory.linear(record_seg, record_off)
local star_seg, star_off = m:strchr(line_seg, line_off, 0x2A)
assert(not memory.null(star_seg, star_off))
assert(m:u8(memory.linear(star_seg, star_off + 1)) == 0x4E)
senses.store_code(m, 0, star_seg, star_off + 2, record_seg, record_off)
assert(m:u8(record + 0x6D) == 0x80 and m:u8(record + 0x6E) == 0x81 and m:u8(record + 0x6F) == 0x80)
assert(m:u16(record + 0x85) == 0)

local result_seg, result_off = generation.noun_form(m, m:u16(record + 0x85), record_seg, record_off + 0x11C,
  m:u8(record + 0x77), m:u8(record + 0x72), 1)
assert(not memory.null(result_seg, result_off))
assert(m:cstring(result_seg, result_off) == encoding.encode('дома'),
  'BASE.RUS paradigm did not produce the expected genitive')

local from_paths = engine.new_memory('LTGOLD/LTPRO.EXE', 'LTGOLD/BASE.RUS')
assert(from_paths.ds == 0x22D5 and from_paths.files[5] ~= nil)
assert(not pcall(engine.new_memory, 'missing-LTPRO.EXE', rus), 'missing path was treated as raw bytes')

print('LTPRO snapshot-free initializer: PASS')
