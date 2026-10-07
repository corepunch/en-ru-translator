-- Observe all changed native fields, not only the resulting current-tag sequence.
local matching = require 'core.matching'
local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
for _, fixture in ipairs(dofile(assert(arg[1]))) do
  local vector = {}
  for i, node in ipairs(fixture.nodes) do vector[i - 1] = node end
  local tags = {}
  for _, node in ipairs(fixture.nodes) do tags[#tags + 1] = string.char(node[12]) end
  local state = {tags = fixture.cache or table.concat(tags)}
  local result = matching.replace(vector, fixture.start, fixture.last, fixture.pattern, fixture.action, state)
  local fields = {}
  for _, node in ipairs(fixture.nodes) do
    fields[#fields + 1] = string.format('[%d,%d,"%s"]', node[12], node[102] or 0, hex(node[284] or ''))
  end
  print('[' .. result .. ',[' .. table.concat(fields, ',') .. '],"' .. hex(state.tags) .. '"]')
end
