local text = require 'core.text'
local nodes = require 'core.nodes'
local senses = require 'core.senses'
local constituents = require 'core.constituents'
local matching = require 'core.matching'
assert(text.is_upper_cyrillic(0x80) and text.is_upper_cyrillic(0xF0) and not text.is_upper_cyrillic(0xA0))
assert(text.is_lower_cyrillic(0xA0) and text.is_lower_cyrillic(0xF1) and not text.is_lower_cyrillic(0xF2))
assert(text.is_cyrillic(0xAF) and not text.is_cyrillic(0xB0))
assert(text.digit(0x37) and text.alpha(0x41) and not text.alpha(0xA0))
assert(text.ends('word','rd') and not text.ends('word','rd',1))
local a,b,c=nodes.new('N'),nodes.new('V'),nodes.new('A')
local state={count=3,elements={[0]={tag=42,next=a,last=a},[1]={tag=86,next=b,last=b},[2]={tag=65,next=c,last=c}},tags={[0]=42,[1]=86,[2]=65}}
constituents.swap(state,1,2)
assert(state.elements[1].next==c and state.tags[1]==65)
local d=nodes.new('L')
assert(constituents.insert(state,{tag=76,next=d,last=d},1)==4)
local root={}
constituents.relink(state,root)
assert(root.next==a and a.next==d and d.next==c and c.next==b and not b.next)
assert(matching.constituents(state,1,'LA')==2)
-- Cached spans and live tags must remain independent.
state.elements[2].tag=78
assert(matching.constituents(state,1,'LN')==2)
assert(state.tags[2]==65)
local r=nodes.new('Q')
assert(senses.parse_code(r,string.char(0x90,0x84)..'12word')=='word')
assert(r[0x76]==4 and r[0x72]==1 and r[0x75]==2)
r.text='first'; r.alternative={text='old'}
local clone=senses.clone(r,'second')
clone.text='changed'
assert(r.text=='first' and not clone.alternative and not clone.next)
local numbers={}
for _,value in ipairs({'1','11','2','12','22','5'}) do
  numbers[#numbers+1]={[0x0E]=0x57,[0x0C]=0x48,[0x87]=#value,[0x12]=value}
end
senses.numeric_pass({},nodes.link(numbers))
assert(nodes.byte(numbers[1],0x72)==0 and numbers[2][0x72]==1)
assert(nodes.byte(numbers[3],0x72)==0 and numbers[4][0x72]==1 and nodes.byte(numbers[5],0x72)==0 and numbers[6][0x72]==1)
print('post_stages_test: passed')
