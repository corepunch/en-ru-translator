-- Memory-model morphology, 1E71:02AC/0420/05FB/0977/0CDC.
-- Unlike inflect.lua, these preserve all writes to the shared DS:C858 buffer,
-- including failed forms and bytes beyond its terminating NUL.
local memory = require 'core.ltpro.memory'
local runtime = require 'core.ltpro.runtime'
local forms = {}
local linear, null = memory.linear, memory.null
local RESULT = 0xC858
local function signed(n) n = n & 0xFFFF; return n >= 0x8000 and n - 0x10000 or n end
local function put(m, s, o, n, c) m:set8(linear(s, (o + n) & 0xFFFF), c) end
local function append(m, s, o, text)
  m:write_string(s, (o + m:strlen(s, o)) & 0xFFFF, text .. '\0')
end
local function cat(m, offset) m:strcat(m.ds, RESULT, m.ds, offset) end
local function catptr(m, offset) m:strcat(m.ds, RESULT, m:far(linear(m.ds, offset))) end
local function ends(m, s, o, n, offset)
  return runtime.ends_with(m, s, o, n, m.ds, offset) ~= 0
end
local function reflexive(m, s, o, n)
  return n > 2 and (runtime.ends_with(m, s, o, n, m:far(linear(m.ds, 0x630C))) == 2 or
    runtime.ends_with(m, s, o, n, m:far(linear(m.ds, 0x6310))) == 2)
end

