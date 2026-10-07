-- LTPRO T8 (1986:000E, file 0x1D26E): agreement between constituents.
--
-- For every constituent position si from 1, each rule of the T8 table
-- (DS:49E4; 8-byte records: pattern far pointer, word, selector 1-70) is
-- matched with the constituent matcher (1C3D:0135) and its handler run;
-- then T7 (1449:0004) runs inside constituent si. Afterwards the
-- constituents' record lists are chained back into one list (1C3D:1A97).
--
-- The handlers keep three record pointers in their frame (natively at
-- BP-0A, BP-0E and BP-12) that persist from one handler to the next within
-- one T8 call; a few handlers read one without setting it first. They start
-- as null here (natively: stack contents left by earlier calls).
local memory = require 'core.ltpro.memory'
local constituents = require 'core.ltpro.constituents'
local seventh = require 'core.ltpro.seventh_pass'
local records = require 'core.ltpro.records'
local eighth = {}
local linear = memory.linear

local RULES = 0x49E4

local function context(m)
  local ds = m.ds
  local aseg, aoff = m:far(linear(ds, 0xC7FA))
  local c = {m = m, ds = ds, aseg = aseg, aoff = aoff}
  local function ref(seg, off)
    return {seg = seg, off = off, at = linear(seg, off), null = memory.null(seg, off)}
  end
  c.ref = ref
  c.NULL = ref(0, 0)
  function c.E(i) return linear(aseg, (aoff + i * 12) & 0xFFFF) end
  function c.e0(i) return m:u8(c.E(i)) end
  function c.e2(i) return m:u8(c.E(i) + 2) end
  function c.first(i) return ref(m:far(c.E(i) + 4)) end
  function c.last(i) return ref(m:far(c.E(i) + 8)) end
  function c.next(r) return ref(m:far(r.at)) end
  function c.aux(r) return ref(m:far(r.at + 0x62)) end
  function c.get(r, f) return m:u8(r.at + f) end
  function c.set(r, f, v) m:set8(r.at + f, v) end
  function c.copy(dst, src, f) m:set8(dst.at + f, m:u8(src.at + f)) end
  function c.word(r, f) return m:u16(r.at + f) end
  function c.find(r, test)
    while not r.null do
      if test(c.get(r, 0x0C)) then return r end
      r = c.next(r)
    end
    return r
  end
  function c.is(r, literal) return m:stricmp(r.seg, (r.off + 0x12) & 0xFFFF, ds, literal) == 0 end
  function c.strcpy_ds(r, field, literal) m:strcpy(r.seg, (r.off + field) & 0xFFFF, ds, literal) end
  function c.reading(r, literal)
    local s, o = m:far(r.at + 0x98)
    m:strcpy(s, o, ds, literal)
  end
  function c.b6D(r, n) return (c.get(r, 0x6D) >> n) & 1 end
  function c.t7(i)
    return seventh.run(m, aseg, (aoff + i * 12 + 4) & 0xFFFF, c.e0(i), i, aseg, aoff)
  end
  return c
end

local function is_tag(set) return function(t) return set:find(string.char(t), 1, true) ~= nil end end
-- The last record with tag 'V' (or `set`) in the list, else the list's last.
local function last_of(c, i, set)
  local r, found = c.first(i), c.last(i)
  while not r.null do
    if set:find(string.char(c.get(r, 0x0C)), 1, true) then found = r end
    r = c.next(r)
  end
  return found
end
-- Prepositional/negation prefix written to +243 of a record or its auxiliary.
local function prefix(c, r, with_aux, without_aux)
  local a = c.aux(r)
  if not a.null then c.strcpy_ds(a, 0x243, with_aux) else c.strcpy_ds(r, 0x243, without_aux) end
end
-- Case after a verb whose code bit 1 of +6D is set (shared by several rules).
local function verb_case(c, r)
  if c.b6D(r, 1) ~= 0 then
    if c.get(r, 0x72) == 0 and c.get(r, 0x77) == 2 then c.set(r, 0x76, 8)
    elseif c.word(r, 0x85) == 0x35 then c.set(r, 0x76, 8)
    else c.set(r, 0x76, 2) end
  else
    c.set(r, 0x76, 8)
  end
end

local H = {}

