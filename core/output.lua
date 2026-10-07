local text = require 'core.text'
local nodes = require 'core.nodes'
local output = {}
local get=nodes.byte
local function upper(c)
  if c>=0xE0 and c<0xF0 then return c-0x50 end
  if c>=0xA0 and c<0xB0 then return c-0x20 end
  return c==0xF1 and 0xF0 or c
end
local function capitals(value)
  local _,n=value:gsub('[A-Z]','')
  return n
end
local function capital(value,all,skip,start)
  local i=start or 1
  if skip then
    if value:byte(i)==0x2C then i=i+1 end
    if value:byte(i)==0x20 then i=i+1 end
  end
  local finish=all and #value or math.min(i,#value)
  local chars={value:sub(1,i-1)}
  for j=i,finish do chars[#chars+1]=string.char(upper(value:byte(j))) end
  chars[#chars+1]=value:sub(finish+1)
  return table.concat(chars)
end

function output.reading(value)
  if value:sub(1,1)~='W' then return value end
  local bytes,i={},2
  while i<=#value do
    local c=value:byte(i)
    if c==0x23 or c==0x7B then
      bytes[#bytes+1]=' '
      local close=value:find(c==0x23 and '#' or '}',i+1,true)
      assert(close,'unterminated W-reading annotation')
      bytes[#bytes+1]=value:sub(i+1,close-1)
      break
    end
    bytes[#bytes+1]=text.alpha(c) and ' ' or string.char(c)
    i=i+1
  end
  local result=table.concat(bytes)
  return result:sub(1,1)==' ' and result:sub(2) or result,result
end

function output.sentence(state,root)
  local a=state.assets
  local si,first,count,previous=0,true,0,nil
  local r=assert(root.next,'output requires the leading boundary')
  local initial_caps=get(r,9)
  local chunks={}
  local function emit(value) chunks[#chunks+1]=value end
  while r do
    local function b(f) return get(r,f) end
    local function str(f) return r[f] or '' end
    local function leading_upper(f) return text.upper_ascii(b(f)) end
    local function cap_translation(all,skip,start) r.text=capital(r.text or '',all,skip,start) end
    if b(0x0E)==0x44 then
      local delimiter=b(0x0D)
      if delimiter==0x20 then
        local c=b(0x12); emit(' '..(c~=0 and string.char(c) or ''))
      elseif delimiter~=0x2A and delimiter~=0x5E and delimiter~=0x7C and b(0x12)~=0 then emit(string.char(b(0x12))) end
      if b(0x0F)~=0 and r.next and get(r.next,0x0E)==0x57 then r.next[0x0D]=0x20 end
    else
      if b(0x0C)~=0x3F then
        local partner=r.aux
        if partner and (partner.text or '')~='' then
          si=capitals(partner[0x12] or '')
          if text.upper_ascii(get(partner,0x12)) then partner.text=capital(partner.text,false) end
          if si>1 then partner.text=capital(partner.text,true,false,2) end
          if b(0x0D)==0 then emit(a:string(0x5F5)) end
          emit(partner.text)
        end
        local marker=b(0x0F)
        if (marker==0x77 or marker==0x57) and previous and (get(previous,0x0F)==0x77 or get(previous,0x0F)==0x57) then
          if text.is_upper_cyrillic((previous.text or ''):byte() or 0) or leading_upper(0x12) then
            cap_translation(false)
            if si>1 then cap_translation(true,false,2) end
          end
        elseif first and initial_caps~=0 then
          first=false
          si=math.max(initial_caps,capitals(str(0x21B)))
          r[0x243]=capital(str(0x243),si>1)
          local suppressed=(marker==0x3D or marker==0x25) and leading_upper(0x12) and text.is_upper_cyrillic((r.text or ''):byte() or 0)
          si=suppressed and 0 or math.max(initial_caps,capitals(str(0x12)))
          cap_translation(si>1,si<=1)
        else
          local suppressed=(marker==0x3D or marker==0x25) and leading_upper(0x12) and text.is_upper_cyrillic((r.text or ''):byte() or 0)
          si=suppressed and 0 or capitals(str(0x21B))
          if leading_upper(0x21B) then r[0x243]=capital(str(0x243),false) end
          if si>1 then r[0x243]=capital(str(0x243),true,false,2) end
          si=suppressed and 0 or capitals(str(0x12))
          if leading_upper(0x12) then cap_translation(false) end
          if si>1 then cap_translation(true,false,2) end
        end
      end
      if b(0x0B)>1 then
        local value=r.text or ''
        if value~='' then
          local c=value:byte()
          if b(0x0D)==0 and c~=0x2C and c~=0x3A then emit(a:string(0x5F7)) end
          emit(str(0x243))
          if c==0x2C then
            assert(previous,'output requires a previous record')
            if get(previous,0x0E)==0x44 and (get(previous,0x0D)==0x2A or get(previous,0x0C)==0x28 or get(previous,0x12)==0x2C) then
              r.text=r.text:sub(get(previous,0x12)==0x2C and 2 or 3)
            end
          end
          emit(r.text)
          local alt=r.alternative
          if alt then
            emit(a:string(0x45C)..string.format(a:string(0x5F9),a:word(0x042B)+count))
            count=count+1
            while alt do
              emit(output.reading(alt.text))
              alt=alt.alternative
              if alt then emit(a:string(0x5FF)) end
            end
            emit(a:string(0x601))
          end
        end
      else
        if b(0x0D)==0 then emit(a:string(0x603)) end
        emit(b(0x0C)==0x23 and str(0x243):find('-',1,true) and str(0x243) or str(0x21B))
        if b(0x66)==0x23 and b(0x12)~=0 then
          local apostrophe=str(0x12):match(".*()'")
          if apostrophe and str(0x12):sub(apostrophe+1,apostrophe+1):lower()=='s' then
            r[0x12]=str(0x12):sub(1,apostrophe-1)
          end
        end
        emit(str(0x12))
      end
    end
    previous,r=r,r.next
  end
  return table.concat(chunks),count
end

function output.meanings(state,root)
  local a,chunks,count=state.assets,{},0
  local r=root.next
  while r do
    if get(r,0x0E)==0x57 and (r.alternative or r.annotation) then
      local source=(r[0x12] or ''):lower()
      chunks[#chunks+1]=string.format(a:string(0x5CE),a:word(0x042B)+count,source)
      r.text=(r.text or ''):gsub('^,',''):gsub('^ ','')
      chunks[#chunks+1]=r.annotation and string.format(a:string(0x5D9),r.annotation,r.text) or string.format(a:string(0x5E1),r.text)
      local alt=r.alternative
      while alt do
        local value=output.reading(alt.text)
        chunks[#chunks+1]=alt.annotation and string.format(a:string(0x5E6),alt.annotation,value) or string.format(a:string(0x5F0),value)
        alt=alt.alternative
      end
      count=count+1
    end
    r=r.next
  end
  return table.concat(chunks)
end
return output
