local layout = require 'core.record_layout'
local captured = {}

-- Import captured records without treating unnamed bytes as disposable padding.
-- Pointer identity is physical (segment*16+offset), not textual segment:offset.
function captured.from_records(records)
  local addresses, ordered = {}, {}
  for i, record in ipairs(records) do
    local address = record.segment * 16 + record.offset
    local node = addresses[address]
    if not node then
      local raw = assert(record.bytes)
      assert(#raw >= 0x26B, 'truncated native lexical record')
      node = {raw=raw, native_address=address}
      for at = 0, #raw - 1 do node[layout.key(at)] = raw:byte(at + 1) end
      for _, at in ipairs({0x12,0x9C,0x11C,0x21B,0x243}) do
        local stop = assert(raw:find('\0',at+1,true), 'unterminated native lexical string')
        node[layout.key(at)] = raw:sub(at+1,stop-1)
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

return captured
