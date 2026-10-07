-- Literal-key branch of 0A4F:1713 and reading distribution in 0A4F:18F8.
-- Pattern keys, macros and record insertion markers require separate ports.
local nodes=require 'core.ltpro.nodes'
local readings=require 'core.ltpro.readings'
local phrases={}
function phrases.match(dictionary, records, index, key)
  local best,finish
  for _,record in ipairs(dictionary.by_token[key] or {}) do
    if record.key:find(' ',1,true) and record.key:match("^[A-Za-z '-]+$") then
      local words={}
      for w in record.key:gmatch('%S+') do words[#words+1]=w:lower() end
      local matched=words[1]==key
      for j=2,#words do
        local n=records[index+j-1]
        if not n or n[0x0E]~=0x57 or n[0x12]:lower()~=words[j] then matched=false;break end
      end
      if matched and record.value:sub(1,1)~='$' and (not finish or index+#words-1>finish) then
        best,finish=record,index+#words-1
      end
    end
  end
  return best,finish
end
function phrases.apply(record, records, first, last)
  local value=record.value:match('^[^\\]*')
  local node=records[first]
  if value:sub(1,1)~='W' then
    local t=value:sub(1,1)
    node[0x66]=t:upper():byte()
    if not (t:match('[VZ]') and nodes.tag(node):match('[EeGFh]')) then node[0x0C]=t:byte() end
    if nodes.tag(node)=='V' and node[0x12]:sub(-1)~="'" then node[0x72]=0 end
    node[0x0F]=0x77
    readings.decode(node,value:sub(2))
    for _=first+1,last do table.remove(records,first+1) end
    return first+1
  end
  local pos,tag=3,value:sub(2,2)
  local oldtag,number=nodes.tag(node),node[0x72] or 0
  local index=first
  while index<=last or tag~='' do
    assert(tag~='' and tag:match('[ANnVvEhFebPCwX]'), 'native W phrase selector is not ported: '..tag)
    local stop=pos
    while stop<=#value and not value:sub(stop,stop):match('[A-Za-z ~#/;]') do
      if value:sub(stop,stop)=='{' then stop=assert(value:find('}',stop,true),'unterminated phrase annotation') end
      stop=stop+1
    end
    local text=value:sub(pos,stop-1)
    assert(not text:match('^[=%%]'),'native phrase macros are not ported')
    local nexttag=value:sub(stop,stop)
    if nexttag==' ' then nexttag='w' end
    if index>last then
      local fresh=nodes.new(tag,{[0x0E]=0x57,[0x0F]=0x77,[0x12]='',[0x9C]='',
        [0x85]=0xFF,[0x86]=0xFF,[0x87]=#text,[0x10]=0})
      for at=0x68,0x7B do fresh[at]=0 end
      table.insert(records,index,fresh)
      last=index
    end
    local n=records[index]
    n[0x0B]=2
    if tag=='n' then n[0x72]=1;tag='N'
    elseif tag=='v' then n[0x74]=3;tag='V'
    elseif tag=='N' then
      if text:match('^%d') then n[0x75]=tonumber(text:sub(1,1));text=text:sub(2) end
      if number~=0 then n[0x72]=1 end
    elseif tag=='V' or tag=='E' then
      if oldtag=='G' or oldtag=='E' then
        tag=oldtag;n[0x76]=8
        if nodes.tag(n)=='E' then n[0x73]=1 end
      elseif oldtag=='F' then tag='E';n[0x76],n[0x73],n[0x0F]=8,1,0x6E
      elseif oldtag=='h' then n[0x76],n[0x73]=8,1 end
    elseif tag=='h' then n[0x73]=1;tag='V'
    elseif tag=='F' then tag='E';n[0x73],n[0x76],n[0x0F]=1,8,0x6E
    elseif tag=='e' and oldtag=='G' then tag=oldtag
    elseif tag=='X' then
      for _,at in ipairs({0x73,0x72,0x74}) do
        if text:match('^%d') then n[at]=tonumber(text:sub(1,1));text=text:sub(2) end
      end
    end
    n[0x0C],n[0x66],n[0x11C]=tag:byte(),tag:upper():byte(),text
    if (n[0x0F] or 0)==0 then n[0x0F]=0x77 end
    tag,pos=nexttag,stop+1
    if tag=='' then
      for _=index+1,last do table.remove(records,index+1) end
      return index+1
    end
    index=index+1
  end
  return last+1
end
return phrases
