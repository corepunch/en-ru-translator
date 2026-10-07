local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'
local spec = dofile(arg[1])
local f = assert(io.open(spec.memory, 'rb')); local base = f:read('a'); f:close()
local m = memory.new(base)
m.ds, m.library_segment = spec.ds, spec.ds - 0x22D5
for i, op in ipairs(spec.operations) do
  local seg, off = 0, 0
  if op[1] == 'free' then heap.free(m, op[3], op[2])
  elseif op[1] == 'malloc' then seg, off = heap.malloc(m, op[2])
  else seg, off = heap.calloc(m, op[2], op[3]) end
  local want = spec.results[i]
  if op[1] ~= 'free' and (off ~= want[1] or seg ~= want[2]) then
    io.stderr:write(string.format('operation %d %s: lua %04X:%04X native %04X:%04X\n', i, op[1], seg, off, want[2], want[1]))
  end
end
local bytes = {}
for a = 0, #base - 1 do bytes[#bytes + 1] = string.char(m:u8(a)) end
local out = assert(io.open(arg[2], 'wb')); out:write(table.concat(bytes)); out:close()