H[1] = function(c, F, si, hit)
  if c.e2(si) == 0x71 or c.e2(hit) == 0x71 then return end
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x0F) == 0x71 or c.get(F.r, 0x78) & 4 ~= 0 then return end
  if c.e2(si) ~= 0x6B then
    F.a = c.find(c.first(si), is_tag('NRS'))
    if not F.a.null and c.get(F.a, 0x0F) ~= 0x71 and not F.r.null and c.get(F.a, 0x66) ~= 0 and
       c.get(F.a, 0x76) == 0 then
      local a = c.aux(F.r)
      if not a.null then c.copy(a, F.a, 0x74); c.copy(a, F.a, 0x72); c.copy(a, F.a, 0x77) end
      c.copy(F.r, F.a, 0x77); c.copy(F.r, F.a, 0x74); c.copy(F.r, F.a, 0x72)
    end
  end
  if (not F.a.null and c.get(F.a, 0x0C) == 0x53 and c.get(F.a, 0x75) ~= 0) or
     c.e0(si) == 0x6B or c.e0(si - 1) == 0x6B then
    prefix(c, F.r, 0x4F66, 0x4F6A)
  end
end

H[2] = function(c, F, si, hit)
  if c.e2(si) == 0x71 then return end
  F.e = c.first(si)
  F.a = c.last(si)
  while not F.e.null do
    if c.get(F.e, 0x0C) == 0x56 then F.a = F.e end
    F.e = c.next(F.e)
  end
  if F.a.null or c.get(F.a, 0x7A) ~= 0 then return end
  if c.get(F.a, 0x68) & 0x3F ~= 0 and (c.get(F.a, 0x6E) >> 6) & 1 ~= 0 and
     (c.e0(hit + 1) == 0x51 or c.e0(hit + 1) == 0x4A) then
    F.e = c.find(c.first(hit), is_tag('N'))
    if not F.e.null then c.set(F.e, 0x76, 4) end
    return
  end
  local index = hit
  if c.e0(hit + 1) == 0x4E or c.e0(hit + 1) == 0x49 then
    F.e = c.find(c.first(hit), is_tag('N'))
    if not F.e.null then c.set(F.e, 0x76, 4) end
    index = hit + 1
  end
  F.r = c.find(c.first(index), is_tag('N'))
  if F.r.null then return end
  if c.get(F.a, 0x76) ~= 8 then c.copy(F.r, F.a, 0x76); return end
  verb_case(c, F.r)
end

H[3] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x0F) ~= 0 then return end
  local case = c.get(F.r, 0x76)
  if case ~= 8 and case ~= 0x20 then return end
  if not (c.is(F.r, 0x4F6E) or c.is(F.r, 0x4F71) or c.is(F.r, 0x4F74)) then return end
  F.a = c.first(si)
  F.e = c.last(si)
  while not F.a.null do
    local t = c.get(F.a, 0x0C)
    if t == 0x56 or t == 0x45 then F.e = F.a end
    F.a = c.next(F.a)
  end
  if F.e.null then return end
  c.set(F.r, 0x76, c.b6D(F.e, 6) ~= 0 and 0x20 or 8)
end

H[4] = function(c, F, si, hit)
  F.a = c.first(si)
  F.e = c.last(si)
  while not F.a.null do
    if c.get(F.a, 0x0C) == 0x56 then F.e = F.a end
    F.a = c.next(F.a)
  end
  F.r = c.first(hit)
  if F.r.null or F.e.null then return end
  c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77)
  if c.get(F.e, 0x7A) ~= 0 then return end
  c.copy(F.r, F.e, 0x76)
end

H[5] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x74) ~= 0 then return end
  c.t7(si)
  F.a = c.find(c.first(si), is_tag('N'))
  if not F.a.null then
    c.set(F.r, 0x0F, c.get(F.r, 0x76))
    c.copy(F.r, F.a, 0x76); c.copy(F.r, F.a, 0x72); c.copy(F.r, F.a, 0x77)
    c.set(F.r, 0x74, 3)
  end
  return 'skip'
end

H[6] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x72) end
end

H[7] = function(c, F, si, hit)
  F.a = c.find(c.first(si), is_tag('NS'))
  if F.a.null then return end
  F.r = c.first(hit)
  if F.r.null then return end
  c.copy(F.r, F.a, 0x72); c.copy(F.r, F.a, 0x77)
  c.set(F.r, 0x76, c.get(F.r, 0x0C) == 0x6C and 2 or 0)
