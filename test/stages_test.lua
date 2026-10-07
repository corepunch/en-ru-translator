local nodes = require 'core.nodes'
local lexicon = require 'core.lexicon'
local grammar = require 'core.grammar'
local encoding=require 'core.encoding'
local function cp(s) return encoding.encode(s) end

local bytes='LTech header\0\r\nword*Nслово{значение}.\r\nword*Vдругое\r\nphrase*WWNтекст\n'
local loaded=lexicon.from_bytes(bytes)
assert(loaded.bytes==bytes)
assert(#loaded.records==3 and #loaded.by_key.word==2)
assert(loaded.records[1].value=='Nслово{значение}.')
assert(loaded.records[3].value=='WWNтекст')

local forms=lexicon.from_bytes(cp('if*JеслиPПпри\nhe*R031онrу негоmему\ncomes*vприходить\\come\nthen*DзатемCзатемJзатемjтогда\ni*R011яrу меняmмне\ngo*Vидти\n'))
local state=lexicon.analyze(forms,'If he comes then I go.')
assert(state.tags=='*JRVDRV*')
assert(state.vector[3][0x74]==3 and state.vector[3][0x76]==8)
assert(state.vector[5][0x74]==1)
local result=grammar.first(state.root,{terminator=0x2E})
assert(result.tags=='*JRVjRV*')
assert(#result.events==1 and result.events[1].rule==27 and result.events[1].handler==0)
assert(result.vector[4][0x66]==string.byte('D'))
assert(result.vector[4][0x11C]==cp('затемCзатемJзатемjтогда'))
local unknown=lexicon.analyze(forms,'An unknown word.')
assert(unknown.tags=='*???*' and unknown.vector[2][0x12]=='unknown')
assert(unknown.vector[2][0x74]==3 and unknown.vector[2][0x77]==1)

-- T2 over native nodes: `has` is removed and the participle becomes the verb,
-- as in the captured case-048 boundary.
local perfect=lexicon.from_bytes(cp('he*R031онrу негоmему\nhas*Y003иметьyесть\\have\nworked*Eработать\\work\n'))
local analyzed=lexicon.analyze(perfect,'He has worked.')
assert(analyzed.tags=='*RYE*')
local after_t1=grammar.first(analyzed.root,{terminator=0x2E})
assert(after_t1.tags=='*RYE*' and #after_t1.events==0)
local after_t2=grammar.second(analyzed.root,{count=after_t1.count})
assert(after_t2.tags=='*RV*' and after_t2.count==4)
assert(after_t2.vector[2][0x12]=='worked' and after_t2.vector[2][0x75]==1 and after_t2.vector[2][0x73]==1)
assert(#after_t2.events==2 and after_t2.events[1].handler==60 and after_t2.events[2].handler==24)

-- Per-word sub-rules: dictionary order, star inside a pattern class, ten at most.
local phrasing = require 'core.phrasing'
local lines={'he*R031онrу негоmему','is*X003бытьUдолженfимеется ли\\be','is <dDkK>`present`*$ \\$`Vприсутствовать`',
  'in*PВПвb','in <THI>`hours`*$PВчерез','in `full`[*]*$Dполностью\\ \\','the*T','house*Nдом','in spite of*Pнесмотря на'}
for i=1,11 do lines[#lines+1]='in `extra'..i..'`*$D'..i end
local sub=lexicon.from_bytes(cp(table.concat(lines,'\n')..'\n'))
local attached=lexicon.sub_rules(sub,'In')
assert(#attached==10 and attached[1].pattern=='<THI>`hours`' and attached[1].action==cp('PВчерез'))
assert(attached[2].pattern=='`full`[*]' and attached[2].action==cp('Dполностью\\ \\'))
assert(attached[10].pattern=='`extra8`')
local house=lexicon.analyze(sub,'He is in the house.')
assert(house.tags=='*RXPTN*' and #house.vector[2].rules==1 and #house.vector[3].rules==10 and house.vector[4].rules==nil)
grammar.first(house.root,{terminator=0x2E});grammar.second(house.root,{});grammar.third(house.root,{})
local after_t4=phrasing.run(house.root,{})
assert(after_t4.tags=='*RXPTN*' and #after_t4.events==3 and after_t4.events[3].handler==18)
for _,event in ipairs(after_t4.events) do assert(not event.sub_rule) end

local n=nodes.new('P',{[0x0B]=1,[0x0F]=0})
assert(lexicon.decode_reading(n,cp('ВПвb'))==1)
assert(n[0x76]==8 and n[0x11C]==cp('Пвb'))
local v=nodes.new('V',{[0x68]=0x80,[0x6A]=0x80,[0x0F]=0})
assert(lexicon.decode_reading(v,cp('123делать'))==3)
assert(v[0x68]==0xC1 and v[0x6A]==0x83 and v[0x76]==8)
assert(not pcall(lexicon.decode_reading,n,'=macro'))

local function raw(next_offset,next_segment)
  local data=string.rep('\0',0x282)
  data=string.pack('<I2I2',next_offset,next_segment)..data:sub(5)
  return data:sub(1,12)..'N'..data:sub(14)
end
local record=raw(0,0)
local root,vector,count=nodes.from_records({
  {offset=16,segment=0x8000,bytes=record},
  {offset=0,segment=0x8001,bytes=record},
})
assert(count==2 and root.next==vector[0] and vector[0]==vector[1])
assert(not pcall(nodes.from_records,{{offset=0,segment=0x8000,bytes=raw(16,0x9000)}}))
local pool={limit=1}
local boundary=assert(nodes.boundary('j','|',pool))
assert(boundary[0x0C]==0x6A and boundary[0x0D]==0x7C and boundary[0x0E]==0x44)
assert(boundary[0x12]=='j' and pool.count==1)
assert(nodes.boundary('j','|',pool)==nil)
local exhausted={allocate=function() return nil end}
assert(nodes.boundary('j','|',exhausted)==nil and exhausted.count==nil)
print('stages_test: passed')
