-- OpenRussian others.tsv rows have no part of speech. The builder codes them
-- as WD readings; the former W#...# form let the # decoder take a leading
-- с/м/ж as gender and drop it (согласно -> огласно). Translation checks are
-- the `others` lines in test/translations.txt.
local file=assert(io.open('openrussian/BASE.DIC','rb'))
local data=file:read('*a');file:close()
assert(not data:find('*W#',1,true),'generated readings must not use the # class for Russian text')
print('openrussian_others_test: passed')