local function build(m, id, s, o, length, tableoff, index)
  local row = linear(m.ds, (tableoff + id * 6) & 0xFFFF)
  local cut = signed(length - m:u16(row))
  if cut > 0 then
    local text = m:cstring(s, o):sub(1, cut)
    m:write_string(m.ds, RESULT, text .. string.rep('\0', cut - #text) .. '\0')
  else m:strcpy(m.ds, RESULT, s, o) end
  local rs, ro = m:far(row + 2)
  for _ = 1, math.max(0, index) do
    rs, ro = m:strchr(rs, ro, 0x20)
    if null(rs, ro) then return false end
    ro = (ro + 1) & 0xFFFF
  end
  local marker = m:u8(linear(rs, ro))
  if marker == 0x2D then return false end
  if marker ~= 0x3D then
    if cut == 0 then put(m, m.ds, RESULT, 0, 0) end
    local es, eo = m:strchr(rs, ro, 0x20)
    if null(es, eo) then m:strcat(m.ds, RESULT, rs, ro)
    else
      local n = (eo - ro) & 0xFFFF
      append(m, m.ds, RESULT, m:cstring(rs, ro):sub(1, n))
      put(m, m.ds, RESULT, length + n, 0)
    end
  end
  return true
end

function forms.noun(m, id, s, o, gender, plural, case)
  local tableoff = gender == 0 and 0x55A6 or gender == 2 and 0x5450 or 0x5238
  local index = signed(case + (plural ~= 0 and 6 or 0)) - 1
  if not build(m, id, s, o, m:strlen(s, o), tableoff, index) then return 0, 0 end
  return m.ds, RESULT
end

function forms.adjective(m, id, s, o, gender, plural, case)
  local length = m:strlen(s, o)
  local refl = id ~= 14 and reflexive(m, s, o, length)
  local tableoff = gender == 0 and 0x580C or gender == 2 and 0x5770 or 0x56D4
  if not build(m, id, s, o, length - (refl and 2 or 0), tableoff,
    signed(case + (plural ~= 0 and 6 or 0))) then return 0, 0 end
  if refl then catptr(m, 0x630C) end
  return m.ds, RESULT
end

function forms.verb(m, id, s, o, aspect, flags, person, plural, past, gender)
  local length, index = m:strlen(s, o)
  if flags & 4 ~= 0 then index, past = 6, 0
  elseif past == 1 then index = 7
  elseif person == 0 then m:strcpy(m.ds, RESULT, s, o); return m.ds, RESULT
  else index = signed(person - 1 + (plural ~= 0 and 3 or 0)) end
  local refl = reflexive(m, s, o, length)
  if not build(m, id, s, o, length - (refl and 2 or 0), aspect == 1 and 0x5E90 or 0x5A50, index) then
    return 0, 0
  end
  if past == 1 then
    local n = m:strlen(m.ds, RESULT)
    if (gender ~= 1 or plural ~= 0) and
      (ends(m, m.ds, RESULT, n, 0xB983) or ends(m, m.ds, RESULT, n, 0xB987)) then
      put(m, m.ds, RESULT, n - 2, m:u8(linear(m.ds, (RESULT + n - 1) & 0xFFFF)))
      n = n - 1; put(m, m.ds, RESULT, n, 0)
    elseif ends(m, m.ds, RESULT, n, 0xB98B) then
      n = n - 1; put(m, m.ds, RESULT, n, 0)
    end
    if m:u8(linear(m.ds, (RESULT + n - 1) & 0xFFFF)) ~= 0xAB and (gender ~= 1 or plural == 1) then cat(m, 0xB98E) end
    if plural ~= 0 then cat(m, 0xB990)
    elseif gender == 2 then cat(m, 0xB992)
    elseif gender == 0 then cat(m, 0xB994) end
  end
  if refl then
    catptr(m, (index == 0 or index == 4 or index == 6 or (past == 1 and (gender ~= 1 or plural ~= 0))) and 0x6310 or 0x630C)
  end
  if past == 1 and flags & 2 ~= 0 then cat(m, 0xB996) end
  if flags & 16 ~= 0 then cat(m, 0xB99A) end
  return m.ds, RESULT
end

function forms.participle(m, id, s, o, aspect, tag, passive, past)
  local index = tag == 0x47 and 8 or past == 1 and (passive ~= 0 and 12 or 11) or (passive ~= 0 and 10 or 9)
  local length = m:strlen(s, o)
  local refl = passive == 0 and reflexive(m, s, o, length)
  if not build(m, id, s, o, length - (refl and 2 or 0), aspect == 1 and 0x5E90 or 0x5A50, index) then return 0, 0 end
  if refl then
    if index == 8 and aspect ~= 0 then cat(m, 0xB99E) end
    catptr(m, index == 8 and 0x6310 or 0x630C)
  end
  return m.ds, RESULT
end

-- 1E71:0CDC: pronouns are changed in place, not in the shared buffer.
function forms.pronoun(m, s, o, person, gender, plural, case, prefix)
  local length = m:strlen(s, o)
  local cut, index = length
  local first = m:u8(linear(s, o))
  if person == 0 or first == 0xAD or first == 0xAA or first == 0xE7 or person > 3 then
    index = 8
    while true do
      local rs, ro = m:far(linear(m.ds, (0x6344 + index * 4) & 0xFFFF))
      if null(rs, ro) then return 0, 0 end
      cut = runtime.ends_with(m, s, o, length, rs, ro)
      if cut ~= 0 then break end
      index = index + 1
    end
  elseif person == 1 then index = plural == 1 and 5 or 0
  elseif person == 2 then index = plural == 1 and 6 or 1
  else index = plural == 1 and 7 or gender == 2 and 4 or 2 end
  if case ~= 0 then
    length = (length - cut) & 0xFFFF
    put(m, s, o, length, 0)
    local rs, ro = m:far(linear(m.ds, (0x6314 + index * 4) & 0xFFFF))
    if case ~= 5 and prefix ~= 0 and (index == 2 or index == 3 or index == 4 or index == 7) then
      m:strcpy(s, o, m.ds, 0xBAB1); length = (length + 1) & 0xFFFF
    end
    for _ = 2, signed(case) do
      rs, ro = m:strchr(rs, ro, 0x20)
      if null(rs, ro) then return 0, 0 end
      ro = (ro + 1) & 0xFFFF
    end
    local es, eo = m:strchr(rs, ro, 0x20)
    if null(es, eo) then m:strcat(s, o, rs, ro)
    else
      local n = (eo - ro) & 0xFFFF
      append(m, s, o, m:cstring(rs, ro):sub(1, n)); put(m, s, o, length + n, 0)
    end
  end
  return s, o
end

return forms
