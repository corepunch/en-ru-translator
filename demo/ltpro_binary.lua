-- Read the unpacked DOS image directly; offsets are file coordinates, not r2 addresses.
local binary = {}
binary.layouts = {
  { name = "T1", offset = 0x2738C, count = 47, size = 10, lua_index = 1 },
  { name = "T2", offset = 0x2756C, count = 157, size = 10, lua_index = 2 },
  { name = "T3", offset = 0x27B98, count = 136, size = 10, lua_index = 3 },
  -- 0x14954 loads DS:2DDC; 0x149BF reads the handler at record+8.
  { name = "T4", offset = 0x2952C, count = 178, size = 9, lua_index = 4 },
  -- The scanner at 0x161CB traverses both blocks before reaching one sentinel.
  { name = "T5", offset = 0x2A740, count = 9, size = 10, lua_index = 5, no_sentinel = true },
  { name = "T6", offset = 0x2A79A, count = 47, size = 10, lua_index = 6 },
  { name = "cleanup", offset = 0x2AB30, count = 9, size = 10, lua_index = 7 },
  { name = "T7", offset = 0x2AC92, count = 35, size = 8, lua_index = 8 },
  { name = "T7-adjective", offset = 0x2ADB2, count = 1, size = 8, lua_key = "adjective" },
  { name = "T8", offset = 0x2B134, count = 83, size = 8, lua_index = 9 },
  -- 1C3D:1B3F, the 21-selector constituent rule pass (DS:4FEC).
  { name = "constituent", offset = 0x2B73C, count = 15, size = 8, lua_key = "constituent" },
}
binary.suffix_layout = { name = "suffix", offset = 0x26EC6, count = 43, size = 10, suffix = true }

-- Six-byte morphology records retain the cut count, including adjective entries.
-- These arrays are followed by spelling-pattern pointer arrays, not zero sentinels.
binary.morphology_layouts = {
  { name = "nouns", gender = 1, offset = 0x2BCF6, gold_offset = 0x55FF8, count = 33 },
  { name = "nouns", gender = 2, offset = 0x2B988, gold_offset = 0x55C8A, count = 66 },
  { name = "nouns", gender = 3, offset = 0x2BBA0, gold_offset = 0x55EA2, count = 35 },
  { name = "adjectives", gender = 1, offset = 0x2BF5C, gold_offset = 0x5625E, count = 26 },
  { name = "adjectives", gender = 2, offset = 0x2BE24, gold_offset = 0x56126, count = 26 },
  { name = "adjectives", gender = 3, offset = 0x2BEC0, gold_offset = 0x561C2, count = 26 },
  { name = "imperfective", offset = 0x2C1A0, gold_offset = 0x564A2, count = 106 },
  { name = "verbs", offset = 0x2C5E0, gold_offset = 0x568E2, count = 113 },
}

-- These locations were resolved from far-pointer references in LTGOLD.EXE itself.
-- Cleanup precedes the reorder array there; a uniform LTPRO-to-LTGOLD shift is wrong.
binary.gold_offsets = { 0x5168E, 0x5186E, 0x51E9A, 0x5382E, 0x54B4A,
  0x54BA4, 0x54A42, 0x54F94, 0x550B4, 0x55436 }
binary.dispatch_layouts = {
  { name = "T1", cs = 0x11BF0, offset = 0x26D3, count = 15, sparse = true, default = 0x124A8 },
  { name = "T2", cs = 0x11BF0, offset = 0x2659, count = 61, default = 0x13670 },
  { name = "T3", cs = 0x11BF0, offset = 0x2593, count = 99, default = 0x14104 },
  { name = "T4", cs = 0x142F0, offset = 0x1D9F, count = 99, default = 0x16009 },
  { name = "reorder", cs = 0x16190, offset = 0x601, count = 13, sparse = true, default = 0x165A1 },
  { name = "cleanup", cs = 0x167C0, offset = 0x324, count = 11, default = 0x16A6B },
  { name = "T7", cs = 0x17E90, offset = 0xCF5, count = 23, default = 0x18B4F },
  { name = "T7_select", cs = 0x17E90, offset = 0xD23, count = 19, sparse = true, default = 0x17EE2 },
  { name = "T8", cs = 0x1D260, offset = 0x2AE5, count = 70, default = 0x1FCCB },
}

function binary.new(bytes)
  assert(bytes:sub(1, 2) == "MZ", "expected an unpacked MZ executable")
  local reader = {}
  function reader.u8(offset)
    return assert(bytes:byte(offset + 1), string.format("offset 0x%X outside image", offset))
  end
  function reader.u16(offset)
    return reader.u8(offset) + 256 * reader.u8(offset + 1)
  end
  local header_size = reader.u16(8) * 16
  assert(header_size >= 28 and header_size < #bytes, "invalid MZ header size")
  function reader.string_at(pointer)
    local offset, segment = reader.u16(pointer), reader.u16(pointer + 2)
    if offset == 0 and segment == 0 then return nil end
    -- Resolve both far-pointer words; a zero offset with a nonzero segment is valid.
    local address = header_size + segment * 16 + offset
    assert(address >= header_size and address < #bytes, "far pointer outside image")
    local stop = assert(bytes:find("\0", address + 1, true), "unterminated image string")
    return bytes:sub(address + 1, stop - 1)
  end
  function reader.records(layout)
    local records = {}
    for i = 0, layout.count - 1 do
      local address = layout.offset + i * layout.size
      local record = { address = address }
      if layout.suffix then
        record.flag = reader.u16(address)
        record.suffix = assert(reader.string_at(address + 2), "null suffix pointer")
        record.tag = assert(reader.string_at(address + 6), "null suffix tag pointer")
      else
        record.pattern = assert(reader.string_at(address), "null rule pattern pointer")
        if layout.size == 8 then
          -- Guard +4 is a scalar, not an action pointer (endpoint swap at 0x17F29).
          record.endpoint_order = reader.u16(address + 4)
          record.flag = reader.u16(address + 6)
        else
          record.action = reader.string_at(address + 4)
          record.flag = layout.size == 9 and reader.u8(address + 8) or reader.u16(address + 8)
        end
      end
      records[#records + 1] = record
    end
    if not layout.no_sentinel then
      local sentinel = layout.offset + layout.count * layout.size
      for i = 0, layout.size - 1 do
        assert(reader.u8(sentinel + i) == 0, layout.name .. ": invalid table sentinel")
      end
    end
    return records
  end
  function reader.dispatch(layout)
    local result = {}
    for i = 0, layout.count - 1 do
      local key = layout.sparse and reader.u16(layout.cs + layout.offset + i * 2) or i + 1
      local targets = layout.offset + (layout.sparse and layout.count * 2 or 0)
      local address = layout.cs + reader.u16(layout.cs + targets + i * 2)
      assert(address >= header_size and address < #bytes, "handler outside image")
      result[#result + 1] = { id = key, address = address }
    end
    return result
  end
  function reader.morphology(layout)
    local records = {}
    for i = 0, layout.count - 1 do
      local address = layout.offset + i * 6
      records[#records + 1] = {
        reader.u16(address), assert(reader.string_at(address + 2), "null morphology pointer")
      }
    end
    return records
  end
  return reader
end

function binary.read(path)
  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()
  return binary.new(bytes)
end

return binary