end

H[8] = function(c, F, si, hit)
  F.e = c.first(si)
  F.a = F.e
  F.e = c.find(F.e, is_tag('V'))
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  local a = c.aux(F.r)
  if not a.null then
    c.copy(a, F.e, 0x74); c.copy(a, F.e, 0x72); c.copy(a, F.e, 0x77)
  else
    c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77)
  end
  c.copy(F.r, F.a, 0x72); c.copy(F.r, F.e, 0x78); c.copy(F.r, F.e, 0x7A); c.copy(F.r, F.e, 0x7B)
end

H[9] = function(c, F, si, hit)
  F.e = c.find(c.first(si), is_tag('V'))
  if F.e.null then return end
  F.r = c.NULL
  if c.e2(hit) ~= 0x6B then
    F.r = c.find(c.first(hit), is_tag('N'))
    if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x76) end
  end
  if (not F.r.null and c.get(F.r, 0x0C) == 0x53 and c.get(F.r, 0x75) ~= 0) or c.e0(hit) == 0x6B then
    prefix(c, F.e, 0x4F77, 0x4F7B)
  end
end

H[10] = function(c, F, si, hit)
  F.a = c.first(si)
  F.e = c.last(si)
  while not F.a.null do
    if c.get(F.a, 0x0C) == 0x56 then F.e = F.a end
    F.a = c.next(F.a)
  end
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  if c.get(F.r, 0x78) & 4 ~= 0 then return end
  if c.get(F.e, 0x66) == 0x45 and c.get(F.r, 0x66) ~= 0x45 then return end
  local a = c.aux(F.r)
  if not a.null then
    c.copy(a, F.e, 0x74); c.copy(a, F.e, 0x72); c.copy(a, F.e, 0x77)
  else
    c.copy(F.r, F.e, 0x78); c.copy(F.r, F.e, 0x7A); c.copy(F.r, F.e, 0x7B)
  end
  c.copy(F.r, F.e, 0x74); c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77)
end

H[11] = function(c, F, si, hit)
  F.a = c.first(si)
  F.r = c.first(hit)
  if not F.r.null and not F.a.null then
    c.copy(F.r, F.a, 0x72); c.copy(F.r, F.a, 0x77); c.set(F.r, 0x76, 0x10)
  end
end

H[12] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  if c.get(F.e, 0x75) ~= 0 then
    if c.get(F.e, 0x75) == 1 then prefix(c, F.r, 0x4F7F, 0x4F83)
    else c.strcpy_ds(F.r, 0x243, 0x4F87) end
  end
  if c.get(F.r, 0x7A) ~= 0 then c.set(F.r, 0x77, 0) end
end

H[13] = function(c, F, si, hit)
  F.a = c.first(si)
  F.r = c.first(hit)
  if not F.r.null and not F.a.null then
    c.copy(F.r, F.a, 0x72); c.copy(F.r, F.a, 0x77); c.set(F.r, 0x7B, 1)
  end
end

H[14] = function(c, F, si, hit)
  F.a = c.first(si)
  F.e = c.last(si)
  while not F.a.null and not F.e.null do
    local t = c.get(F.a, 0x0C)
    if t == 0x56 or t == 0x59 then F.e = F.a end
    F.a = c.next(F.a)
  end
  if not F.e.null and c.get(F.e, 0x7A) ~= 0 then return end
  F.r = c.first(hit)
  if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x76) end
end

H[15] = function(c, F, si, hit)
  F.e = c.first(si)
  if c.e2(hit) ~= 0x6B then
    F.r = c.find(c.first(hit), is_tag('N'))
    if not F.e.null and not F.r.null then
      c.set(F.r, 0x76, (c.b6D(F.r, 1) ~= 0 or c.e0(hit) == 0x6B) and 2 or 8)
    end
  end
  if c.e0(si - 1) == 0x58 then
    F.a = c.first(si - 1)
    if not F.a.null then c.strcpy_ds(F.a, 0x243, 0x4F8B) end
  elseif not F.e.null then
    c.strcpy_ds(F.e, 0x243, 0x4F8F)
  end
end

H[16] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.r.null then return end
  local a = c.aux(F.r)
  if not a.null then c.set(a, 0x74, 3); c.copy(a, F.e, 0x72); c.copy(a, F.e, 0x77) end
  c.set(F.r, 0x74, 3); c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x72)
  if c.get(F.r, 0x78) & 4 ~= 0 then c.set(F.r, 0x78, c.get(F.r, 0x78) & 0xFB) end
