local generation = require 'core.generation'
local output = require 'core.output'
local nodes = require 'core.nodes'
local state={assets={},russian={openrussian_forms={},source_forms={}}}
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
local boundary={[9]=2,kind=0x44,separator=0x2A}
local word={kind=0x57,reading_state=2,tag=0x4E,source='CAT',text='\xAA\xAE\xE2e'}
local punct={kind=0x44,separator=0x2E,source='.'}
local result,count=output.sentence(state,nodes.link({boundary,word,punct}))
assert(count==0 and result==' \x8A\x8E\x92e.')
assert(word.text=='\x8A\x8E\x92e')
print('generation_test: passed')
