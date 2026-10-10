local engine = require 'core.engine'
local generation = require 'core.generation'
local state = engine.new_state('LTGOLD/BASE.RUS')
for _, fixture in ipairs(dofile(assert(arg[1]))) do
  local value = generation[fixture.routine .. '_form'](state, table.unpack(fixture.args))
  print(value and (value:gsub('.', function(c) return string.format('%02x', c:byte()) end)) or '-')
end
