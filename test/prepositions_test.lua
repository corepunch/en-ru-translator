-- Translation checks are the `preposition:` lines in test/translations.txt
-- (original LTPRO captures: test/ltpro/prepositions/). Every P/p reading in
-- dictionary.txt must have one.
local covered={}
for _,case in ipairs(require('test.cases').load()) do
  if case.group=='preposition' then covered[case.entry]=true end
end
local entries=0
for line in io.lines('openrussian/dictionary.txt') do
  local key,code=line:match('^(.-)%*(.)')
  if line:match('^#') then key=nil end
  if code=='P' or code=='p' then
    assert(covered[key],'preposition entry has no translation test: '..key)
    entries=entries+1
  end
end
assert(entries>0,'no prepositions in dictionary.txt')
print('prepositions_test: passed ('..entries..' entries)')
