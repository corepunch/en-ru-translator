-- Materialize the native-node table model as LTPRO heap records.
--
-- This is deliberately explicit: callers provide a memory image with the
-- Borland heap initialized, and this module allocates records with that heap.
-- It does not initialize DOS startup state or infer pointers from snapshots.
local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'
local records = require 'core.ltpro.records'

local bridge = {}
local linear = memory.linear

local STRING_FIELDS = { [0x12] = true, [0x9C] = true, [0x11C] = true, [0x243] = true }
-- These node-table APIs hold the full word at its low-byte offset. Imported
-- raw records still expose the two constituent bytes, which we recombine.
local WORD_FIELDS = { [0x10] = true, [0x87] = true }

local function write_string(m, segment, offset, field_offset, text)
  assert(type(text) == 'string', string.format('node string +%X must be a string', field_offset))
  assert(not text:find('\0', 1, true), string.format('node string +%X contains an embedded NUL', field_offset))
  assert(#text < records.SIZE - field_offset,
    string.format('node string +%X exceeds record size', field_offset))
  m:write_string(segment, offset, text .. '\0')
end

local function allocate_graph(m, root)
  assert(type(root) == 'table', 'expected a node root')
  local nodes, queue, seen = {}, {}, {}
  local function include(node)
    if node == nil or seen[node] then return end
    assert(type(node) == 'table', 'node link must target a table node')
    seen[node] = true
    queue[#queue + 1] = node
  end
  include(root.next)
  local cursor = 1
  while cursor <= #queue do
    local node = queue[cursor]
    cursor = cursor + 1
    include(node.next)
    include(node.aux)
  end

  for _, node in ipairs(queue) do
    local segment, offset = heap.calloc(m, 1, records.SIZE)
    assert(not memory.null(segment, offset), 'native heap could not allocate lexical record')
    nodes[node] = {segment = segment, offset = offset}
  end
  return queue, nodes
end

-- Convert a linked node root into native lexical records.
--
-- Returns {root={segment,offset}, nodes=node_to_far_pointer,
--          ordered={node,...}, count=n}. Each reachable node is allocated
-- once, including auxiliary nodes reachable through `node.aux`. `root` is
-- the table-model sentinel and is not itself a native record.
function bridge.serialize(m, root)
  assert(m and m.ds and m.library_segment,
    'memory must have initialized DS and library_segment fields')
  local queue, nodes = allocate_graph(m, root)

  for _, node in ipairs(queue) do
    local ptr = nodes[node]
    local base = linear(ptr.segment, ptr.offset)

    -- Captures carry all record bytes, including unnamed and word fields.
    -- New lexical nodes instead begin zeroed and overlay the numeric byte map.
    if node.raw then
      assert(#node.raw >= records.SIZE, 'truncated native lexical record')
      m:write_string(ptr.segment, ptr.offset, node.raw:sub(1, records.SIZE))
    end
    for at = 0, records.SIZE - 1 do
      local value = node[at]
      if type(value) == 'number' then
        if WORD_FIELDS[at] then
          local word
          if value > 0xFF or value < 0 then
            word = value
          else
            local high = type(node[at + 1]) == 'number' and node[at + 1] or 0
            word = (high << 8) | value
          end
          m:set16(base + at, word)
        else
          m:set8(base + at, value)
        end
      end
    end
    for at in pairs(STRING_FIELDS) do
      local value = node[at]
      if type(value) == 'string' then
        write_string(m, ptr.segment, (ptr.offset + at) & 0xFFFF, at, value)
      end
    end

    -- +0 chains lexical records; +62 links an auxiliary record. The +98
    -- pointer is the native self-relative translation string pointer.
    local next_ptr = node.next and nodes[node.next]
    if next_ptr then m:set_far(base, next_ptr.segment, next_ptr.offset)
    else m:set_far(base, 0, 0) end
    local aux_ptr = node.aux and nodes[node.aux]
    if aux_ptr then
      m:set_far(base + 0x62, aux_ptr.segment, aux_ptr.offset)
    elseif node.aux_raw then
      assert(#node.aux_raw == 4, 'aux_raw must contain one four-byte far pointer')
      local aux_offset, aux_segment = string.unpack('<I2I2', node.aux_raw)
      assert(memory.null(aux_segment, aux_offset),
        'unresolved auxiliary pointer: include its native auxiliary record before bridging')
      m:set_far(base + 0x62, 0, 0)
    else
      m:set_far(base + 0x62, 0, 0)
    end
    m:set_far(base + 0x98, ptr.segment, (ptr.offset + 0x11C) & 0xFFFF)
  end

  local ordered, t4_rules, node = {}, {}, root.next
  while node do
    ordered[#ordered + 1] = node
    if node.rules and #node.rules > 0 then t4_rules[node] = node.rules end
    node = node.next
  end
  local root_ptr = nodes[root.next]
  return {
    root = root_ptr or {segment = 0, offset = 0},
    nodes = nodes,
    ordered = ordered,
    count = #ordered,
    -- T4's current per-word rules are Lua-side matcher inputs; no native
    -- backing-record layout for them is represented by the lexical node.
    t4_rules = t4_rules,
  }
end

return bridge
