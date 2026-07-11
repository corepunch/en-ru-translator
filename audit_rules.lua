-- Verify that rules.lua preserves every rule record extracted from LTPRO.EXE.
-- This is intentionally independent of the parser so matcher bugs cannot hide extraction drift.
local utils = require "utils"
local rules = require "rules"

local path = arg[1] or "LTGOLD/LTPRO.EXE"  -- NOTE: LTGOLD/ LTPRO.EXE is a binary tool, not a data file
local file = assert(io.open(path, "rb"))
local exe = file:read("*all")
file:close()

local data_base = 0x26750
local layouts = {
  { offset = 0x2738C, count = 47,  size = 10, flag = 8, pattern = 0, action = 4 },
  { offset = 0x2756C, count = 157, size = 10, flag = 8, pattern = 0, action = 4 },
  { offset = 0x27B98, count = 136, size = 10, flag = 8, pattern = 0, action = 4 },
  { offset = 0x2952B, count = 178, size = 9,  flag = 0, pattern = 1, action = 5, byte_flag = true },
  { offset = 0x2A740, count = 9,   size = 10, flag = 8, pattern = 0, action = 4, no_sentinel = true },
  { offset = 0x2A79A, count = 47,  size = 10, flag = 8, pattern = 0, action = 4 },
  { offset = 0x2AB30, count = 9,   size = 10, flag = 8, pattern = 0, action = 4 },
  { offset = 0x2AC92, count = 35,  size = 8,  flag = 6, pattern = 0, action = 4 },
  { offset = 0x2B134, count = 83,  size = 8,  flag = 6, pattern = 0, action = 4 },
}

local function byte(offset)
  return assert(exe:byte(offset + 1), string.format("offset 0x%X is outside %s", offset, path))
end

local function u16(offset)
  return byte(offset) + byte(offset + 1) * 256
end

local function cstring(offset)
  if offset == 0 then return "" end
  local stop = assert(exe:find("\0", offset + 1, true), "unterminated EXE string")
  return exe:sub(offset + 1, stop - 1)
end

local failures = 0
for ti, layout in ipairs(layouts) do
  local lua_table = assert(rules[ti], "rules.lua is missing T" .. ti)
  if #lua_table ~= layout.count then
    io.stderr:write(string.format("T%d count: Lua=%d EXE=%d\n", ti, #lua_table, layout.count))
    failures = failures + 1
  end
  for ri = 0, math.min(#lua_table, layout.count) - 1 do
    local record = layout.offset + ri * layout.size
    local expected_flag = layout.byte_flag and byte(record + layout.flag) or u16(record + layout.flag)
    local expected_pattern = utils.decode(cstring(data_base + u16(record + layout.pattern)), false)
    local action_pointer = u16(record + layout.action)
    local expected_action = action_pointer == 0 and "" or
      utils.decode(cstring(data_base + action_pointer), false)
    local actual_flag, actual_pattern, actual_action = table.unpack(lua_table[ri + 1])
    actual_action = actual_action or ""
    if actual_flag ~= expected_flag or actual_pattern ~= expected_pattern or actual_action ~= expected_action then
      failures = failures + 1
      io.stderr:write(string.format(
        "T%d[%d] differs\n  EXE: 0x%X %q %q\n  Lua: 0x%X %q %q\n",
        ti, ri, expected_flag, expected_pattern, expected_action,
        actual_flag or -1, actual_pattern or "", actual_action
      ))
    end
  end
  if not layout.no_sentinel then
    local sentinel = layout.offset + layout.count * layout.size
    for i = 0, layout.size - 1 do
      if byte(sentinel + i) ~= 0 then
        failures = failures + 1
        io.stderr:write(string.format("T%d has no zero sentinel at 0x%X\n", ti, sentinel))
        break
      end
    end
  end
end

if failures > 0 then
  io.stderr:write(string.format("Rule extraction audit failed: %d difference(s)\n", failures))
  os.exit(1)
end

print("Rule extraction audit passed: all 9 rule blocks, 701 records")
