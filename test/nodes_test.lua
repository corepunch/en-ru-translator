local nodes=require 'core.nodes'
local shared=nodes.new('V',{reading='shared'})
local a=nodes.new('N',{paradigm=255,paradigm_high=255,source_length=300,reading='word',aux=shared})
local b=nodes.new('A',{reading='tail',aux=shared})
local root=nodes.link({a,b})
nodes.prepare(root)
assert(a.aux==b.aux and a.paradigm==65535 and a.source_length==300)
assert(a.text=='word' and b.text=='tail' and shared.text=='shared')
shared.text='updated'
assert(a.aux.text=='updated' and b.aux.text=='updated')
a.tag=32; a.marker=0x58
local vector,count=nodes.vector(root)
assert(count==1 and vector[0]==b and a.tag==0x78)
local state={word_count=511}
assert(nodes.word(state,0x4E,'noun').text=='noun')
assert(not nodes.word(state,0x4E,'over limit'))
-- Native fixture offsets are translated once, with opaque captured data retained.
local layout = require 'tools.ltpro_record_layout'
local imported = layout.import({[0x0C] = string.byte('N'), [0x73] = 1, [0x12] = 'source', [0x6B] = 17})
assert(imported.tag == string.byte('N') and imported.tense == 1 and imported.source == 'source')
assert(imported[0x0C] == nil and imported[0x73] == nil and imported[0x6B] == 17)
assert(nodes.character(imported, 'tag') == 'N' and nodes.number(nil, 'tense') == 0)
print('nodes_test: passed')
