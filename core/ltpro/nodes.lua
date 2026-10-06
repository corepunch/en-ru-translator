-- Native lexical-node operations recovered from LTPRO 1313:000E and 1313:12DF.
-- Numeric keys are offsets into the original record; unknown fields stay unnamed.
local nodes = {}

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

function nodes.swap(previous_a, a, previous_b, b)
  -- The original updates singly-linked next pointers and special-cases adjacent nodes.
  local next_a, next_b = a.next, b.next
  previous_a.next, previous_b.next = b, a
  a.next = next_b
  b.next = a == previous_b and a or next_a
end

return nodes
