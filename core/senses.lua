local text = require 'core.text'
local nodes = require 'core.nodes'
local russian = require 'core.russian'
local senses = {}
local digit,alpha=text.digit,text.alpha
local get=nodes.byte
local function set(r,f,v) r[f]=v end

-- Reading text is owned by its node. Parsing advances a string position;
-- alternatives and phrase components receive independent strings.
function senses.skip_prefix(r)
  local off,i=2,0
  while i<5 do
    local c=r.text:byte(off+i) or 0
    if c==0 or not (text.is_cyrillic(c) or digit(c) or c==0x29) then break end
    if c==0x29 then off=off+i+1; r.text=r.text:sub(off); off=1; i=0 else i=i+1 end
  end
  return r.text:sub(off)
end

local CASE_LETTERS = {[0x82] = 8, [0x84] = 4, [0x88] = 0, [0x8F] = 0x20, [0x90] = 2, [0x92] = 0x10}
function senses.parse_code(r, value)
  local off = 1
  local function c() return value:byte(off) or 0 end
  local function take(field)
    if digit(c()) then set(r, field, c() - 0x30); off = off + 1; return true end
    return false
  end
  local tag = get(r, 0x0C)
  if tag == 0x49 then take(0x72)
  elseif tag == 0x4A then
    take(0x73)
    if digit(c()) then set(r, 0x0F, 0x6B); off = off + 1 end
  elseif tag == 0x78 then take(0x73)
  elseif tag == 0x79 then take(0x75); set(r, 0x76, 2)
  elseif tag == 0x44 or tag == 0x4F or tag == 0x50 or tag == 0x51 or tag == 0x70 then
    -- Case letters (CP866 В Д И П Р Т) may repeat; the last one wins.
    while CASE_LETTERS[c()] do
      set(r, 0x76, CASE_LETTERS[c()])
      off = off + 1
    end
    take(0x72)
    take(0x75)
  elseif tag == 0x4D or tag == 0x52 or tag == 0x53 or tag == 0x72 then
    take(0x72)
    take(0x74)
    take(0x77)
    if tag == 0x4D and get(r, 0x76) == 0 then set(r, 0x76, 2) end
    if tag == 0x53 then set(r, 0x74, 3) end
  elseif tag == 0x6E then
    set(r, 0x72, 1)
    set(r, 0x0C, 0x4E)
  else
    if digit(c()) then off = off + 1 end
    if digit(c()) then off = off + 1 end
  end
  return value:sub(off)
end

-- Decode dictionary paradigm metadata and derive agreement fields by tag.
function senses.store_code(r, first, code)
  local function p(i) return code:byte(i+1) or 0 end
  if p(0) == 0 then return end
  local full = first ~= 1
  local dest = first == 1 and 0x67 or 0x6D
  local tag = get(r, 0x0C)
  if tag == 0x4E then
    set(r, dest, p(0)); set(r, dest + 1, p(1))
    if full then
      set(r, dest + 2, p(2))
      if p(2) ~= 0 then set(r, 0x85, get(r, dest + 2) & 0x7F) end
      if (get(r, dest + 1) >> 3) & 1 ~= 0 then set(r, 0x72, 1) end
      if (get(r, dest + 1) >> 2) & 1 ~= 0 then set(r, 0x72, 0) end
    end
    local b = get(r, dest + 1)
    set(r, 0x77, ((b >> 1) & 1) * 2 + (b & 1))
  elseif tag == 0x41 then
    set(r, dest, p(0))
    if full then
      if get(r, dest) & 1 ~= 0 then set(r, dest + 1, p(1)); set(r, dest + 2, p(2))
      else set(r, dest + 2, p(1)) end
      if (get(r, dest) >> 5) & 1 ~= 0 then set(r, 0x7B, 1) end
      set(r, 0x85, get(r, dest + 2) & 0x7F)
    else
      set(r, dest + 1, p(1))
    end
  elseif tag == 0x45 or tag == 0x46 or tag == 0x47 or tag == 0x56 or tag == 0x65 or tag == 0x76 then
    set(r, dest, p(0)); set(r, dest + 1, p(1))
    if full then
      set(r, dest + 2, p(2)); set(r, dest + 3, p(3))
      local case = get(r, 0x76)
      if case == 0 or case == 8 then set(r, 0x76, get(r, dest + 1) & 0x3F) end
      if get(r, 0x6A) & 0x3F == 0 then
        local v = get(r, 0x79)
        if v == 0 or v == 8 then set(r, 0x79, get(r, dest + 3) & 0x3F) end
      end
      set(r, 0x85, get(r, dest + 2) & 0x7F)
    elseif get(r, 0x0C) == 0x45 or get(r, 0x66) == 0x45 then
      set(r, 0x73, 1)
    end
  end
