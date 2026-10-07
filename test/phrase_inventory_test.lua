local lexicon = require 'core.lexicon'
local encoding = require 'core.encoding'
local file=assert(io.open('LTGOLD/BASE.DIC','rb'))
local dictionary=lexicon.from_bytes(file:read('*a'));file:close()
local count=0
for _,record in ipairs(dictionary.records) do
  if record.value:sub(1,1)=='W' and record.key:find(' ',1,true) then
    local input=record.key:gsub('~','cat')
    local ok, result=pcall(lexicon.analyze,dictionary,input)
    assert(ok, encoding.decode(record.key)..': '..tostring(result))
    assert(result.count<=512)
    count=count+1
  end
end
assert(count>8000, 'expected the supplied dictionary phrase inventory')
print('phrase_inventory_test: passed ('..count..' phrase inputs)')