end

H[17] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if not F.e.null and (c.get(F.e, 0x73) ~= 0 or c.get(F.e, 0x74) == 0) then
    F.r = c.find(F.r, is_tag('N'))
    if not F.r.null then c.set(F.r, 0x76, 0x10) end
  end
  if c.e0(si + 1) == 0x6B then
    F.r = c.first(hit)
    if not F.r.null then c.strcpy_ds(F.r, 0x243, 0x4F93) end
  end
  if c.e0(si - 1) == 0x53 and not F.e.null and c.get(F.e, 0x73) == 0 then
    local s, o = c.m:far(F.e.at + 0x98)
    c.m:set8(linear(s, o), 0)
  end
end

H[18] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.find(c.first(hit), is_tag('A'))
  if not F.e.null and not F.r.null then
    if c.get(F.e, 0x74) == 0 then c.set(F.r, 0x76, 0x10); return end
    if c.get(F.e, 0x73) ~= 0 then c.set(F.r, 0x76, 0x10) end
    if c.get(F.e, 0x73) == 0 then
      local s, o = c.m:far(F.e.at + 0x98)
      c.m:set8(linear(s, o), 0)
    end
    c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x72)
    if c.get(F.r, 0x6D) & 1 ~= 0 and c.get(F.r, 0x76) ~= 0x10 and
       (c.e0(si - 1) == 0x4E or c.e0(si - 1) == 0x23 or c.e0(si - 1) == 0x52) then
      c.set(F.r, 0x7B, 1)
    end
  end
  if c.e0(si + 1) == 0x6B then
    F.r = c.first(hit)
    if not F.r.null then c.strcpy_ds(F.r, 0x243, 0x4F97) end
  end
end

H[19] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x0F) ~= 0 then return end
  if not (c.is(F.r, 0x4F9B) or c.is(F.r, 0x4F9E) or c.is(F.r, 0x4FA1)) then return end
  F.a = c.first(si)
  F.e = c.last(si)
  while not F.a.null do
    if c.get(F.a, 0x0C) == c.e0(si) then F.e = F.a end
    F.a = c.next(F.a)
  end
  if F.e.null or F.r.null then return end
  c.set(F.r, 0x76, c.b6D(F.e, 6) ~= 0 and 0x20 or 8)
end

H[21] = function(c, F, si, hit)
  F.a = c.first(si)
  F.e = c.last(si)
  while not F.a.null do
    if c.get(F.a, 0x0C) == 0x56 then F.e = F.a end
    F.a = c.next(F.a)
  end
  F.r = c.first(hit)
  if not F.e.null and not F.r.null then
    c.copy(F.r, F.e, 0x74); c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77)
  end
end

H[42] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  if c.get(F.e, 0x74) == 0 then c.set(F.r, 0x76, 0x10); return end
  if c.get(F.e, 0x73) ~= 0 then c.set(F.r, 0x76, 0x10) end
  c.copy(F.r, F.e, 0x77)
end

H[22] = function(c, F, si, hit)
  F.a = c.first(si)
  if c.e2(si) == 0x77 then F.a = c.find(F.a, is_tag('P')) end
  F.a = c.find(F.a, is_tag('N'))
  if F.a.null then return end
  F.r = c.first(hit)
  if F.r.null then return end
  c.copy(F.r, F.a, 0x72); c.copy(F.r, F.a, 0x77)
  c.set(F.r, 0x76, c.get(F.r, 0x0C) == 0x6C and 2 or 0)
end

H[23] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  c.copy(F.r, F.e, 0x74); c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x73)
end

H[24] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  c.copy(F.r, F.e, 0x74); c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77)
end

H[25] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x76) == 2 then return end
  if c.get(F.r, 0x0F) ~= 0 then return end
  if c.is(F.r, 0x4FA4) or c.is(F.r, 0x4FA7) or c.is(F.r, 0x4FAA) then c.set(F.r, 0x76, 0x20) end
end

H[26] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  if c.is(F.e, 0x4FAD) and c.get(F.e, 0x0F) == 0 then c.set(F.r, 0x76, 0x20)
  else c.copy(F.r, F.e, 0x76) end
  if c.get(F.r, 0x0F) == 0 then
    local s, o = c.m:far(F.r.at + 0x98)
    c.m:set8(linear(s, o), 0x20)
  end
