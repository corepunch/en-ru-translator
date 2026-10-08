local provider = require 'core.openrussian_poc'
local morphology = provider.load('data/openrussian-poc/BASE.DIC', 'data/openrussian-poc/BASE.RUS')

local examples = {
  {'table', {pos='noun', number='singular', case='genitive'}},
  {'child', {pos='noun', number='plural', case='nominative'}},
  {'read', {pos='verb', tense='present', number='singular', person='first'}},
  {'go', {pos='verb', tense='present', number='singular', person='first'}},
  {'write', {pos='verb', tense='present', number='singular', person='first'}},
  {'white', {pos='adjective', number='singular', gender='masculine', case='genitive'}},
}

for _, example in ipairs(examples) do
  local values = morphology.forms(example[1], example[2])
  assert(values and #values > 0, 'missing DIC/RUS source form for ' .. example[1])
  local words = {}
  for _, value in ipairs(values) do words[#words + 1] = value.form end
  print(example[1] .. ' [' .. values[1].slot .. '] -> ' .. table.concat(words, ', '))
end
