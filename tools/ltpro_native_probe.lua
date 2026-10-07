local layout = require 'core.record_layout'
-- Feed native fixtures to the Lua port; stdout is machine-readable for the 8086 harness.
local nodes = require 'core.nodes'
local reorder = require 'core.reorder'
for _, fixture in ipairs(assert(loadfile(arg[1]))()) do
  local records = {}
  for i, fields in ipairs(fixture) do
    local record = {id = i, [0x11C] = fields.text}
    for key, value in pairs(fields) do if type(key) == 'number' then record[layout.key(key)] = value end end
    records[i] = record
  end
  local root = nodes.link(records)
  reorder.apply(root)
  local ids, tags, node, seen = {}, {}, root.next, {}
  while node do
    assert(not seen[node], 'cycle')
    seen[node] = true
    ids[#ids + 1], node = node.id, node.next
  end
  for _, record in ipairs(records) do tags[#tags + 1] = record.tag end
  print('[[' .. table.concat(ids, ',') .. '],[' .. table.concat(tags, ',') .. ']]')
end
