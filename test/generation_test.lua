local generation = require 'core.generation'
local output = require 'core.output'
local nodes = require 'core.nodes'
local state={assets={}}
function state.assets:paradigm() return 2,'x - =' end
function state.assets:string(at) return at==0x5F7 and ' ' or '' end
assert(generation.case(0)==0 and generation.case(1)==0)
assert(generation.case(0x26)==1 and generation.case(0x20)==5)
assert(generation.noun_form(state,0,'abcd',1,0,1)=='abx')
assert(generation.noun_form(state,0,'abcd',1,0,2)==nil)
assert(generation.noun_form(state,0,'abcd',1,0,3)=='ab')
assert(generation.verb_form(state,0xFFFF,'abcd',0,0x12,0,0,0,1)=='abcd')
assert(output.reading('Wabc#literal#ignored')=='   literal')
assert(output.reading('W{literal}ignored')=='literal')
assert(output.reading('plain')=='plain')
assert(not pcall(output.reading,'W{unterminated'))
local boundary={[9]=2,[0x0E]=0x44,[0x0D]=0x2A}
local word={[0x0E]=0x57,[0x0B]=2,[0x0C]=0x4E,[0x12]='CAT',text='\xAA\xAE\xE2e'}
local punct={[0x0E]=0x44,[0x0D]=0x2E,[0x12]='.'}
local result,count=output.sentence(state,nodes.link({boundary,word,punct}))
assert(count==0 and result==' \x8A\x8E\x92e.')
assert(word.text=='\x8A\x8E\x92e')
print('generation_test: passed')
