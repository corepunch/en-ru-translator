local nodes=require 'core.ltpro.nodes'
local dictionary=require 'core.ltpro.dictionary'
local lexical=require 'core.ltpro.lexical'
local first_pass=require 'core.ltpro.first_pass'
local readings=require 'core.ltpro.readings'
local encoding=require 'core.encoding'
local function cp(s) return encoding.encode(s) end

local bytes='LTech header\0\r\nword*Nслово{значение}.\r\nword*Vдругое\r\nphrase*WWNтекст\n'
local loaded=dictionary.from_bytes(bytes)
assert(loaded.bytes==bytes)
assert(#loaded.records==3 and #loaded.by_key.word==2)
assert(loaded.records[1].value=='Nслово{значение}.')
assert(loaded.records[3].value=='WWNтекст')

local forms=dictionary.from_bytes(cp('if*JеслиPПпри\nhe*R031онrу негоmему\ncomes*vприходить\\come\nthen*DзатемCзатемJзатемjтогда\ni*R011яrу меняmмне\ngo*Vидти\n'))
local state=lexical.analyze(forms,'If he comes then I go.')
assert(state.tags=='*JRVDRV*')
assert(state.vector[3][0x74]==3 and state.vector[3][0x76]==8)
assert(state.vector[5][0x74]==1)
local result=first_pass.run(state.root,{terminator=0x2E})
assert(result.tags=='*JRVjRV*')
assert(#result.events==1 and result.events[1].rule==27 and result.events[1].handler==0)
assert(result.vector[4][0x66]==string.byte('D'))
assert(result.vector[4][0x11C]==cp('затемCзатемJзатемjтогда'))
assert(not pcall(lexical.analyze,forms,'An unknown word.'))

local n=nodes.new('P',{[0x0B]=1,[0x0F]=0})
assert(readings.decode(n,cp('ВПвb'))==1)
assert(n[0x76]==8 and n[0x11C]==cp('Пвb'))
local v=nodes.new('V',{[0x68]=0x80,[0x6A]=0x80,[0x0F]=0})
assert(readings.decode(v,cp('123делать'))==3)
assert(v[0x68]==0xC1 and v[0x6A]==0x83 and v[0x76]==8)
assert(not pcall(readings.decode,n,'=macro'))

-- Production regression: the lexical clause-end reading must retain its text,
-- while a structural marker with no reading remains silent.
local compiler=require 'core.compiler'
assert(compiler.compile({'j'..cp('тогда')},{quiet=true})=='Тогда')
assert(compiler.compile({'j'},{quiet=true})=='')

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
print('ltpro_stages_test: passed')
