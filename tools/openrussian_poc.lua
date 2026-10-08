package.path = './?.lua;./?/init.lua;' .. package.path

local engine = require 'core.engine'
local options = {
  dictionary = 'data/openrussian-poc/BASE.DIC',
  russian = 'data/openrussian-poc/BASE.RUS',
}
local examples = {
  'The child reads a book.',
  'I read a book.',
  'The table is white.',
}

for _, input in ipairs(examples) do
  local translated = engine.translate(input, options)
  print(input .. ' -> ' .. translated)
end
