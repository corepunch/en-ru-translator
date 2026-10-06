-- T7's caller class chooses its table before matching; the adjective table is conditional.
local rules = require "core.rules"
local dispatch = require "core.ltpro.dispatch"
local guards = {}
local tables_by_address = { [0x17ECE] = rules[8], [0x17ED8] = rules.adjective }

function guards.table_for(tag)
  local code = type(tag) == "string" and tag:byte() or tag
  return tables_by_address[dispatch.T7_select[code]]
end

function guards.endpoints(rule, first, last)
  if rule.endpoint_order ~= 0 then return last, first end
  return first, last
end

return guards
