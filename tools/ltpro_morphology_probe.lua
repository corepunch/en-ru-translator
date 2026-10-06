local inflect = require 'core.ltpro.inflect'
for _, fixture in ipairs(dofile(assert(arg[1]))) do
  local value = inflect[fixture.routine](table.unpack(fixture.args))
  print(value and (value:gsub('.', function(c) return string.format('%02x', c:byte()) end)) or '-')
end
