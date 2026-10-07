-- Expected byte strings were checked against the original 8086 functions.
local engine = require 'core.engine'
local generation = require 'core.generation'
local state = engine.new_state('LTGOLD/LTPRO.EXE', 'LTGOLD/BASE.RUS')
local function form(kind, id, word, ...)
  return generation[kind .. '_form'](state, id, word, ...)
end
local encode = require('core.encoding').encode
local function check(actual, expected)
  assert(actual == (expected and encode(expected)), 'native morphology mismatch')
end
check(form('noun', 0, encode('дом'), 1, 0, 1), 'дома')
check(form('noun', 0, encode('дом'), 1, 1, 0), 'дома')
check(form('adjective', 0, encode('новый'), 1, 0, 1), 'нового')
check(form('adjective', 14, encode('весь'), 2, 0, 0), 'вся')
check(form('verb', 98, encode('идти'), 0, 0, 3, 0, 1, 1), 'шел')
check(form('verb', 98, encode('идти'), 0, 0, 3, 0, 1, 2), 'шла')
check(form('verb', 98, encode('идти'), 0, 18, 3, 1, 1, 0), 'шли бы ли')
check(form('verb', 60, encode('сидеть'), 0, 0, 3, 0, 1, 2), 'сидeла')
check(form('verb', 0, encode('читать'), 0, 4, 3, 0, 1, 1), 'читайте')
check(form('verb', 0, encode('читаться'), 0, 0, 1, 0, 0, 1), 'читаюсь')
check(form('verb', 0, encode('читаться'), 0, 0, 0, 0, 0, 1), 'читаться')
check(form('verb', 9, encode('слать'), 0, 0, 3, 0, 0, 1), nil)
check(form('participle', 0, encode('читать'), 0, 0x47, 0, 0), 'читая')
check(form('participle', 0, encode('читаться'), 0, 0x47, 0, 0), 'читаясь')
print('LTPRO native inflection tests passed')
