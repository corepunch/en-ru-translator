local lexicon = require 'core.lexicon'
local encoding=require 'core.encoding'
local f=assert(io.open('LTGOLD/BASE.DIC','rb'))
local dict=lexicon.from_bytes(f:read('a'));f:close()
local function analyze(text,tags)
  local state=lexicon.analyze(dict,text)
  assert(state.tags==tags,state.tags..' / '..tags)
  return state.vector
end
local v=analyze('The Letter of Credit shall allow for partial shipments and partial payment.','*TNXVANCAN*')
assert(v[2].source=='Letter' and v[2].marker==0x77 and encoding.decode(v[2].reading)=='аккредитив')
v=analyze("I'm testing this.",'*RXGS*')
assert(v[1].source=='I' and v[1].source_length==1 and v[1].source_position==0)
assert(v[2].source=='am' and v[2].source_position==0)
local intact=lexicon.analyze(dict,"O'Neil John's book.")
assert(intact.vector[1].source=="O'Neil" and intact.vector[2].source=="John's")
v=analyze('There is no book.','*yZ*')
assert(v[1].aspect==1 and v[1].case_mask==2)
v=analyze('He cannot go.','*RUKV*')
assert(v[2].source=='can' and v[2].source_position==3 and v[3].source=='not' and v[3].source_position==0)
v=analyze('He works.','*RV*')
assert(v[2].lookup=='work ')
v=analyze('If he comes then I go.','*JRVDRV*')
assert(v[3].lookup=='')
v=analyze('Two books.','*IZ*')
assert(v[2].lookup=='book' and v[2].number==1 and v[2].person==3)
v=analyze('"Fish meal", seller said.','*"AN",NE*')
assert(v[2].reading_state==2 and v[3].reading_state==2 and v[2].marker==0x77)
v=analyze('making them.','*GM*')
local inherited=false
for _,rule in ipairs(v[1].rules or {}) do
  if rule.pattern=='[MR]' and encoding.decode(rule.action)=='заставлять' then inherited=true end
end
assert(inherited,'backreference subrules must reach T4')
local unknown=lexicon.analyze(dict,'ABC-123.')
assert(unknown.word_count==0 and unknown.tags=='*#*' and unknown.vector[1].source=='ABC-123')
-- Native E001+case stores the object's case at +79, preserving +76=8.
local n={tag=string.byte('E'),reading_state=1,previous_tag=string.byte('E')}
lexicon.decode_reading(n,encoding.encode('001Рслово'))
assert(n.case_mask==8 and n.governed_case==2 and encoding.decode(n.reading)=='слово')
print('lexical_test: passed')
