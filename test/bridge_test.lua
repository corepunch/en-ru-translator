local memory = require 'core.memory'
local nodes = require 'core.nodes'
local m = memory.new()
local DS = 0x2AF7
m.ds = DS
m.library_segment = DS - 0x22D5
local heap_segment = 0x3000
local heap_bytes = 0x1000
local first = memory.linear(m.library_segment, 0x1A6A)
local last = memory.linear(m.library_segment, 0x1A6C)
local rover = memory.linear(m.library_segment, 0x1A6E)
m:set16(first, heap_segment); m:set16(last, heap_segment); m:set16(rover, heap_segment)
m:set16(memory.linear(heap_segment, 0), heap_bytes // 16)
m:set16(memory.linear(heap_segment, 2), 0)
m:set16(memory.linear(heap_segment, 4), heap_segment)
m:set16(memory.linear(heap_segment, 6), heap_segment)

local root = {}
local first_node = nodes.new('N', {
  [0x0D] = 0x42, [0x0E] = 0x57, [0x10] = 0x1234,
  [0x12] = 'cat', [0x9C] = 'source metadata', [0x11C] = '\x81\x82translation',
  [0x243] = string.rep('x', 39), [0x87] = 0x3456,
})
local tail = nodes.new('*', {[0x0E] = 0x44, [0x12] = '*', [0x11C] = ''})
root.next, first_node.next = first_node, tail
first_node.aux = tail -- An auxiliary link aliases a node already in the sentence.
first_node.rules = {{pattern = 'NV', action = 'Nперевод'}}

local exported = nodes.serialize(m, root)
assert(exported.count == 2 and exported.ordered[1] == first_node and exported.ordered[2] == tail)
assert(exported.t4_rules[first_node] == first_node.rules)
assert(exported.nodes[first_node].segment ~= exported.nodes[tail].segment or
       exported.nodes[first_node].offset ~= exported.nodes[tail].offset)
local p = exported.nodes[first_node]
local base = memory.linear(p.segment, p.offset)
assert(m:u16(base + 0x10) == 0x1234)
assert(m:u16(base + 0x87) == 0x3456)
assert(m:cstring(p.segment, (p.offset + 0x12) & 0xFFFF) == 'cat')
assert(m:cstring(p.segment, (p.offset + 0x9C) & 0xFFFF) == 'source metadata')
assert(m:cstring(p.segment, (p.offset + 0x11C) & 0xFFFF) == '\x81\x82translation')
assert(m:cstring(p.segment, (p.offset + 0x243) & 0xFFFF) == string.rep('x', 39))
local ns, no = m:far(base)
assert(ns == exported.nodes[tail].segment and no == exported.nodes[tail].offset)
local as, ao = m:far(base + 0x62)
assert(as == exported.nodes[tail].segment and ao == exported.nodes[tail].offset)
local ts, to = m:far(base + 0x98)
assert(ts == p.segment and to == ((p.offset + 0x11C) & 0xFFFF))

-- Imported records retain their unnamed bytes when moved to different heap
-- addresses; only address-bearing fields are expected to change.
local raw = {}
for i = 0, 0x26A do raw[i + 1] = string.char((i * 37 + 11) & 0xFF) end
for _, at in ipairs({0, 1, 2, 3, 0x12, 0x9C, 0x11C, 0x243, 0x62, 0x63, 0x64, 0x65}) do
  raw[at + 1] = '\0'
end
local raw_bytes = table.concat(raw)
local imported_root, vector = nodes.from_records({
  {segment = 0x7000, offset = 0x10, bytes = raw_bytes},
})
local moved = nodes.serialize(m, imported_root)
local q = moved.nodes[vector[0]]
local moved_base = memory.linear(q.segment, q.offset)
for at = 0, 0x26A do
  if not ((at >= 0 and at <= 3) or (at >= 0x62 and at <= 0x65) or (at >= 0x98 and at <= 0x9B)) then
    assert(m:u8(moved_base + at) == raw_bytes:byte(at + 1), string.format('raw byte +%X changed', at))
  end
end

-- A captured non-null auxiliary pointer whose record was not imported cannot
-- be reused after allocation moves the lexical record.
local dangling_bytes = raw_bytes:sub(1, 0x62) .. string.pack('<I2I2', 0x1234, 0x7000) .. raw_bytes:sub(0x67)
local dangling_root = nodes.from_records({
  {segment = 0x7100, offset = 0x10, bytes = dangling_bytes},
})
local ok, err = pcall(nodes.serialize, m, dangling_root)
assert(not ok and tostring(err):find('unresolved auxiliary pointer', 1, true))
print('bridge_test: passed')
