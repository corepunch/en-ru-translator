-- Compare the raw native-node matcher; inputs are CP866 strings and zero-based vectors.
local matching = require 'core.matching'
for _, fixture in ipairs(dofile(assert(arg[1]))) do
  local vector = {}
  for i, node in ipairs(fixture.nodes) do vector[i - 1] = node end
  print(matching.match(vector, fixture.start, fixture.pattern, fixture.cache))
end
