local memory = require 'core.memory'

local generation = {}

-- Memory-model morphology, 1E71:02AC/0420/05FB/0977/0CDC.
-- These preserve all writes to the shared DS:C858 buffer,
-- including failed forms and bytes beyond its terminating NUL.
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
  return memory.ends_with(m, s, o, n, m.ds, offset) ~= 0
end
local function reflexive(m, s, o, n)
  return n > 2 and (memory.ends_with(m, s, o, n, m:far(linear(m.ds, 0x630C))) == 2 or
    memory.ends_with(m, s, o, n, m:far(linear(m.ds, 0x6310))) == 2)
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

function generation.noun_form(m, id, s, o, gender, plural, case)
  local tableoff = gender == 0 and 0x55A6 or gender == 2 and 0x5450 or 0x5238
  local index = signed(case + (plural ~= 0 and 6 or 0)) - 1
  if not build(m, id, s, o, m:strlen(s, o), tableoff, index) then return 0, 0 end
  return m.ds, RESULT
end

function generation.adjective_form(m, id, s, o, gender, plural, case)
  local length = m:strlen(s, o)
  local refl = id ~= 14 and reflexive(m, s, o, length)
  local tableoff = gender == 0 and 0x580C or gender == 2 and 0x5770 or 0x56D4
  if not build(m, id, s, o, length - (refl and 2 or 0), tableoff,
    signed(case + (plural ~= 0 and 6 or 0))) then return 0, 0 end
  if refl then catptr(m, 0x630C) end
  return m.ds, RESULT
end

function generation.verb_form(m, id, s, o, aspect, flags, person, plural, past, gender)
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

function generation.participle_form(m, id, s, o, aspect, tag, passive, past)
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
function generation.pronoun_form(m, s, o, person, gender, plural, case, prefix)
  local length = m:strlen(s, o)
  local cut, index = length
  local first = m:u8(linear(s, o))
  if person == 0 or first == 0xAD or first == 0xAA or first == 0xE7 or person > 3 then
    index = 8
    while true do
      local rs, ro = m:far(linear(m.ds, (0x6344 + index * 4) & 0xFFFF))
      if null(rs, ro) then return 0, 0 end
      cut = memory.ends_with(m, s, o, length, rs, ro)
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

-- LTPRO generation, 17AA:000A/0045/02E8/0475/1D31.
-- CP866 strings and native far pointers remain in the shared memory model.

local NUMERAL_ENDINGS = {
  {0x4960, 13}, {0x4965, 6}, {0x496B, 16}, {0x496F, 0},
  {0x4972, 14}, {0x4977, 10}, {0x497B, 10}, {0x497F, 12},
  {0x4983, 9}, {0x4987, 17}, {0x498C, 18}, {0x4990, 19},
  {0x4994, 20}, {0x499B, 21}, {0x49A0, 21}, {0x49A6, 21},
  {0x49AB, 22}, {0x49B2, 21}, {0x49B9, 21}, {0x49C0, 23},
  {0x49CC, 25},
}

-- First set case bit wins; the nominative bit is implicit.
function generation.case(mask)
  for i = 1, 5 do if mask & (1 << i) ~= 0 then return i end end
  return 0
end