end

H[27] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.find(c.first(hit), is_tag('N'))
  if F.e.null or F.r.null then return end
  local t = c.get(F.e, 0x0C)
  if t == 0x66 or (t == 0x79 and c.get(F.e, 0x75) ~= 0) then c.copy(F.r, F.e, 0x76)
  else c.copy(F.e, F.r, 0x77) end
  c.copy(F.e, F.r, 0x72)
end

H[28] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.find(c.first(hit), is_tag('N'))
  if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x76) end
end

H[29] = function(c, F, si, hit)
  F.a = c.first(si + 1)
  F.e = c.last(si + 1)
  while not F.a.null do
    if c.get(F.a, 0x0C) == 0x56 then F.e = F.a end
    F.a = c.next(F.a)
  end
  if c.get(F.e, 0x7A) == 0 then return end
  F.r = c.find(c.first(hit), is_tag('N'))
  if not F.e.null and not F.r.null then c.copy(F.e, F.r, 0x72); c.copy(F.e, F.r, 0x77) end
  F.a = c.first(si)
  if not F.a.null and c.get(F.r, 0x7A) ~= 0 then c.set(F.a, 0x76, 4) end
end

H[30] = function(c, F, si, hit)
  if c.e2(hit) == 0x71 then return end
  if c.e0(si) == 0x4F then F.e = c.find(c.first(si), is_tag('N')) else F.e = c.NULL end
  F.r = c.first(hit)
  if F.r.null then return end
  local number = c.e0(si) == 0x4F and 0 or 1
  local a = c.aux(F.r)
  if not a.null then
    c.set(a, 0x74, 3); c.set(a, 0x72, number)
    if not F.e.null then c.copy(F.r, F.e, 0x77) end
  end
  c.set(F.r, 0x74, 3); c.set(F.r, 0x72, number)
  if not F.e.null then c.copy(F.r, F.e, 0x77) end
  if c.get(F.r, 0x78) & 4 ~= 0 then c.set(F.r, 0x78, c.get(F.r, 0x78) & 0xFB) end
end

H[31] = function(c, F, si, hit)
  c.t7(si)
  F.r = c.first(hit)
  F.e = c.find(c.first(si), is_tag('N'))
  if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x76); c.set(F.r, 0x72, 1) end
  return 'skip'
end

H[32] = function(c, F, si, hit)
  F.a = c.first(si + 1)
  if not F.a.null then c.set(F.a, 0x76, 8) end
end

H[33] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null then return end
  c.set(F.r, 0x72, 1)
  c.set(F.r, 0x76, c.get(F.r, 0x0C) == 0x6C and 2 or 0)
end

H[34] = function(c, F, si, hit)
  F.a = c.find(c.first(si), is_tag('#'))
  if F.a.null then return end
  F.r = c.first(hit)
  if F.r.null then return end
  local a = c.aux(F.r)
  if not a.null then c.copy(a, F.a, 0x74); c.copy(a, F.a, 0x72); c.copy(a, F.a, 0x77) end
  c.copy(F.r, F.a, 0x77)
  if c.get(F.r, 0x74) ~= 0 then c.set(F.a, 0x72, 0) end
  c.copy(F.r, F.a, 0x72)
  c.set(F.r, 0x74, 3)
  if c.get(F.r, 0x78) & 4 ~= 0 then c.set(F.r, 0x78, c.get(F.r, 0x78) & 0xFB) end
end

H[35] = function(c, F, si, hit)
  c.m:set8(c.E(hit) + 2, 0x52)
end

H[36] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.find(c.first(hit), is_tag('A'))
  if F.e.null or F.r.null then return end
  c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x72)
  if c.get(F.r, 0x6D) & 1 ~= 0 then c.set(F.r, 0x7B, 1) else c.set(F.r, 0x76, 0x10) end
end

H[37] = function(c, F, si, hit)
  F.a = c.first(hit)
  if not F.a.null then c.set(F.a, 0x74, 3); c.set(F.a, 0x77, 1) end
end

H[39] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null then return end
  if c.get(F.r, 0x0C) == 0x59 then
    c.reading(F.r, 0x4FB0)
  else
    F.e = c.first(si)
    if not F.e.null then c.copy(F.r, F.e, 0x74); c.copy(F.r, F.e, 0x72) end
  end
