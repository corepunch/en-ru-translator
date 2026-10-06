-- Synthetic records catch layout errors without requiring the ignored LTPRO executable.
local binary = require "demo.ltpro_binary"
local bytes = {}
for i = 1, 256 do bytes[i] = "\0" end
local function put(offset, value)
  for i = 1, #value do bytes[offset + i] = value:sub(i, i) end
end
local function u16(value) return string.pack("<I2", value) end
local function pointer(offset, segment) return u16(offset) .. u16(segment) end
put(0, "MZ")
put(8, u16(2))
-- Header 32 + segment 8*16 + offset 0 = 160: offset zero is a valid far pointer.
put(160, "N\0")
put(170, "23\0")
put(180, "ies\0")
put(190, "Z13\0")
put(40, pointer(0, 8) .. pointer(10, 8) .. string.char(0x3C))
put(64, pointer(0, 8) .. u16(1) .. u16(4))
put(88, u16(13) .. pointer(20, 8) .. pointer(30, 8))
put(112, pointer(0, 8) .. pointer(0, 0) .. u16(9))
put(136, u16(3) .. pointer(10, 8))
local reader = binary.new(table.concat(bytes))
local t4 = reader.records({ name = "T4", offset = 40, count = 1, size = 9 })[1]
assert(t4.pattern == "N" and t4.action == "23" and t4.flag == 0x3C)
local guard = reader.records({ name = "guard", offset = 64, count = 1, size = 8 })[1]
assert(guard.endpoint_order == 1 and guard.flag == 4 and guard.action == nil)
local suffix = reader.records({ name = "suffix", offset = 88, count = 1, size = 10, suffix = true })[1]
assert(suffix.flag == 13 and suffix.suffix == "ies" and suffix.tag == "Z13")
local no_action = reader.records({ name = "rewrite", offset = 112, count = 1, size = 10 })[1]
assert(no_action.action == nil and no_action.flag == 9)
local morphology = reader.morphology({offset = 136, count = 1})[1]
assert(morphology[1] == 3 and morphology[2] == '23')
put(72, "x")
assert(not pcall(function()
  binary.new(table.concat(bytes)).records({ name = "bad sentinel", offset = 64, count = 1, size = 8 })
end))
put(64, pointer(0, 0xFFFF))
assert(not pcall(function() binary.new(table.concat(bytes)).string_at(64) end))
assert(not pcall(binary.new, "not an executable"))
print("LTPRO binary reader tests passed")
