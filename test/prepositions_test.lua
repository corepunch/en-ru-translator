-- Translation checks are the `preposition:` lines in test/translations.txt
-- (original LTPRO captures: test/ltpro/prepositions/). Every P/p reading in
-- dictionary/changes.txt must have one.
local covered={}
for _,case in ipairs(require('test.cases').load()) do
  if case.group=='preposition' then covered[case.entry]=true end
end
local entries=0
for line in io.lines('dictionary/changes.txt') do
  local key,code=line:match('^(.-)%*(.)')
  if line:match('^#') then key=nil end
  if code=='P' or code=='p' then
    assert(covered[key],'preposition entry has no translation test: '..key)
    entries=entries+1
  end
end
print('prepositions_test: passed ('..entries..' entries)')
