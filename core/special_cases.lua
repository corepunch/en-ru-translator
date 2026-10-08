-- Lexical exceptions confirmed against the original LTPRO executable.
local special_cases = {}

local people = string.char(0xab, 0xee, 0xa4, 0xa8) -- люди, CP866
local people_forms = {
  [0] = people,
  [1] = string.char(0xab, 0xee, 0xa4, 0xa5, 0xa9), -- людей
  [2] = string.char(0xab, 0xee, 0xa4, 0xef, 0xac), -- людям
  [3] = string.char(0xab, 0xee, 0xa4, 0xa5, 0xa9), -- людей
  [4] = string.char(0xab, 0xee, 0xa4, 0xec, 0xac, 0xa8), -- людьми
  [5] = string.char(0xab, 0xee, 0xa4, 0xef, 0xe5), -- людях
}

function special_cases.english_noun(source)
  if source:lower() == 'people' then return 'n' .. people end
end

function special_cases.noun_form(word, plural, case)
  if word == people and plural ~= 0 then return people_forms[case] end
end

return special_cases