local function record(m, s, o)
  local p = linear(s, o)
  local r = {s = s, o = o, p = p}
  function r.b(n) return m:u8(p + n) end
  function r.w(n) return m:s16(p + n) end
  function r.set(n, v) m:set8(p + n, v) end
  function r.word(n, v) m:set16(p + n, v) end
  function r.ptr(n) return m:far(p + n) end
  function r.text() return m:cstring(r.ptr(0x98)) end
  function r.length() return m:strlen(r.ptr(0x98)) end
  function r.put(n, c)
    local ts, to = r.ptr(0x98)
    m:set8(linear(ts, (to + n) & 0xFFFF), c)
  end
  function r.byte(n)
    local ts, to = r.ptr(0x98)
    return m:u8(linear(ts, (to + n) & 0xFFFF))
  end
  function r.ends(offset, n)
    local ts, to = r.ptr(0x98)
    return memory.ends_with(m, ts, to, n or r.length(), m.ds, offset) ~= 0
  end
  function r.cat(offset)
    local ts, to = r.ptr(0x98); m:strcat(ts, to, m.ds, offset)
  end
  function r.copy(offset)
    local ts, to = r.ptr(0x98); m:strcpy(ts, to, m.ds, offset)
  end
  function r.save(ts, to)
    if null(ts, to) then return false end
    m:strcpy(s, (o + 0x11C) & 0xFFFF, ts, to)
    m:set_far(p + 0x98, s, (o + 0x11C) & 0xFFFF)
    return true
  end
  function r.localize()
    local ts, to = r.ptr(0x98)
    if ts ~= s or to ~= (o + 0x11C) & 0xFFFF then r.save(ts, to) end
  end
  function r.valid() return r.w(0x85) >= 0 and r.w(0x85) < 0x7F end
  function r.adjective()
    local ts, to = r.ptr(0x98)
    return r.save(generation.adjective_form(m, r.w(0x85), ts, to, r.b(0x77), r.b(0x72), generation.case(r.b(0x76))))
  end
  function r.verb(id, aspect)
    local ts, to = r.ptr(0x98)
    return r.save(generation.verb_form(m, id or r.w(0x85), ts, to, aspect or r.b(0x75), r.b(0x78),
      r.b(0x74), r.b(0x72), r.b(0x73), r.b(0x77)))
  end
  return r
end

-- 17AA:0045: participle formation, then short form or adjective agreement.
function generation.participle(m, s, o)
  local r = record(m, s, o)
  local ts, to = r.ptr(0x98)
  if not r.save(generation.participle_form(m, r.w(0x85), ts, to, r.b(0x75), r.b(0x0C), r.b(0x7A), r.b(0x73))) then return end
  local n = r.length()
  if r.b(0x7B) ~= 0 then
    if r.ends(0x48BC, n) then n = n - 2; r.put(n, 0) end
    n = r.length()
    r.put(n - (r.byte(n - 3) == 0xAD and 3 or 2), 0)
    if r.b(0x72) ~= 0 then r.cat(0x48BF)
    elseif r.b(0x77) == 2 then r.cat(0x48C1)
    elseif r.b(0x77) == 0 then r.cat(0x48C3) end
  else
    local c = r.byte(n - (r.ends(0x48C5, n) and 5 or 3))
    r.word(0x85, (c == 0xE7 or c == 0xE8 or c == 0xE9) and 2 or 0)
    r.adjective()
  end
end

-- 17AA:02E8: pronoun helper; preserve the hyphenated tail across inflection.
function generation.pronoun(m, s, o)
  local r = record(m, s, o)
  local ts, to = r.ptr(0x98)
  local hs, ho = m:strchr(ts, to, 0x2D)
  local tail
  if not null(hs, ho) then tail = m:cstring(hs, ho); m:set8(linear(hs, ho), 0) end
  local result_s, result_o
  if r.ends(0x48C8) then
    r.word(0x85, 6)
    result_s, result_o = generation.adjective_form(m, 6, ts, to, r.b(0x77), r.b(0x72), generation.case(r.b(0x76)))
    r.save(result_s, result_o)
  else
    result_s, result_o = generation.pronoun_form(m, ts, to, r.b(0x74), r.b(0x77), r.b(0x72), generation.case(r.b(0x76)), r.b(0x75))
  end
  if tail then
    if not null(result_s, result_o) then
      ts, to = r.ptr(0x98)
      m:write_string(ts, (to + m:strlen(ts, to)) & 0xFFFF, tail .. '\0')
    else m:set8(linear(hs, ho), 0x2D) end
  end
end

