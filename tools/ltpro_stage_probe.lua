local captured = require 'tools.ltpro_records'
local nodes = require 'core.nodes'
local grammar = require 'core.grammar'
local phrasing = require 'core.phrasing'
local reorder = require 'core.reorder'
local encoding = require 'core.encoding'
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
    for _,at in ipairs({0x0B,0x0C,0x0D,0x0E,0x0F,0x66,0x68,0x6A,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B}) do
      if (actual[at] or 0)~=raw:byte(at+1) then differences[#differences+1]=string.format('%s node %d +%02X %d/%d',prefix,i,at,actual[at] or 0,raw:byte(at+1)) end
    end
    for _,at in ipairs({0x12,0x9C,0x11C,0x243}) do
      local stop=assert(raw:find('\0',at+1,true))
      if (actual[at] or '')~=raw:sub(at+1,stop-1) then differences[#differences+1]=string.format('%s node %d string +%02X',prefix,i,at) end
    end
    local aux_offset,aux_segment=string.unpack('<I2I2',raw,0x63)
    local aux=aux_segment*16+aux_offset
    if actual.aux then
      if actual.aux.native_address~=aux then differences[#differences+1]=string.format('%s node %d +62 link',prefix,i) end
    elseif (actual.aux_raw or '\0\0\0\0')~=raw:sub(0x63,0x66) then
      differences[#differences+1]=string.format('%s node %d +62 raw',prefix,i)
    end
  end
end
for _,case in ipairs(fixtures) do
  local records = {}
  for _,record in ipairs(case.before) do
    records[#records+1] = {offset=record.pointer[1],segment=record.pointer[2],bytes=unhex(record.raw_hex)}
  end
  local root, imported = captured.from_records(records)
  for i,record in ipairs(case.before) do
    if record.rules and #record.rules>0 then
      local list={}
      for _,rule in ipairs(record.rules) do list[#list+1]={pattern=rule.pattern,action=rule.action} end
      imported[i-1].rules=list
    end
  end
  local differences = {}
  local rules
  if case.rules then
    rules={}
    for i,rule in ipairs(case.rules) do
      -- Fixture strings are CP866; the scheduler encodes UTF-8 rule text itself.
      rules[i]={rule[1],encoding.decode(rule[2]),rule[3] and encoding.decode(rule[3])}
    end
  end
  local ok, result = pcall(function()
    if case.normalize then grammar.first(root,{terminator=0x2E,rules={}}) end
    if case.stage=='reorder' then
      local vector,count,rebuilt=reorder.apply(root)
      local tags={}
      for i=0,count-1 do tags[#tags+1]=string.char(vector[i][0x0C]) end
      if not rebuilt then tags={case.before_cache} end
      return {vector=vector,count=count,tags=table.concat(tags),events={}}
    end
    if case.stage=='T4' then
      if case.normalize then grammar.first(root,{terminator=0x2E,rules={}}) end
      -- Boundary records take the emulator's allocation addresses, in order.
      local allocated=0
      local boundaries={allocate=function()
        allocated=allocated+1
        return {native_address=assert(case.allocations and case.allocations[allocated],'unexpected native allocation')}
      end}
      return phrasing.run(root,{rules=rules,boundaries=boundaries})
    end
    if case.stage=='T3' then
      if case.normalize then grammar.second(root,{count=#case.before,rules={}}) end
      return grammar.third(root,{count=#case.before,rules=rules,terminator=case.terminator})
    end
    return grammar.second(root,{count=#case.before,rules=rules})
  end)
  if not ok then differences[#differences+1] = tostring(result)
  else
    local count=case.count or #case.after
    if result.tags ~= case.cache then differences[#differences+1]='cache '..result.tags..' / '..case.cache end
    if result.count ~= count then differences[#differences+1]='node count '..result.count..'/'..count end
    compare(result.vector,case.after,differences,'final')
    for _,event in ipairs(result.events) do
      if event.stale then differences[#differences+1]='stale count read at rule '..event.rule end
    end
  end
  if #differences==0 then passed=passed+1
  else failed=failed+1; print('FAIL '..case.id..': '..table.concat(differences,', ')) end
end
print(string.format('Native DOS %s snapshots vs Lua: PASS=%d FAIL=%d TOTAL=%d',fixtures[1] and fixtures[1].stage or 'T2',passed,failed,#fixtures))
os.exit(failed==0 and 0 or 1)
