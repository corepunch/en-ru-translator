local nodes=require 'core.nodes'
local shared=nodes.new('V',{[0x11C]='shared'})
local a=nodes.new('N',{[0x85]=255,[0x86]=255,[0x87]=300,[0x11C]='word',aux=shared})
local b=nodes.new('A',{[0x11C]='tail',aux=shared})
local root=nodes.link({a,b})
nodes.prepare(root)
assert(a.aux==b.aux and a[0x85]==65535 and a[0x87]==300)
assert(a.text=='word' and b.text=='tail' and shared.text=='shared')
shared.text='updated'
assert(a.aux.text=='updated' and b.aux.text=='updated')
a[0x0C]=32; a[0x0F]=0x58
local vector,count=nodes.vector(root)
assert(count==1 and vector[0]==b and a[0x0C]==0x78)
local state={word_count=511}
assert(nodes.word(state,0x4E,'noun').text=='noun')
assert(not nodes.word(state,0x4E,'over limit'))
print('nodes_test: passed')