end

H[43] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.find(c.first(hit), is_tag('A'))
  if F.e.null or F.r.null then return end
  c.set(F.r, 0x76, 0x10); c.copy(F.r, F.e, 0x72)
end

H[44] = function(c, F, si, hit)
  F.e = c.first(si)
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  c.copy(F.r, F.e, 0x74); c.copy(F.r, F.e, 0x72); c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x76)
end

H[45] = function(c, F, si, hit)
  F.r = c.find(c.first(hit), is_tag('N'))
  if not F.r.null then c.set(F.r, 0x76, 0x10) end
end

H[46] = function(c, F, si, hit)
  F.a = c.first(hit)
  if not F.a.null then
    local s, o = c.m:far(F.a.at + 0x98)
    c.m:set8(linear(s, o), 0)
  end
end

H[47] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x76) ~= 0 then return end
  F.e = c.first(si)
  if not F.e.null then c.copy(F.r, F.e, 0x76) end
end

H[48] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x76) ~= 0 then return end
  if c.e2(si) == 0x77 then c.set(F.r, 0x76, 2); return end
  F.e = c.find(c.first(si), is_tag('N'))
  if not F.e.null then c.copy(F.r, F.e, 0x76) end
end

H[49] = function(c, F, si, hit)
  F.a = c.find(c.first(si), is_tag('N'))
  if not F.a.null then c.set(F.a, 0x76, 4) end
end

-- Insert a constituent holding one new record (tag `tag`, text at DS:`text`)
-- at array position `at`. The element is built in T8's frame: bytes 1 and 3
-- are stack contents natively (not modeled; 0 here; never read).
local function insert_element(c, at, tag, class, text)
  local m = c.m
  local nseg, noff = records.new(m, 0, 0, ((text >> 8) << 8) | tag, c.ds, text)
  if memory.null(nseg, noff) then return c.NULL end
  m:set8(linear(nseg, noff) + 0x0B, 3)
  m:set_far(linear(nseg, noff), 0, 0)
  local bytes = string.char(tag, 0, class, 0) .. string.pack('<I2I2I2I2', noff, nseg, noff, nseg)
  local count_at = linear(c.ds, 0xC7FE)
  m:set16(count_at, constituents.insert(m, c.aseg, c.aoff, bytes, at, m:u16(count_at)))
  return c.ref(nseg, noff)
end

H[53] = function(c, F, si, hit)
  F.a = insert_element(c, hit - 2, 0x4C, 0x4B, 0x4FB8)
end

H[54] = function(c, F, si, hit)
  if c.e2(hit) == 0x52 or c.e0(hit + 1) == 0x2A then return end
  F.a = insert_element(c, hit, 0x4C, 0x4B, 0x4FC2)
end

H[55] = function(c, F, si, hit)
  F.e = c.first(si)
  if F.e.null then return end
  local tag, text = 0x4C, 0x4FD2
  if c.get(F.e, 0x68) & 0x3F == 1 and (c.get(F.e, 0x6E) >> 6) & 1 ~= 0 then tag, text = 0x4A, 0x4FCC end
  local nseg, noff = records.new(c.m, 0, 0, ((text >> 8) << 8) | tag, c.ds, text)
  F.a = c.ref(nseg, noff)
  c.set(F.e, 0x76, 4)
  if F.a.null then return end
  c.m:set8(F.a.at + 0x0B, 3)
  c.m:set_far(F.a.at, 0, 0)
  local bytes = string.char(tag, 0, 0x4B, 0) .. string.pack('<I2I2I2I2', noff, nseg, noff, nseg)
  local count_at = linear(c.ds, 0xC7FE)
  c.m:set16(count_at, constituents.insert(c.m, c.aseg, c.aoff, bytes, hit - 1, c.m:u16(count_at)))
end

