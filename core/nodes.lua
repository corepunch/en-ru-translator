local memory = require 'core.memory'
local heap = require 'core.heap'

local nodes = {}
local linear = memory.linear

-- Native lexical-node operations recovered from LTPRO 1313:000E and 1313:12DF.
-- Numeric keys are offsets into the original record; unknown fields stay unnamed.
function nodes.new(tag, fields)
  local node = fields or {}
  node[0x0C] = tag:byte()
  return node
end

-- 0687:0812 allocates a zeroed 15h-byte boundary record. This narrower
-- constructor is used with a null parent by T1; it is not a lexical-node clone.
function nodes.boundary(tag, marker, state)
  state = state or {}
  if state.limit and (state.count or 0) >= state.limit then return nil end
  local node
  if state.allocate then node=state.allocate() else node={} end
  if not node then return nil end
  for at=0,0x14 do node[at]=0 end
  node[0x0C],node[0x0D],node[0x0E]=tag:byte(),marker:byte(),0x44
  node[0x12],node[0x9C],node[0x11C]=tag,'',''
  state.count=(state.count or 0)+1
  return node
end

-- Import captured records without treating unnamed bytes as disposable padding.
-- Pointer identity is physical (segment*16+offset), not textual segment:offset.
function nodes.from_records(records)
  local addresses, ordered = {}, {}
  for i, record in ipairs(records) do
    local address = record.segment * 16 + record.offset
    local node = addresses[address]
    if not node then
      local raw = assert(record.bytes)
      assert(#raw >= 0x26B, 'truncated native lexical record')
      node = {raw=raw, native_address=address}
      for at = 0, #raw - 1 do node[at] = raw:byte(at + 1) end
      for _, at in ipairs({0x12,0x9C,0x11C,0x243}) do
        local stop = assert(raw:find('\0',at+1,true), 'unterminated native lexical string')
        node[at] = raw:sub(at+1,stop-1)
      end
      addresses[address] = node
    else
      assert(node.raw == record.bytes, 'conflicting aliased native record')
    end
    ordered[i] = node
  end
  for _, node in ipairs(ordered) do
    local offset, segment = string.unpack('<I2I2', node.raw)
    local address = segment * 16 + offset
    assert(address == 0 or addresses[address], 'unresolved native next pointer')
    node.next = addresses[address]
    -- +62 is a far pointer to a linked auxiliary record (T2 writes it). Keep an
    -- unresolved value as raw bytes rather than inventing a node for it.
    local aux_offset, aux_segment = string.unpack('<I2I2', node.raw, 0x63)
    local aux = aux_segment * 16 + aux_offset
    node.aux = addresses[aux]
    node.aux_raw = node.raw:sub(0x63, 0x66)
  end
  local vector = {}
  for i,node in ipairs(ordered) do vector[i-1] = node end
  return {next=ordered[1]}, vector, #ordered
end

function nodes.byte(node, offset)
  return node and node[offset] or 0
end

function nodes.tag(node)
  return string.char(nodes.byte(node, 0x0C))
end

function nodes.set_tag(node, tag)
  assert(node, 'missing native node')[0x0C] = tag:byte()
end

function nodes.set_marker(node, marker)
  assert(node, 'missing native node')[0x0F] = marker:byte()
end

function nodes.has_reading(node, tag)
  return (assert(node, 'missing native node')[0x11C] or ''):find(tag, 1, true) ~= nil
end

function nodes.link(records)
  local root, previous = {}, nil
  for _, node in ipairs(records) do
    if previous then previous.next = node else root.next = node end
    previous = node
  end
  if previous then previous.next = nil end
  return root
end

function nodes.vector(root)
  local vector, count, previous, node = {}, 0, nil, root.next
  while node and count < 512 do
    if node[0x0C] == 0x20 then
      local following = node.next
      if previous then previous.next = following else root.next = following end
      -- 0x16C4E preserves a removed X record as x; the object can have other owners.
      if node[0x0F] == 0x58 then node[0x0C] = 0x78 end
      node = following
    else
      vector[count] = node
      count = count + 1
      previous, node = node, node.next
    end
  end
  return vector, count
end

-- Return the live vector/count and a fresh mutable tag cache. Callers still
-- decide when to refresh: native handlers can retain stale counts or tags.
function nodes.rebuild(root)
  local vector, count = nodes.vector(root)
  local tags = {}
  for i = 0, count - 1 do tags[#tags + 1] = nodes.tag(vector[i]) end
  return vector, count, {tags = table.concat(tags)}
end

function nodes.swap(previous_a, a, previous_b, b)
  -- The original updates singly-linked next pointers and special-cases adjacent nodes.
  local next_a, next_b = a.next, b.next
  previous_a.next, previous_b.next = b, a
  a.next = next_b
  b.next = a == previous_b and a or next_a
end

-- 1313:000E: collect the records of the list at (seg, off) into `vector`
-- and their tags into DS:C5AE, unlinking blank (' ') records: their
-- auxiliary record (+62) and its sub-rules are freed, and the record itself
-- with its sub-rules (+94) unless it is an 'X' record, which is only retagged
-- 'x' (it is referenced elsewhere). At most 200h records. Returns the count.
function nodes.rebuild_memory(m, seg, off, vector)
  local ds = m.ds
  local si = 0
  local pseg, poff = m:far(linear(seg, off))
  local cseg, coff = pseg, poff
  while not memory.null(cseg, coff) do
    local r = linear(cseg, coff)
    if m:u8(r + 0x0C) ~= 0x20 then
      vector[si] = {cseg, coff}
      m:set8(linear(ds, (0xC5AE + si) & 0xFFFF), m:u8(r + 0x0C))
      si = si + 1
      pseg, poff = cseg, coff
    else
      m:set_far(linear(pseg, poff), m:far(r))
      if m:u8(r + 0x0E) == 0x57 and not memory.null(m:far(r + 0x62)) then
        local aseg, aoff = m:far(r + 0x62)
        local a = linear(aseg, aoff)
        if not memory.null(m:far(a + 0x94)) then heap.free(m, m:far(a + 0x94)) end
        heap.free(m, aseg, aoff)
      end
      if m:u8(r + 0x0F) == 0x58 then
        m:set8(r + 0x0C, 0x78)
      else
        if m:u8(r + 0x0E) == 0x57 and not memory.null(m:far(r + 0x94)) then heap.free(m, m:far(r + 0x94)) end
        heap.free(m, cseg, coff)
      end
    end
    cseg, coff = m:far(linear(pseg, poff))
    if si >= 0x200 then break end
  end
  vector[si] = {0, 0}
  m:set8(linear(ds, (0xC5AE + si) & 0xFFFF), 0)
  return si
end

-- Materialize the native-node table model as LTPRO heap records.
--
-- This is deliberately explicit: callers provide a memory image with the
-- Borland heap initialized, and this module allocates records with that heap.
-- It does not initialize DOS startup state or infer pointers from snapshots.

local STRING_FIELDS = { [0x12] = true, [0x9C] = true, [0x11C] = true, [0x243] = true }
-- These node-table APIs hold the full word at its low-byte offset. Imported
-- raw records still expose the two constituent bytes, which we recombine.
local WORD_FIELDS = { [0x10] = true, [0x87] = true }

local function write_string(m, segment, offset, field_offset, text)
  assert(type(text) == 'string', string.format('node string +%X must be a string', field_offset))
  assert(not text:find('\0', 1, true), string.format('node string +%X contains an embedded NUL', field_offset))
  assert(#text < heap.RECORD_SIZE - field_offset,
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
    local segment, offset = heap.calloc(m, 1, heap.RECORD_SIZE)
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
function nodes.serialize(m, root)
  assert(m and m.ds and m.library_segment,
    'memory must have initialized DS and library_segment fields')
  local queue, nodes = allocate_graph(m, root)

  for _, node in ipairs(queue) do
    local ptr = nodes[node]
    local base = linear(ptr.segment, ptr.offset)

    -- Captures carry all record bytes, including unnamed and word fields.
    -- New lexical nodes instead begin zeroed and overlay the numeric byte map.
    if node.raw then
      assert(#node.raw >= heap.RECORD_SIZE, 'truncated native lexical record')
      m:write_string(ptr.segment, ptr.offset, node.raw:sub(1, heap.RECORD_SIZE))
    end
    for at = 0, heap.RECORD_SIZE - 1 do
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

return nodes
