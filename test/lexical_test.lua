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
assert(v[2][0x12]=='Letter' and v[2][0x0F]==0x77 and encoding.decode(v[2][0x11C])=='аккредитив')
v=analyze('There is no book.','*yZ*')
assert(v[1][0x75]==1 and v[1][0x76]==2)
v=analyze('He cannot go.','*RUKV*')
assert(v[2][0x12]=='can' and v[2][0x10]==3 and v[3][0x12]=='not' and v[3][0x10]==0)
v=analyze('He works.','*RV*')
assert(v[2][0x9C]=='work ')
v=analyze('If he comes then I go.','*JRVDRV*')
assert(v[3][0x9C]=='')
v=analyze('Two books.','*IZ*')
assert(v[2][0x9C]=='book' and v[2][0x72]==1 and v[2][0x74]==3)
v=analyze('"Fish meal", seller said.','*"AN",NE*')
assert(v[2][0x0B]==2 and v[3][0x0B]==2 and v[2][0x0F]==0x77)
v=analyze('making them.','*GM*')
local inherited=false
for _,rule in ipairs(v[1].rules or {}) do
  if rule.pattern=='[MR]' and encoding.decode(rule.action)=='заставлять' then inherited=true end
end
assert(inherited,'backreference subrules must reach T4')
local unknown=lexicon.analyze(dict,'ABC-123.')
assert(unknown.word_count==0 and unknown.tags=='*#*' and unknown.vector[1][0x12]=='ABC-123')
-- Native E001+case stores the object's case at +79, preserving +76=8.
local n={[0x0C]=string.byte('E'),[0x0B]=1,[0x66]=string.byte('E')}
lexicon.decode_reading(n,encoding.encode('001Рслово'))
assert(n[0x76]==8 and n[0x79]==2 and encoding.decode(n[0x11C])=='слово')
print('lexical_test: passed')
