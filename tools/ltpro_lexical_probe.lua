local dictionary=require 'core.ltpro.dictionary'
local lexical=require 'core.ltpro.lexical'
local fixtures=dofile(assert(arg[1]))
local file=assert(io.open(arg[2] or 'LTGOLD/BASE.DIC','rb'))
local loaded=dictionary.from_bytes(file:read('*a'));file:close()
local passed,failed=0,0
for _,case in ipairs(fixtures) do
  local state=lexical.analyze(loaded,case.input)
  local differences={}
  if state.tags~=case.cache then differences[#differences+1]='tag cache' end
  if state.count~=#case.nodes then differences[#differences+1]='node count' end
  for i=2,#case.nodes-1 do
    local actual=state.vector[i-1]
    local expected=case.nodes[i]
    local raw=(expected.raw_hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end))
    for _,at in ipairs({0x0B,0x0C,0x0E,0x0F,0x66,0x85,0x86}) do
      if actual[at]~=raw:byte(at+1) then differences[#differences+1]=string.format('node %d +%02X',i,at) end
    end
    for at=0x68,0x7B do
      if actual[at]~=raw:byte(at+1) then differences[#differences+1]=string.format('node %d +%02X',i,at) end
    end
    for _,at in ipairs({0x10,0x87}) do
      if actual[at]~=string.unpack('<I2',raw,at+1) then differences[#differences+1]=string.format('node %d word +%02X',i,at) end
    end
    for _,at in ipairs({0x12,0x9C,0x11C}) do
      if actual[at]~=raw:sub(at+1,assert(raw:find('\0',at+1,true))-1) then
        differences[#differences+1]=string.format('node %d text +%02X',i,at)
      end
    end
  end
  if #differences==0 then passed=passed+1
  else failed=failed+1;print('FAIL '..case.id..': '..table.concat(differences,', ')) end
end
print(string.format('Native lexical slice vs Lua: PASS=%d FAIL=%d TOTAL=%d',passed,failed,#fixtures))
os.exit(failed==0 and 0 or 1)
