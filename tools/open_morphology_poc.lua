local morphology = require 'core.open_morphology'
local data = dofile('data/morphology-poc/lexemes.lua')
local provider = morphology.new(data)

local examples = {
  {'стол', {'NOUN', 'gent', 'sing'}},
  {'книга', {'NOUN', 'ablt', 'sing'}},
  {'время', {'NOUN', 'gent', 'sing'}},
  {'читать', {'VERB', '1per', 'sing', 'pres', 'indc'}},
  {'писать', {'VERB', '1per', 'sing', 'pres', 'indc'}},
  {'идти', {'VERB', '1per', 'sing', 'pres', 'indc'}},
  {'дать', {'VERB', 'masc', 'sing', 'past', 'indc'}},
  {'быть', {'VERB', 'sing', '3per', 'pres', 'indc'}, {'Abbr'}},
  {'учиться', {'VERB', '1per', 'sing', 'pres', 'indc'}},
  {'белый', {'ADJF', 'Qual', 'gent', 'masc', 'sing'}, {'Supr'}},
}

for _, example in ipairs(examples) do
  local values = provider.forms(example[1], example[2], example[3])
  assert(values and #values > 0, 'missing source form for ' .. example[1])
  print(example[1] .. ' -> ' .. table.concat(values, ', '))
end
