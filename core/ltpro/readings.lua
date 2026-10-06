-- LTPRO 0A4F:0C0F (file EAFF..F45E): decode one lexical reading's metadata.
-- The caller has consumed the tag; payload and returned offset are CP866 bytes.
local readings = {}
local function tag(n) return string.char(n[0x0C] or 0) end
local function has(s,c) return s:find(c,1,true) ~= nil end
local cases = {[0x82]=8,[0x84]=4,[0x8F]=32,[0x90]=2,[0x92]=16}

function readings.decode(node, payload, options)
  options = options or {}
  assert(tag(node)~='#', 'native unknown-word reading decoder is not ported')
  local p=1
  local function digit(at)
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then node[at]=b-48; p=p+1; return true end
    return false
  end
  local function paradigm(at)
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      local value=b-48
      node[at]=((node[at] or 0)&0x80)|value|((value&1)<<6)
      p=p+1
    end
  end
  local function aspect()
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      node[0x6A]=((node[0x6A] or 0)&0xBF)|(((b-48)&1)<<6)
      p=p+1
    end
  end
  local t=tag(node)
  if has('XYx',t) then
    digit(0x73);digit(0x72);digit(0x74)
    if t=='Y' then node[0x76]=8 end
  elseif t=='y' then digit(0x75);node[0x76]=2
  elseif t=='d' then digit(0x75);digit(0x73)
  elseif has('MRr',t) then
    digit(0x72);digit(0x74);digit(0x77)
    if t=='M' then node[0x76]=2 end
  elseif has('OS',t) then digit(0x72);digit(0x75);digit(0x77);node[0x74]=3
  elseif has('PQfp',t) then
    local b=payload:byte(p)
    if b and b>0x81 and b<0x93 then
      if cases[b] then node[0x76]=cases[b] end
      p=p+1
    end
  elseif t=='I' then digit(0x72)
  elseif t=='U' then
    digit(0x73);digit(0x78);node[0x76],node[0x74]=8,3
  elseif t=='J' then digit(0x73);digit(0x75)
  elseif t=='N' then digit(0x75)
  elseif t=='n' then digit(0x75);node[0x72]=1
  elseif t=='a' then node[0x0F]=0x61
  elseif t=='v' then paradigm(0x68);aspect();node[0x74],node[0x76]=3,8
  elseif t=='z' then paradigm(0x68);aspect();node[0x72],node[0x74],node[0x76]=1,3,8
  elseif has('eEFGVZh',t) then
    if t=='e' and node[0x0B]==1 and node[0x74]==3 then
      node[0x0C],node[0x66]=0x56,0x56
    end
    paradigm(0x68);aspect()
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      node[0x6A]=((node[0x6A] or 0)&0xC0)|((b-48)&0x3F);p=p+1
    end
    node[0x76]=8
    t=tag(node)
    if has('EehF',t) or node[0x66]==0x45 then node[0x73]=1 end
    if t=='h' then node[0x0C],node[0x66]=0x56,0x56
    else
      b=payload:byte(p)
      if t=='E' and ((node[0x6A] or 0)&0x3F)==1 and b and b>0x81 and b<0x93 then
        if cases[b] then node[0x76]=cases[b] end
        p=p+1
      end
      if t=='F' then node[0x0F],node[0x0C]=0x6E,0x45 end
    end
  end
  t=tag(node)
  if not has('ekxjtudbiplyfgac',t) then node[0x0C]=t:upper():byte() end
  local text=payload:sub(p)
  assert(text:sub(1,1)~='=' and text:sub(1,1)~='%', 'native lexical macros are not ported')
  node[0x0B],node[0x11C]=3,text
  return p-1
end

return readings