-- 17AA:0475: the tag switch. Return value is always 1, including no-op tags.
function generation.word(m, s, o)
  local r = record(m, s, o)
  local tag = r.b(0x0C)
  if tag == 0x4E then -- N
    if r.valid() and (r.b(0x72) ~= 0 or r.b(0x76) > 1) then
      local ts, to = r.ptr(0x98)
      r.save(generation.noun_form(m, r.w(0x85), ts, to, r.b(0x77), r.b(0x72), generation.case(r.b(0x76))))
    end
  elseif tag == 0x55 then -- U
    local n = r.length()
    if r.ends(0x48CE, n) then
      local aspect = 0
      if r.byte(0) ~= 0xE1 and r.b(0x75) == 1 then r.copy(0x48D3); aspect = 1 end
      r.verb(0x5D, aspect)
    elseif r.ends(0x48D9, n) then
      r.put(n - 2, 0)
      r.cat(r.b(0x72) ~= 0 and 0x48E0 or r.b(0x77) == 2 and 0x48E3 or r.b(0x77) == 1 and 0x48E6 or 0x48E9)
      if r.b(0x78) & 2 ~= 0 then r.cat(0x48EC) end
      if r.b(0x78) & 16 ~= 0 then r.cat(0x48F0) end
    end
  elseif tag == 0x58 or tag == 0x78 then -- X/x
    if tag == 0x78 and r.b(0x0F) == 0x6B then return 1 end
    local n = r.length()
    if r.byte(n - 1) == 0xAE then
      r.put(n - 2, 0)
      r.cat(r.b(0x72) ~= 0 and 0x48F4 or r.b(0x77) == 2 and 0x48F7 or r.b(0x77) == 1 and 0x48FA or 0x48FD)
      if r.b(0x78) & 2 ~= 0 then r.cat(0x4900) end
      if r.b(0x78) & 16 ~= 0 then r.cat(0x4904) end
    elseif r.b(0x78) & 8 == 0 then
      if r.ends(0x4908, 4) then r.word(0x85, 0x39)
      elseif r.ends(0x490D) then r.set(0x75, 0); r.word(0x85, 0)
      else return 1 end
      r.verb()
    end
  elseif tag == 0x59 then -- Y
    if r.ends(0x4914) then r.word(0x85, 0x28); r.verb() end
  elseif tag == 0x56 or tag == 0x76 then -- V/v
    local ps, po = r.ptr(0x62)
    if not null(ps, po) then
      local partner = record(m, ps, po)
      local ts, to = partner.ptr(0x98)
      local n = 0
      while true do
        local c = m:u8(linear(ts, (to + n) & 0xFFFF))
        if c == 0 then break end
        if m:u8(linear(m.ds, 0xBF77 + c)) & 0x0C ~= 0 then
          m:set8(linear(ts, (to + n) & 0xFFFF), 0); break
        end
        n = n + 1
      end
      if partner.ends(0x4919, 4) and partner.b(0x78) & 8 == 0 then
        local subject = r.b(0x78) & 8 ~= 0 and r.b(0x75) == 0 and partner or r
        partner.save(generation.verb_form(m, 0x39, ts, to, partner.b(0x75), subject.b(0x78), subject.b(0x74),
          subject.b(0x72), partner.b(0x73), subject.b(0x77)))
      end
    end
    if r.valid() then
      if r.b(0x7A) ~= 0 and r.b(0x7B) ~= 0 then r.set(0x75, 1); generation.participle(m, s, o)
      else
        if r.b(0x78) & 8 ~= 0 then r.set(0x74, 0) end
        r.verb()
      end
    end
  elseif tag == 0x47 then -- G
    if r.valid() then
      local ts, to = r.ptr(0x98)
      r.save(generation.participle_form(m, r.w(0x85), ts, to, r.b(0x75), 0x47, 0, 0))
    end
  elseif tag == 0x41 then -- A
    r.localize()
    if (r.b(0x7B) ~= 0 and r.b(0x66) == 0x41) or r.valid() then
      local original = r.b(0x66)
      if original == 0x45 or original == 0x56 or original == 0x46 or original == 0x65 or original == 0x47 then
        if original == 0x45 or original == 0x65 or original == 0x46 then
          r.set(0x7A, 1); if r.b(0x75) == 0 then r.set(0x73, 0) end
        end
        generation.participle(m, s, o); return 1
      elseif r.b(0x7B) ~= 0 then
        local n = r.length() - 2
        r.put(n, 0)
        if r.b(0x72) ~= 0 then
          if r.ends(0x491E, n) then r.put(n - 1, 0) end
          r.cat(0x4921)
        elseif r.b(0x77) == 2 then r.cat(0x4923)
        elseif r.b(0x77) == 0 then r.cat(0x4925)
        else
          if r.ends(0x4927, n) or r.ends(0x492A, n) then r.put(n - 1, 0); r.cat(0x492D) end
          if r.ends(0x4930, n) or r.ends(0x4933, n) or r.ends(0x4936, n) or r.ends(0x4939, n) then r.put(n - 1, 0); r.cat(0x493C) end
          if r.ends(0x493F, n) then r.put(n - 2, 0); r.cat(0x4942) end
          if r.ends(0x4945, n) then r.put(n - 1, 0) end
        end
        return 1
      else r.adjective() end
    end
    if r.b(0x0F) == 0x61 and (r.b(0x73) == 1 or r.b(0x73) == 2) then
      local saved = r.text()
      if r.b(0x73) == 2 then
        r.save(generation.adjective_form(m, 0, m.ds, 0x4948, r.b(0x77), r.b(0x72), generation.case(r.b(0x76))))
      else r.copy(0x494E) end
      r.cat(0x4954)
      local ts, to = r.ptr(0x98)
      m:write_string(ts, (to + r.length()) & 0xFFFF, saved .. '\0')
    end
  elseif tag == 0x4C or tag == 0x6C then -- L/l
    r.word(0x85, 0); r.adjective()
  elseif tag == 0x53 then -- S
    if r.ends(0x4956) then
      if r.b(0x77) == 2 then r.copy(0x495A)
      elseif r.b(0x77) == 0 then r.copy(0x495D) end
    end
  elseif tag == 0x49 or tag == 0x4F then -- I/O; native ordered suffix tests
    local id
    if r.byte(0) == 0xAB then id = 7
    else
      for _, ending in ipairs(NUMERAL_ENDINGS) do
        if r.ends(ending[1]) then id = ending[2]; break end
      end
    end
    if id then r.word(0x85, id); r.adjective() end
  elseif tag == 0x44 then -- D
    if r.b(0x66) == 0x41 and r.b(0x0F) == 0 then
      local n = r.length()
      r.put(n - 2, r.ends(0x49D4, (n - 2) & 0xFFFF) and 0xA8 or 0xAE)
      r.put(n - 1, 0)
    end
  elseif tag == 0x46 then -- F
    local text = m:cstring(m.ds, 0x4894) .. r.text()
    local ts, to = r.ptr(0x98); m:write_string(ts, to, text .. '\0')
    if r.valid() then
      r.set(0x0C, 0x45); r.set(0x73, 0); r.set(0x75, 0)
      if r.b(0x66) == 0x45 or r.b(0x66) == 0x65 then r.set(0x7A, 1) end
      generation.participle(m, s, o)
    end
  elseif tag == 0x45 then -- E
    if r.valid() then
      local n = r.length()
      if r.ends(0x49D7, n) then r.set(0x7A, 0) end
      if r.b(0x7B) ~= 0 and r.b(0x6D) & 8 ~= 0 then
        r.set(0x75, 0); r.set(0x78, 1); r.set(0x7A, 0); r.set(0x74, 3); r.set(0x73, 0); r.set(0x0C, 0x56)
        if not r.ends(0x49DA, n) then r.cat(0x49DD) end
        r.verb()
      else
        if r.b(0x75) == 0 then r.set(0x73, 0) end
        generation.participle(m, s, o)
      end
    end
  elseif tag == 0x4D or tag == 0x51 then -- M/Q
    if r.b(0x66) == 0x53 and r.ends(0x49E0) then
      if r.b(0x72) == 0 and r.b(0x76) & 8 == 0 then
        r.word(0x85, 12); r.put(2, 0); r.adjective()
      end
    else generation.pronoun(m, s, o) end
  end
  return 1
end

-- 17AA:1D31: skip the root boundary; optionally generate alternate readings.
function generation.run(m, s, o)
  while true do
    s, o = m:far(linear(s, o))
    if null(s, o) then break end
    local r = record(m, s, o)
    if r.b(0x0E) == 0x57 and r.b(0x0B) > 1 and r.b(0x0C) ~= 0x23 and r.b(0x0C) ~= 0x48 then
      generation.word(m, s, o)
      if m:u16(linear(m.ds, 0xBBB8)) ~= 0 and m:u16(linear(m.ds, 0xBBB6)) ~= 0 then
        local as, ao = s, o
        while true do
          as, ao = m:far(linear(as, ao) + 0x8F)
          if null(as, ao) then break end
          generation.word(m, as, ao)
        end
      end
    end
  end
  return 1
end

return generation
