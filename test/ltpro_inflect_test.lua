-- Expected byte strings were checked against the original 8086 functions.
local inflect = require 'core.ltpro.inflect'
local encode = require('core.utils').encode
local function check(actual, expected)
  assert(actual == (expected and encode(expected)), 'native morphology mismatch')
end
check(inflect.noun(0, encode('дом'), 1, 0, 1), 'дома')
check(inflect.noun(0, encode('дом'), 1, 1, 0), 'дома')
check(inflect.adjective(0, encode('новый'), 1, 0, 1), 'нового')
check(inflect.adjective(14, encode('весь'), 2, 0, 0), 'вся')
check(inflect.verb(98, encode('идти'), 0, 0, 3, 0, 1, 1), 'шел')
check(inflect.verb(98, encode('идти'), 0, 0, 3, 0, 1, 2), 'шла')
check(inflect.verb(98, encode('идти'), 0, 18, 3, 1, 1, 0), 'шли бы ли')
check(inflect.verb(60, encode('сидеть'), 0, 0, 3, 0, 1, 2), 'сидeла')
check(inflect.verb(0, encode('читать'), 0, 4, 3, 0, 1, 1), 'читайте')
check(inflect.verb(0, encode('читаться'), 0, 0, 1, 0, 0, 1), 'читаюсь')
check(inflect.verb(0, encode('читаться'), 0, 0, 0, 0, 0, 1), 'читаться')
check(inflect.verb(9, encode('слать'), 0, 0, 3, 0, 0, 1), nil)
check(inflect.participle(0, encode('читать'), 0, 0x47, 0, 0), 'читая')
check(inflect.participle(0, encode('читаться'), 0, 0x47, 0, 0), 'читаясь')
print('LTPRO native inflection tests passed')
