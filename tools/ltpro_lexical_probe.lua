local layout = require 'tools.ltpro_record_layout'
local lexicon = require 'core.lexicon'
local fixtures=dofile(assert(arg[1]))
local file=assert(io.open(arg[2] or 'LTGOLD/BASE.DIC','rb'))
local loaded=lexicon.from_bytes(file:read('*a'));file:close()
local passed,failed=0,0
for _,case in ipairs(fixtures) do
  local differences={}
  local ok,state=pcall(lexicon.analyze,loaded,case.input)
  if not ok then differences[1]=tostring(state)
  else
    if state.tags~=case.cache then differences[#differences+1]='tag cache '..state.tags..' / '..case.cache end
    if state.count~=#case.nodes then differences[#differences+1]='node count' end
    for i,expected in ipairs(case.nodes) do
      local actual=state.vector[i-1]
      if not actual then break end
      local raw=(expected.raw_hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end))
      local function field(at)
        if (actual[layout.key(at)] or 0)~=raw:byte(at+1) then differences[#differences+1]=string.format('node %d +%02X %d/%d',i,at,actual[layout.key(at)] or 0,raw:byte(at+1)) end
      end
      for _,at in ipairs({0x0C,0x0D,0x0E,0x0F}) do field(at) end
      if raw:byte(0x0F)==0x57 then
        for _,at in ipairs({0x0B,0x66,0x85,0x86}) do field(at) end
        for at=0x68,0x7B do field(at) end
        local actual_rules,expected_rules=actual.rules or {},expected.rules or {}
        if #actual_rules~=#expected_rules then differences[#differences+1]='node '..i..' sub-rule count' end
        for j,rule in ipairs(expected_rules) do
          local got=actual_rules[j]
          if not got or got.pattern~=rule.pattern or got.action~=rule.action then
            differences[#differences+1]='node '..i..' sub-rule '..j
          end
        end
        for _,at in ipairs({0x10,0x87}) do
          if (actual[layout.key(at)] or 0)~=string.unpack('<I2',raw,at+1) then differences[#differences+1]=string.format('node %d word +%02X',i,at) end
        end
        for _,at in ipairs({0x9C,0x11C}) do
          if (actual[layout.key(at)] or '')~=raw:sub(at+1,assert(raw:find('\0',at+1,true))-1) then
            differences[#differences+1]=string.format('node %d text +%02X',i,at)
          end
        end
      elseif i==1 then field(0x09) end
      if actual.source~=raw:sub(0x13,assert(raw:find('\0',0x13,true))-1) then
        differences[#differences+1]=string.format('node %d source',i)
      end
    end
  end
  if #differences==0 then passed=passed+1
  else failed=failed+1;print('FAIL '..case.id..': '..table.concat(differences,', ')) end
end
print(string.format('Native lexical slice vs Lua: PASS=%d FAIL=%d TOTAL=%d',passed,failed,#fixtures))
os.exit(failed==0 and 0 or 1)
