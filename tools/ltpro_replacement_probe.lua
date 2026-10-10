local layout = require 'tools.ltpro_record_layout'
-- Observe all changed native fields, not only the resulting current-tag sequence.
local matching = require 'core.matching'
local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
for _, fixture in ipairs(dofile(assert(arg[1]))) do
  for i, node in ipairs(fixture.nodes) do fixture.nodes[i] = layout.import(node) end
  local vector = {}
  for i, node in ipairs(fixture.nodes) do vector[i - 1] = node end
  local tags = {}
  for _, node in ipairs(fixture.nodes) do tags[#tags + 1] = string.char(node.tag) end
  local state = {tags = fixture.cache or table.concat(tags)}
  local result = matching.replace(vector, fixture.start, fixture.last, fixture.pattern, fixture.action, state)
  local fields = {}
  for _, node in ipairs(fixture.nodes) do
    fields[#fields + 1] = string.format('[%d,%d,"%s"]', node.tag, node.previous_tag or 0, hex(node.reading or ''))
  end
  print('[' .. result .. ',[' .. table.concat(fields, ',') .. '],"' .. hex(state.tags) .. '"]')
end
