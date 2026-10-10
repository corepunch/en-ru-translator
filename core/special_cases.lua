-- Lexical exceptions confirmed against the original LTPRO executable.
local special_cases = {}

function special_cases.english_noun(source)
  if source:lower() == 'people' then return 'n' .. string.char(0xab, 0xee, 0xa4, 0xa8) end -- люди
end

return special_cases
