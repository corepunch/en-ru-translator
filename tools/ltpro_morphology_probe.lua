local engine = require 'core.engine'
local memory = require 'core.memory'
local generation = require 'core.generation'
local initial = engine.new_memory('LTGOLD/LTPRO.EXE', 'LTGOLD/BASE.RUS')
for _, fixture in ipairs(dofile(assert(arg[1]))) do
  local m = memory.new(initial.base)
  m.ds = initial.ds
  local args = fixture.args
  m:write_string(0xD000, 0, args[2] .. '\0')
  local s, o = generation[fixture.routine .. '_form'](m, args[1], 0xD000, 0, table.unpack(args, 3))
  local value = not memory.null(s, o) and m:cstring(s, o)
  print(value and (value:gsub('.', function(c) return string.format('%02x', c:byte()) end)) or '-')
end
