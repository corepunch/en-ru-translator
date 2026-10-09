local text = require 'core.text'
local nodes = require 'core.nodes'
local output = {}
local get=nodes.number
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
  local meaning_start=state.meaning_start
  local r=assert(root.next,'output requires the leading boundary')
  local initial_caps=get(r,9)
  local chunks={}
  local function emit(value) chunks[#chunks+1]=value end
  while r do
    local function b(f) return get(r,f) end
    local function str(f) return r[f] or '' end
    local function leading_upper(f) return text.upper_ascii(b(f)) end
    local function cap_translation(all,skip,start) r.text=capital(r.text or '',all,skip,start) end
    if b('kind')==0x44 then
      local delimiter=b('separator')
      if delimiter==0x20 then
        local c=b('source'); emit(' '..(c~=0 and string.char(c) or ''))
      elseif delimiter~=0x2A and delimiter~=0x5E and delimiter~=0x7C and b('source')~=0 then emit(string.char(b('source'))) end
      if b('marker')~=0 and r.next and get(r.next,'kind')==0x57 then r.next.separator=0x20 end
    elseif r.literal then
      emit((r.literal_joined and '' or ' ') .. r.literal)
    else
      if b('tag')~=0x3F then
        local partner=r.aux
        if partner and (partner.text or '')~='' then
          si=capitals(partner.source or '')
          if text.upper_ascii(get(partner,'source')) then partner.text=capital(partner.text,false) end
          if si>1 then partner.text=capital(partner.text,true,false,2) end
          if b('separator')==0 then emit(a:string(0x5F5)) end
          emit(partner.text)
        end
        local marker=b('marker')
        if r.phrase_case then
          local casing=r.phrase_case
          if casing.caps>1 then cap_translation(true)
          elseif r==casing.first and casing.caps>0 then cap_translation(false) end
          first=false
        elseif (marker==0x77 or marker==0x57) and previous and (get(previous,'marker')==0x77 or get(previous,'marker')==0x57) then
          if text.is_upper_cyrillic((previous.text or ''):byte() or 0) or leading_upper('source') then
            cap_translation(false)
            if si>1 then cap_translation(true,false,2) end
          end
        elseif first and initial_caps~=0 then
          first=false
          si=math.max(initial_caps,capitals(str('suffix')))
          r.prefix=capital(str('prefix'),si>1)
          local suppressed=(marker==0x3D or marker==0x25) and leading_upper('source') and text.is_upper_cyrillic((r.text or ''):byte() or 0)
          si=suppressed and 0 or math.max(initial_caps,capitals(str('source')))
          cap_translation(si>1,si<=1)
        else
          local suppressed=(marker==0x3D or marker==0x25) and leading_upper('source') and text.is_upper_cyrillic((r.text or ''):byte() or 0)
          si=suppressed and 0 or capitals(str('suffix'))
          if leading_upper('suffix') then r.prefix=capital(str('prefix'),false) end
          if si>1 then r.prefix=capital(str('prefix'),true,false,2) end
          si=suppressed and 0 or capitals(str('source'))
          if leading_upper('source') then cap_translation(false) end
          if si>1 then cap_translation(true,false,2) end
        end
      end
      if b('reading_state')>1 then
        local value=r.text or ''
        if value~='' then
          local c=value:byte()
          if b('separator')==0 and c~=0x2C and c~=0x3A then emit(a:string(0x5F7)) end
          emit(str('prefix'))
          if c==0x2C then
            assert(previous,'output requires a previous record')
            if get(previous,'kind')==0x44 and (get(previous,'separator')==0x2A or get(previous,'tag')==0x28 or get(previous,'source')==0x2C) then
              r.text=r.text:sub(get(previous,'source')==0x2C and 2 or 3)
            end
          end
          emit(r.text)
          local alt=r.alternative
          if alt then
            r.meaning_number=(meaning_start or a:word(0x042B))+count
            emit(a:string(0x45C)..string.format(a:string(0x5F9),r.meaning_number))
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
        if b('separator')==0 then emit(a:string(0x603)) end
        emit(b('tag')==0x23 and str('prefix'):find('-',1,true) and str('prefix') or str('suffix'))
        if b('previous_tag')==0x23 and b('source')~=0 then
          local apostrophe=str('source'):match(".*()'")
          if apostrophe and str('source'):sub(apostrophe+1,apostrophe+1):lower()=='s' then
            r.source=str('source'):sub(1,apostrophe-1)
          end
        end
        emit(str('source'))
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
    if get(r,'kind')==0x57 and (r.alternative or r.annotation) then
      local source=(r.source or ''):lower()
      if r.alternative then
        local number=r.meaning_number or (state.meaning_start or a:word(0x042B))+count
        chunks[#chunks+1]=string.format(a:string(0x5CE),number,source)
        count=count+1
      else
        -- Annotation-only entries have no numbered inline reference.
        chunks[#chunks+1]='\n   '..source..': '
      end
      local reading=(r.text or ''):gsub('^,',''):gsub('^ ','')
      chunks[#chunks+1]=r.annotation and string.format(a:string(0x5D9),r.annotation,reading) or string.format(a:string(0x5E1),reading)
      local alt=r.alternative
      while alt do
        local value=output.reading(alt.text)
        chunks[#chunks+1]=alt.annotation and string.format(a:string(0x5E6),alt.annotation,value) or string.format(a:string(0x5F0),value)
        alt=alt.alternative
      end
    end
    r=r.next
  end
  return table.concat(chunks)
end
return output
