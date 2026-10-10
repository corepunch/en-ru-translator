local engine = require 'core.engine'
local lexicon = require 'core.lexicon'
local encoding = require 'core.encoding'

-- Exercise every curated entry against the installed default dictionary.
-- Expected Russian uses grammatical components and OpenRussian morphology;
-- original-executable outputs and reviewed differences are kept separately in
-- test/ltpro/curated-phrases, never substituted for these expectations.
-- Translation checks are the `phrase:` lines in test/translations.txt. This
-- test checks that every curated entry has one, and that literal keys reject
-- partial words and protected spans.
local covered={}
for _,case in ipairs(require('test.cases').load()) do
  if case.group=='phrase' then covered[case.entry]=true end
end

local file=assert(io.open('dictionary/BASE.DIC','rb'))
local dictionary=lexicon.from_bytes(file:read('*a'));file:close()
local entries=0
local in_phrases=false
for line in io.lines('dictionary/changes.txt') do
  if line:match('^## ') then in_phrases=line=='## phrases' end
  if in_phrases and line:match('%S') and not line:match('^#') then
    local key=line:match('^(.-)%*%$') or line:match('^(.-)%*')
    assert(covered[key],'curated entry has no translation test: '..key)
    entries=entries+1
    if not line:find('*$',1,true) then
      -- Reject a changed last word for EVERY literal expression. A shorter
      -- valid expression may still match (thank you vs thank you very much).
      local records=lexicon.tokenize(key..'x')
      local found=lexicon.match_phrase(dictionary,records,2,records[2].source:lower())
      assert(not found or found.key~=key,'partial-word match: '..key)
      local protected=key:gsub('(%S+)$','{~%1~}')
      records=lexicon.tokenize(protected)
      found=lexicon.match_phrase(dictionary,records,2,records[2].source:lower())
      assert(not found or found.key~=key,'protected-span match: '..key)
    end
  end
end
for _,case in ipairs({
  {'Good afternoontime.','добрый день'},
  {'Good {~afternoon~}.','добрый день'},
  {'Thank you {~very much~}.','большое спасибо'},
  {'In {~advance~}.','заранее'},
  {'As soon as {~possible~}.','как можно скорее'},
  {'Happy birthdayish.','с днём рождения'},
}) do
  local analyzed=lexicon.analyze(dictionary,encoding.encode(case[1]))
  for i=1,analyzed.count-2 do
    assert(analyzed.vector[i].reading~=encoding.encode(case[2]),
      case[1]..': matched across a protected span or inside a word')
  end
end
local extended=lexicon.analyze(dictionary,'Thank you very much for your help.')
assert(extended.vector[1].reading==encoding.encode('большой') and
  extended.vector[2].reading==encoding.encode('спасибо'),'prefer the longest expression and retain its components')
local remaining=false
for i=2,extended.count-2 do
  if extended.vector[i].source=='help' then remaining=true end
end
assert(remaining,'preserve following context')
print('common_phrases_test: passed ('..entries..' entries)')
