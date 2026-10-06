local nodes = require 'core.ltpro.nodes'
local first_pass = require 'core.ltpro.first_pass'
local function unhex(s) return (s:gsub('%x%x',function(x) return string.char(tonumber(x,16)) end)) end
local fixtures = dofile(assert(arg[1]))
local passed, failed = 0, 0
local function compare(vector,expected,differences,prefix)
  for i,record in ipairs(expected) do
    local actual=vector[i-1]
    if not actual then differences[#differences+1]=prefix..' missing node '..i;break end
    local address=record.pointer[2]*16+record.pointer[1]
    if actual.native_address~=address then differences[#differences+1]=prefix..' node identity '..i end
    local next_address=record.next_pointer[2]*16+record.next_pointer[1]
    if (actual.next and actual.next.native_address or 0)~=next_address then
      differences[#differences+1]=prefix..' next link '..i
    end
    local raw=unhex(record.raw_hex)
    for _,at in ipairs({0x0B,0x0C,0x0D,0x0E,0x0F,0x66,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B}) do
      if (actual[at] or 0)~=raw:byte(at+1) then differences[#differences+1]=string.format('%s node %d +%02X',prefix,i,at) end
    end
    for _,at in ipairs({0x12,0x9C,0x11C}) do
      local stop=assert(raw:find('\0',at+1,true))
      if actual[at]~=raw:sub(at+1,stop-1) then differences[#differences+1]=string.format('%s node %d string +%02X',prefix,i,at) end
    end
  end
end
for _,case in ipairs(fixtures) do
  local records = {}
  for _,record in ipairs(case.before) do
    records[#records+1] = {offset=record.pointer[1],segment=record.pointer[2],bytes=unhex(record.raw_hex)}
  end
  local root = nodes.from_records(records)
  local differences = {}
  local matched=0
  local allocated=0
  local boundaries={limit=case.boundary_limit,allocate=function()
    if case.allocation_failure then return nil end
    allocated=allocated+1
    return {native_address=assert(case.allocations[allocated])}
  end}
  local ok, result = pcall(first_pass.run,root,{terminator=case.terminator,rules=case.rules,boundaries=boundaries,on_match=function(event,vector,count,cache)
    matched=matched+1
    local expected=case.events and case.events[matched]
    if not expected then differences[#differences+1]='unexpected match event';return end
    for _,field in ipairs({'rule','handler','last'}) do
      if event[field]~=expected[field] then differences[#differences+1]='event '..matched..' '..field end
    end
    if cache~=expected.cache or count~=#expected.nodes then differences[#differences+1]='event '..matched..' vector/cache' end
    compare(vector,expected.nodes,differences,'event '..matched)
  end})
  if case.events and matched~=#case.events then differences[#differences+1]='event count' end
  if not ok then differences[#differences+1] = tostring(result)
  else
    if case.early_exit==1 then
      if result.result~=0 then differences[#differences+1]='missing native early return' end
    else
      if result.result~=1 then differences[#differences+1]='unexpected early return' end
      if result.tags ~= case.cache then differences[#differences+1]='cache '..result.tags..' / '..case.cache end
      if result.count ~= #case.after then differences[#differences+1]='node count' end
    end
    compare(result.vector,case.after,differences,'final')
  end
  if #differences==0 then passed=passed+1
  else failed=failed+1; print('FAIL '..case.id..': '..table.concat(differences,', ')) end
end
print(string.format('Native DOS T1 snapshots vs Lua: PASS=%d FAIL=%d TOTAL=%d',passed,failed,#fixtures))
os.exit(failed==0 and 0 or 1)