H[56] = function(c, F, si, hit)
  F.e = c.find(c.first(si), is_tag('V'))
  if F.e.null or c.get(F.e, 0x68) & 0x3F == 0 then return end
  local text = 0x4FE2
  if c.get(F.e, 0x68) & 0x3F == 1 then
    text = 0x4FDC
  end
  local nseg, noff = records.new(c.m, 0, 0, ((text >> 8) << 8) | 0x4A, c.ds, text)
  F.a = c.ref(nseg, noff)
  if text == 0x4FE2 then
    F.r = c.first(hit)
    if not F.r.null then c.set(F.r, 0x73, 1) end
  end
  if F.a.null then return end
  c.m:set8(F.a.at + 0x0B, 3)
  c.m:set_far(F.a.at, 0, 0)
  local bytes = string.char(0x4A, 0, 0x4A, 0) .. string.pack('<I2I2I2I2', noff, nseg, noff, nseg)
  local count_at = linear(c.ds, 0xC7FE)
  c.m:set16(count_at, constituents.insert(c.m, c.aseg, c.aoff, bytes, hit - 1, c.m:u16(count_at)))
end

local function swap(c, i, j) constituents.swap(c.m, c.aseg, c.aoff, i, j) end
local function retag(c, i, t) c.m:set8(c.E(i), t); c.m:set8(linear(c.ds, (0xC7B6 + i) & 0xFFFF), t) end

H[59] = function(c, F, si, hit)
  F.a = c.first(hit - 1)
  if not F.a.null and c.get(F.a, 0x0F) == 0x72 then swap(c, si, si + 1) end
end

H[60] = function(c, F, si, hit)
  swap(c, si, si + c.m:s16(linear(c.ds, c.rule + 4)))
end

H[61] = function(c, F, si, hit)
  swap(c, si, hit)
  swap(c, si + 1, hit)
  F.e = c.first(si)
  F.r = c.first(si + 1)
  if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x76) end
  retag(c, si, 0x70)
end

H[62] = function(c, F, si, hit)
  if c.e0(si - 1) == 0x70 then return end
  F.e = c.find(c.first(si), is_tag('N'))
  F.r = c.first(hit)
  if F.e.null or F.r.null then return end
  local frame = c.get(F.r, 0x6A) & 0x3F
  if frame == 1 then c.set(F.e, 0x76, c.get(F.r, 0x79)); return end
  if frame == 2 and c.e0(hit + 1) == 0x50 then
    swap(c, si, hit + 1)
    swap(c, si + 1, hit + 1)
    retag(c, si, 0x70)
  end
end

H[63] = function(c, F, si, hit)
  F.a = insert_element(c, si, 0x2A, 0x4B, 0x4FEA)
  if not F.a.null then swap(c, si, hit) end
end

H[68] = function(c, F, si, hit)
  F.e = c.find(c.first(si), is_tag('N'))
  F.r = c.first(hit)
  if not F.e.null and not F.r.null then c.copy(F.r, F.e, 0x77); c.copy(F.r, F.e, 0x72) end
end

H[69] = function(c, F, si, hit)
  F.r = c.first(hit)
  if not F.r.null then c.set(F.r, 0x74, 3); c.set(F.r, 0x72, 1) end
end

H[70] = function(c, F, si, hit)
  F.r = c.first(hit)
  if F.r.null or c.get(F.r, 0x78) ~= 0 or c.get(F.r, 0x7A) ~= 0 then return end
  F.a = c.find(c.first(si), is_tag('N'))
  if F.a.null then return end
  F.r = c.last(hit)
  if not F.r.null then c.copy(F.a, F.r, 0x76) end
end

-- 1986:000E. `root` is the record list head; `terminator` the driver's SI.
function eighth.run(m, root_seg, root_off, terminator)
  local c = context(m)
  local F = {a = c.NULL, e = c.NULL, r = c.NULL}
  c.terminator = terminator
  c.root_seg, c.root_off = root_seg, root_off
  local count_at = linear(c.ds, 0xC7FE)
  local si = 1
  while m:s16(count_at) - 1 > si do
    local rule = RULES
    local skipped = false
    while not memory.null(m:far(linear(c.ds, rule))) do
      local pseg, poff = m:far(linear(c.ds, rule))
      local hit = constituents.match(m, c.aseg, c.aoff, si, pseg, poff)
      if hit ~= 0 then
        c.rule = rule
        local handler = H[m:u16(linear(c.ds, rule + 6))]
        if handler and handler(c, F, si, hit) == 'skip' then skipped = true; break end
      end
      rule = rule + 8
    end
    if not skipped then c.t7(si) end
    si = si + 1
  end
  constituents.relink(m, root_seg, root_off, c.aseg, c.aoff, m:u16(count_at))
end

return eighth