end

function senses.reflexive(state,r)
  r[0x77]=1
  local value,n=r.text,#r.text
  local function back(i) return text.byte(value,n-i) end
  if text.ends(value,state.assets:string(0x484A)) then
    local c=back(5); r[0x85]=(c==0xE7 or c==0xE8 or c==0xE9) and 2 or 0
    return 0
  end
  local c=back(3)
  if c==0xE7 then r[0x85]=(back(2)==0xA5 and back(1)==0xA9) and 0x18 or 2
  elseif c==0xE8 then r[0x85]=back(2)==0xAE and 6 or 2
  elseif c==0xE9 then r[0x85]=2
  else
    local ending=value:sub(-2)
    r.text=value:sub(1,n-2)..'*A'
    return 1,ending
  end
  r[0x0B]=3
  return 0
end

function senses.clone(r,value)
  local copy={}
  for k,v in pairs(r) do copy[k]=v end
  copy[0x89],copy.annotation,copy.alternative,copy.next=0,nil,nil,nil
  copy.text,copy[0x11C]=value,value
  senses.skip_prefix(copy)
  return copy
end

function senses.expand_phrase(state,r)
  local value=r.text
  local i=1
  local function c() return value:byte(i) or 0 end
  local function step() i=i+1 end
  if c()==0x57 then step() end
  if alpha(c()) or c()==0x23 then
    if c()==0x6E then r[0x72]=1; value=value:sub(1,i-1)..'N'..value:sub(i+1) end
    local t=c()
    if t~=0x47 and t~=0x56 and t~=0x45 then r[0x66],r[0x0C]=t,t end
    if c()==0x23 then
      step()
      if digit(c()) then if get(r,0x72)==0 then r[0x72]=c()-48 end; step() end
      if digit(c()) then r[0x77]=c()-48; step()
      elseif c()==0xAC then r[0x77]=1; step()
      elseif c()==0xA6 then r[0x77]=2; step()
      elseif c()==0x63 then r[0x77]=0; step() end
      r[0x74]=3
    else step() end
  end
  value=value:sub(1,(value:find('/',i,true) or (#value+1))-1)
  local tag=get(r,0x0C)
  r[0x0F]=0x77
  local function component(current)
    local start=i
    if current==0x23 then
      while c()~=0 and c()~=0x23 do step() end
      local result=value:sub(start,i-1)
      if c()~=0 then step() end
      local following=c()==0x20 and 0x77 or c()
      if c()~=0 then step() end
      return result,following
    end
    while c()~=0 do
      if alpha(c()) or c()==0x20 or c()==0x23 then break end
      if c()==0x7B then while c()~=0 and c()~=0x7D do step() end end
      step()
    end
    local result=value:sub(start,i-1)
    local following=c()==0x20 and 0x77 or c()
    if c()~=0 then step() end
    return result,following
  end
  local current
  r.text,current=component(tag)
  local last=r
  while current~=0 do
    local value,following=component(current)
    local n=nodes.word(state,current,value)
    if not n then last[0x0B]=0xFF; return 0 end
    n[0x0B],n[0x0F]=3,0x77
    if current==0x56 then
      if tag==0x47 or tag==0x45 then n[0x0C]=tag
      elseif get(last,0x74)==3 then n[0x74]=3 end
    end
    if current==0x4E and get(last,0x72)~=0 then n[0x72]=1 end
    n[0x66]=current==0x6E and 0x4E or current
    n.text=senses.parse_code(n,n.text)
    n.next,last.next=last.next,n
    last,current=n,following
  end
  return tag
end

function senses.select(state, original, r, alt, wtag, wflag)
  local a=state.assets
  local T,length=0,0
  local result,bar,adjective_ending=1,0,nil
  local p,l,t,c,d
  local function reading_byte(i) return text.byte(r.text,i or 0) end
  local function put_reading(i,v) r.text=text.put(r.text,i,v) end
  local function skip_character() r.text=r.text:sub(2) end
  local function set_length() length=#r.text end
  local function lookup(prefix) return russian.lookup(state,r.text,prefix) end
  local function ends(at) return text.ends(r.text,a:string(at),length) end
  local function append_literal(at) r.text=r.text..a:string(at) end
  local function bit6D(n) return (get(r,0x6D) >> n) & 1 end
  local function same_record() return original==r end
  local function release_aux() r.aux=nil end
  local function aux_set() return r.aux~=nil end
  local function copy_from(value) r.text=value end

  T = get(r, 0x0C)
  p = senses.skip_prefix(r)
  if reading_byte(0) == 0x57 or wtag == 0x57 or wflag ~= 0 then
    t = senses.expand_phrase(state, r)
    T = t & 0xFF
    if t & 0xFF == 0 then return 0 end
  end
  if not same_record() then return 1 end
  if T == 0x4E and get(r, 0x66) == 0x41 and (get(r, 0x0F) == 0x77 or get(r, 0x0F) == 0x57) then
    T = 0x41; set(r, 0x0C, 0x41); set(r, 0x76, 0)
  end
  t = T
  if t == 0x41 or t == 0x45 or t == 0x46 or t == 0x47 or t == 0x56 or t == 0x65 or t == 0x76 then
    c = get(r, 0x66)
    if t == 0x41 and not (c == 0x45 or c == 0x65 or c == 0x56 or c == 0x47) then goto adjective end
    if t ~= 0x41 or alt ~= 0 then goto verb end
    ::adjective::
    set_length()
    c = get(r, 0x66)
    if c == 0x23 or c == 0x3F or c == 0x48 then
      set(r, 0x0B, 1); result = 0
    elseif c == 0x49 or length < 3 then
      result = 0
    else
      if alt == 0 then set(r, 0x66, 0x41) end
      result, adjective_ending = senses.reflexive(state, r)
    end
    goto established
    ::verb::
    l = r.text:find("|",1,true)
    goto verb_body
  elseif t == 0x4E then
    goto noun
  elseif t == 0x44 then
    if get(r, 0x66) == 0x50 then r.text = senses.parse_code(r,r.text) end
    if alt == 0 then set(r, 0x66, 0x44) end
    goto none
  elseif t == 0x64 then
    set(r, 0x0C, 0x44); goto none
  elseif t == 0x6E or t == 0x23 then
    if t == 0x23 then T = 0x4E end
    set(r, 0x0C, 0x4E); goto established
  elseif t == 0x4C then
    set(r, 0x74, 3); set(r, 0x77, 1); goto none
  elseif t == 0x4A then
    if get(r, 0x66) == 0x50 and text.is_upper_cyrillic(reading_byte(0)) then set(r, 0x0C, 0x50) end
    goto code
  elseif t == 0x49 or t == 0x4D or t == 0x4F or t == 0x50 or t == 0x51 or t == 0x52 or t == 0x53 or
         t == 0x70 or t == 0x72 or t == 0x78 or t == 0x79 then
    goto code
  else
    goto none
  end

  ::code::
  r.text = senses.parse_code(r,r.text)
  ::none::
  result = 0
  ::established::
  if result == 0 then return 0 end
  -- A Russian lower-case word (or one-letter word): look its form up with
  -- the tag appended ("word*T") unless it is an adjective.
  if reading_byte(0) == 0 or not text.is_lower_cyrillic(reading_byte(0)) then return 0 end
  c = reading_byte(1)
  if not text.is_lower_cyrillic(c) and not (c == 0 or c == 0x20 or c == 0x2E or c == 0x2D or c == 0x2A) then return 0 end
  if T ~= 0x41 then
    set_length()
    put_reading(length, 0x2A)
    put_reading(length + 1, T)
    put_reading(length + 2, 0)
  end
  l = lookup(1)
  if not l then goto not_found end
  p = l:match("%*(.*)")
  if not p then return 0 end
  set(r, 0x6C, (p:byte() or 0))
  p = p:sub(2)
  senses.store_code(r, 0, p)
  if get(r, 0x0C) == 0x41 then
    r.text = r.text:sub(1,length-2) .. adjective_ending .. r.text:sub(length+1)
    set(r, 0x77, 1)
  end
  put_reading(length, 0)
  set(r, 0x0B, 4)
  do return 1 end

  ::not_found::
  t = T
  if t == 0x41 then
    r.text = r.text:sub(1,length-2) .. adjective_ending .. r.text:sub(length+1)
    set(r, 0x77, 1)
    if ends(0x486B) or ends(0x486F) or ends(0x4873) or ends(0x4877) then
      set(r, 0x85, 4)
    elseif ends(0x487B) or ends(0x487E) or ends(0x4881) or ends(0x4884) then
      set(r, 0x85, reading_byte(length - 3) == 0xE6 and 1 or 0)
    end
    set(r, 0x74, 3)
  elseif t == 0x4E then
    put_reading(length, 0)
    set(r, 0x77, 1)
    set(r, 0x74, 3)
  end
  put_reading(length, 0)
  do return 0 end

  ::noun::
  set(r, 0x0C, 0x4E)
  c = get(r, 0x66)
  if c == 0x23 or c == 0x3F then
    -- Gender of a number word from the text after the reading's prefix.
    c = (p:byte() or 0)
    if digit(c) then set(r, 0x77, c - 0x30); p = p:sub(2)
    elseif c == 0xAC then set(r, 0x77, 1); p = p:sub(2)
    elseif c == 0xA6 then set(r, 0x77, 2); p = p:sub(2)
    elseif c == 0xE1 then set(r, 0x77, 0); p = p:sub(2) end
    set(r, 0x0B, 1)
    return 1
  end
  if digit(reading_byte(0)) then
    set(r, 0x75, reading_byte(0) - 0x30)
    skip_character()
  elseif get(r, 0x66) == 0x4E or alt == 0 then
    -- nothing
  else
    if wtag ~= 0 and wtag ~= 0x56 then
      local i = r.text:find('V',1,true)
      if i then r.text=r.text:sub(i+1) end
      r.text=r.text:match('^[^A-Z]*')
    end
    r.text = russian.replace_ending(state,r.text) or r.text
  end
  set(r, 0x76, 0)
  set(r, 0x74, 3)
  goto established

  ::verb_body::
  -- An alternative after '|' is used when +75 (aspect) is 1.
  if get(r, 0x75) == 1 and l then
    r.text = r.text:sub(l+1)
    bar = 0
  else
    if l then r.text=r.text:sub(1,l-1) end
    bar = 1
  end
  if get(r, 0x0C) ~= 0x45 then set(r, 0x77, 1) end
  if get(r, 0x66) == 0x5A then set(r, 0x72, 0) end
  if digit(reading_byte(0)) then
    d = (reading_byte(0) - 0x30) & 0x3F
    skip_character()
    set(r, 0x68, (get(r, 0x68) & 0xC0) | d)
    set(r, 0x68, (get(r, 0x68) & 0xBF) | ((d & 1) << 6))
  end
  if digit(reading_byte(0)) then
    d = (reading_byte(0) - 0x30) & 1
    skip_character()
    set(r, 0x6A, (get(r, 0x6A) & 0xBF) | (d << 6))
  end
  if digit(reading_byte(0)) then
    d = (reading_byte(0) - 0x30) & 0x3F
    skip_character()
    set(r, 0x6A, (get(r, 0x6A) & 0xC0) | d)
  end
  if reading_byte(0) == 0 or not text.is_lower_cyrillic(reading_byte(0)) then return 0 end
  c = reading_byte(1)
  if not text.is_lower_cyrillic(c) and not (c == 0 or c == 0x20 or c == 0x2E or c == 0x2D) then return 0 end
  l = lookup(0)
  set_length()
  if not l and ends(0x4850) then
    put_reading(length - 2, 0)
    l = lookup(0)
    append_literal(0x4853)
  end
  if not l then
    return 0
  end
  p = l:match("%*(.*)")
  if not p then return 0 end
  senses.store_code(r, 0, p:sub(2))
  if get(r, 0x75) == 1 and bar ~= 0 and (p:byte() or 0) == 0x56 and
     (p:byte(2) or 0) ~= 0 and (p:byte(6) or 0) ~= 0 and
     bit6D(3) == 0 and bit6D(1) == 0 then
    -- The perfective partner named after the code ("V....partner").
    copy_from(p:sub(6))
    if text.is_lower_cyrillic(reading_byte(0)) and text.is_lower_cyrillic(reading_byte(1)) then
      l = lookup(0)
      set_length()
      if not l and ends(0x4856) then
        put_reading(length - 2, 0)
        l = lookup(0)
        append_literal(0x4859)
      end
      if l then
        p = l:match("%*(.*)") or ""
      end
    end
  end
  set(r, 0x6C, (p:byte() or 0))
  p = p:sub(2)
  senses.store_code(r, 0, p)
  if bit6D(2) ~= 0 and bit6D(3) == 0 then set(r, 0x75, 1) end
  if bit6D(3) ~= 0 and bit6D(2) == 0 then set(r, 0x75, 0) end
  if ends(0x485C) then
    set(r, 0x76, get(r, 0x79))
  elseif bit6D(4) ~= 0 then
    append_literal(0x485F)
    set(r, 0x76, get(r, 0x79))
  elseif get(r, 0x78) & 1 == 0 then
    -- nothing
  elseif bit6D(5) == 0 then
    append_literal(0x4862)
    set(r, 0x76, get(r, 0x79))
  else
    set(r, 0x78, get(r, 0x78) & 0xFE)
    set(r, 0x7A, (get(r, 0x0C) == 0x56 and get(r, 0x73) == 1) and 0 or 1)
    set(r, 0x7B, 1)
    set(r, 0x73, 1)
    if (p:byte(5) or 0) ~= 0 and get(r, 0x75) == 0 and bit6D(3) == 0 and bit6D(1) == 0 then
      copy_from(p:sub(5))
    end
    set(r, 0x75, 1)
  end
  if get(r, 0x73) == 2 and aux_set() then
    if bit6D(3) ~= 0 then
      set(r, 0x78, 8); set(r, 0x74, 0); set(r, 0x72, 0)
    elseif same_record() then
      release_aux()
    end
  end
  if get(r, 0x0C) == 0x56 and get(r, 0x7A) ~= 0 and not aux_set() and bit6D(3) ~= 0 and
     get(r, 0x6A) & 0x3F == 0 and get(r, 0x75) == 0 then
    set(r, 0x75, 0); set(r, 0x78, 1); set(r, 0x73, 0)
    append_literal(0x4865)
    set(r, 0x7A, 0); set(r, 0x7B, 0)
  end
  if get(r, 0x7A) ~= 0 and aux_set() then
    if bit6D(3) ~= 0 then
      set(r, 0x75, 0); set(r, 0x78, 1)
      append_literal(0x4868)
      set(r, 0x7A, 0); set(r, 0x7B, 0)
      if same_record() then release_aux() end
    else
      set(r, 0x73, 1)
    end
  end
  set(r, 0x0B, 4)
  return 1
end

-- Select a tagged reading and split its alternatives and annotations.
function senses.choose(state,r)
  local value=r.text
  local t=get(r,0x0C)
  if t==0x47 or t==0x46 or t==0x45 or t==0x65 then t=0x56 end
  local tag=string.char(t)
  local p=value:find(tag..'.',1,true)
  if p then p=p+1
  else
    local annotated=value:find('{',1,true)
    if t==0x4E then
      p=value:find('n.',1,true)
      if p then r[0x72]=1; p=p+1
      elseif not annotated then
        p=value:find(tag,1,true)
        if not p then p=value:find('n',1,true); if p then r[0x72]=1 end end
      end
    elseif not annotated then p=value:find(tag,1,true) end
  end
  local unmarked=p and 0 or 1
  p=p or 1
  local q=p+1
  while q<=#value do
    local c=value:byte(q)
    if c==0x57 or value:byte(p)==0x57 then
      repeat q=q+1 until q>#value or value:byte(q)==0x2F
    elseif c==0x7B then
      repeat q=q+1 until q>#value or value:byte(q)==0x7D
    elseif alpha(c) or c==0x23 or c==0x5C then break end
    q=q+1
  end
  r.text=value:sub(p,q-1)
  senses.skip_prefix(r)
  local wflag=(value:byte(p-1)==0x57) and 1 or 0
  local wtag=r.text:byte() or 0
  if wtag==0x2E then r.text=r.text:sub(2)
  else
    if alpha(wtag) or wtag==0x23 then r.text=r.text:sub(2) end
    if r.text:sub(1,1)=='.' then r.text=r.text:sub(2) end
  end
  if r.text:sub(1,1)=='W' or wtag==0x57 then wflag=1 end
  local last,current=r,r
  local start=current.text:find('[;{/]')
  while start do
    local value=current.text
    local i=start
    while i<=#value and not value:sub(i,i):find('[;{/]') do i=i+1 end
    local cut=i
    if value:sub(i,i)=='/' then i=i+1 end
    if value:sub(i,i)=='{' then
      local finish=value:find('}',i+1,true) or (#value+1)
      if not last.annotation then last.annotation=value:sub(i+1,finish-1) end
      i=finish+1
    end
    if value:sub(i,i)==';' then
      r[0x89]=(get(r,0x89)+1) & 255
      current.text=value:sub(1,cut-1)
      local rest=value:sub(i+1)
      if rest~='' then
        local clone=senses.clone(r,rest)
        clone[8]=get(r,0x89); last.alternative=clone
        last,current=clone,clone
        start=current.text:find('[;{/]')
      else break end
    else current.text=value:sub(1,cut-1); break end
  end
  senses.select(state,r,r,unmarked,wtag,wflag)
  return 1
end

function senses.numeric_pass(state,root)
  local r=root.next
  while r do
    if get(r,0x0E)==0x57 then
      if get(r,0x0C)==0x48 then
        if get(r,0x0F)~=0x68 then
          local length=r[0x87] or 0
          local source=r[0x12] or ''
          local last=source:byte(length) or 0
          local tens=source:byte(length-1) or 0
          if last==0x31 then
            if length>1 and tens==0x31 then r[0x72]=1 end
          elseif last>=0x32 and last<=0x34 then
            if length>1 and tens~=0x32 and tens~=0x33 and tens~=0x34 then r[0x72]=1 end
          else r[0x72]=1 end
        end
        r[0x74],r[0x77]=3,1
      elseif get(r,0x0B)>1 then
        local tag=get(r,0x0C)
        if not (tag==0x23 and get(r,0x0F)~=0x3D) and tag~=0x3F then senses.choose(state,r) end
      end
    end
    r=r.next
  end
  return 1
end
return senses
