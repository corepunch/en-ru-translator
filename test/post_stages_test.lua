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
assert(r.case_mask==4 and r.number==1 and r.aspect==2)
r.text='first'; r.alternative={text='old'}
local clone=senses.clone(r,'second')
clone.text='changed'
assert(r.text=='first' and not clone.alternative and not clone.next)
local numbers={}
for _,value in ipairs({'1','11','2','12','22','5'}) do
  numbers[#numbers+1]={kind=0x57,tag=0x48,source_length=#value,source=value}
end
senses.numeric_pass({},nodes.link(numbers))
assert(nodes.number(numbers[1],'number')==0 and numbers[2].number==1)
assert(nodes.number(numbers[3],'number')==0 and numbers[4].number==1 and nodes.number(numbers[5],'number')==0 and numbers[6].number==1)
-- Tag spelling controls constituent boundaries: E becomes a main verb after a
-- noun, while the lowercase r/v tags retain their distinct native categories.
local function build(tags)
  local records = {}
  for i = 1, #tags do
    local tag = tags:sub(i, i)
    records[i] = nodes.new(tag, {separator = tag == '*' and string.byte('*') or 0,
      passive = tag == 'E' and 1 or 0})
  end
  local state = {}
  state.count = constituents.build(state, nodes.link(records))
  return state, records
end
local built, words = build('*NE*')
assert(built.count == 4 and nodes.tag(words[3]) == 'V' and words[3].passive == 0)
assert(built.elements[2].class == string.byte('Y'))
built, words = build('*rv*')
assert(built.count == 4 and nodes.tag(words[2]) == 'r' and nodes.tag(words[3]) == 'v')
assert(built.elements[1].class == string.byte('W') and built.elements[2].class == string.byte('Y'))

print('post_stages_test: passed')
