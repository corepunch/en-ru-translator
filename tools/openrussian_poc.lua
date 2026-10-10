package.path = './?.lua;./?/init.lua;' .. package.path

local engine = require 'core.engine'
local options = {
  dictionary = 'openrussian/BASE.DIC',
  russian = 'openrussian/BASE.RUS',
  russian_morphology = 'openrussian/BASE.MORPH',
}
local examples = {
  'The child reads a book.',
  'I read a book.',
  'The child wants a book.',
  'The child wants books.',
  'A child reads a book.',
  'The person reads a book.',
  'A person reads books.',
  'The person wants a book.',
  'People want a book.',
  'I want a book.',
  'I want books.',
  'I want time.',
  'People want time.',
  'The child wants time.',
  'People give a book.',
  'The child gives a book.',
  'I give a book.',
  'I can read a book.',
  'The child eats.',
  'The child reads the book.',
}

for _, input in ipairs(examples) do
  local translated = engine.translate(input, options)
  print(input .. ' -> ' .. translated)
end
