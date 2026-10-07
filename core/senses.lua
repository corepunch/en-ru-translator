local memory = require 'core.memory'
local heap = require 'core.heap'
local russian = require 'core.russian'

local senses = {}

-- LTPRO 151F: choosing a word's Russian reading and its grammatical state
-- after reordering (driver stage 151F:2740 and the routines it calls).
--
-- Records are addressed as far pointers (segment, offset) into the memory
-- model; field offsets are those of the native 282h-byte lexical record.
-- +98 is a far pointer to the record's current reading text (normally inside
-- its own +11C buffer), advanced and split in place as readings are parsed.
local linear = memory.linear

local function digit(c) return (memory.ctype(c) & 2) ~= 0 end
local function alpha(c) return (memory.ctype(c) & 0x0C) ~= 0 end

-- 151F:0B6B: skip an alternative's numbering prefix. The text after +98's
-- first byte is scanned for up to five Cyrillic letters, digits or ')';
-- each ')' found moves +98 past it and restarts the count. Returns the
-- pointer to the text after the first byte (moved past any skipped prefix).
function senses.skip_prefix(m, rseg, roff)
  local rec = linear(rseg, roff)
  local seg, off = m:far(rec + 0x98)
  off = (off + 1) & 0xFFFF
  local i = 0
  while i < 5 do
    local c = m:u8(linear(seg, (off + i) & 0xFFFF))
    if c == 0 then break end
    if not (memory.is_cyrillic(c) or (memory.ctype(c) & 2) ~= 0 or c == 0x29) then break end
    if c == 0x29 then
      off = (off + i + 1) & 0xFFFF
      m:set_far(rec + 0x98, seg, off)
      i = 0
    else
      i = i + 1
    end
  end
  return seg, off
end

-- 151F:028B: parse the grammatical code that follows a reading's tag in the
-- text at (seg, off) into the record's fields, according to the record's
-- tag. Returns the text position after the code.
local CASE_LETTERS = {[0x82] = 8, [0x84] = 4, [0x88] = 0, [0x8F] = 0x20, [0x90] = 2, [0x92] = 0x10}
function senses.parse_code(m, seg, off, rseg, roff)
  local r = linear(rseg, roff)
  local function c() return m:u8(linear(seg, off)) end
  local function take(field)
    if digit(c()) then m:set8(r + field, c() - 0x30); off = (off + 1) & 0xFFFF; return true end
    return false
  end
  local tag = m:u8(r + 0x0C)
  if tag == 0x49 then take(0x72)
  elseif tag == 0x4A then
    take(0x73)
    if digit(c()) then m:set8(r + 0x0F, 0x6B); off = (off + 1) & 0xFFFF end
  elseif tag == 0x78 then take(0x73)
  elseif tag == 0x79 then take(0x75); m:set8(r + 0x76, 2)
  elseif tag == 0x44 or tag == 0x4F or tag == 0x50 or tag == 0x51 or tag == 0x70 then
    -- Case letters (CP866 В Д И П Р Т) may repeat; the last one wins.
    while CASE_LETTERS[c()] do
      m:set8(r + 0x76, CASE_LETTERS[c()])
      off = (off + 1) & 0xFFFF
    end
    take(0x72)
    take(0x75)
  elseif tag == 0x4D or tag == 0x52 or tag == 0x53 or tag == 0x72 then
    take(0x72)
    take(0x74)
    take(0x77)
    if tag == 0x4D and m:u8(r + 0x76) == 0 then m:set8(r + 0x76, 2) end
    if tag == 0x53 then m:set8(r + 0x74, 3) end
  elseif tag == 0x6E then
    m:set8(r + 0x72, 1)
    m:set8(r + 0x0C, 0x4E)
  else
    if digit(c()) then off = (off + 1) & 0xFFFF end
    if digit(c()) then off = (off + 1) & 0xFFFF end
  end
  return seg, off
end

-- 151F:000F: copy a dictionary entry's paradigm code bytes from (seg, off)
-- to +67 (`first` = 1) or +6D, and derive number, gender, case and form
-- fields from them by the record's tag.
function senses.store_code(m, first, seg, off, rseg, roff)
  local r = linear(rseg, roff)
  local function p(i) return m:u8(linear(seg, (off + i) & 0xFFFF)) end
  if p(0) == 0 then return end
  local full = first ~= 1
  local dest = r + (first == 1 and 0x67 or 0x6D)
  local tag = m:u8(r + 0x0C)
  if tag == 0x4E then
    m:set8(dest, p(0)); m:set8(dest + 1, p(1))
    if full then
      m:set8(dest + 2, p(2))
      if p(2) ~= 0 then m:set16(r + 0x85, m:u8(dest + 2) & 0x7F) end
      if (m:u8(dest + 1) >> 3) & 1 ~= 0 then m:set8(r + 0x72, 1) end
      if (m:u8(dest + 1) >> 2) & 1 ~= 0 then m:set8(r + 0x72, 0) end
    end
    local b = m:u8(dest + 1)
    m:set8(r + 0x77, ((b >> 1) & 1) * 2 + (b & 1))
  elseif tag == 0x41 then
    m:set8(dest, p(0))
    if full then
      if m:u8(dest) & 1 ~= 0 then m:set8(dest + 1, p(1)); m:set8(dest + 2, p(2))
      else m:set8(dest + 2, p(1)) end
      if (m:u8(dest) >> 5) & 1 ~= 0 then m:set8(r + 0x7B, 1) end
      m:set16(r + 0x85, m:u8(dest + 2) & 0x7F)
    else
      m:set8(dest + 1, p(1))
    end
  elseif tag == 0x45 or tag == 0x46 or tag == 0x47 or tag == 0x56 or tag == 0x65 or tag == 0x76 then
    m:set8(dest, p(0)); m:set8(dest + 1, p(1))
    if full then
      m:set8(dest + 2, p(2)); m:set8(dest + 3, p(3))
      local case = m:u8(r + 0x76)
      if case == 0 or case == 8 then m:set8(r + 0x76, m:u8(dest + 1) & 0x3F) end
      if m:u8(r + 0x6A) & 0x3F == 0 then
        local v = m:u8(r + 0x79)
        if v == 0 or v == 8 then m:set8(r + 0x79, m:u8(dest + 3) & 0x3F) end
      end
      m:set16(r + 0x85, m:u8(dest + 2) & 0x7F)
    elseif m:u8(r + 0x0C) == 0x45 or m:u8(r + 0x66) == 0x45 then
      m:set8(r + 0x73, 1)
    end
  end
end

-- 151F:09A3: reflexive verbs. With the text length in DS:C7B4: a text
-- ending in "ся" gets +85 = 2 after ч/ш/щ (else 0) and returns 0; a stem
-- ending in ч, чей, ш, шо, щ sets +85 and +0B = 3 and returns 0; otherwise
-- the last two letters are saved at the far pointer DS:4840, replaced by
-- "*A" (a lookup key for the adjective form), and 1 is returned.
function senses.reflexive(m, rseg, roff)
  local r = linear(rseg, roff)
  local ds = m.ds
  m:set8(r + 0x77, 1)
  local seg, off = m:far(r + 0x98)
  local length = m:u16(linear(ds, 0xC7B4))
  local function at(back) return m:u8(linear(seg, (off + length - back) & 0xFFFF)) end
  if memory.ends_with(m, seg, off, length, ds, 0x484A) ~= 0 then
    local c = at(5)
    m:set16(r + 0x85, (c == 0xE7 or c == 0xE8 or c == 0xE9) and 2 or 0)
    return 0
  end
  local c3, matched = at(3), true
  if c3 == 0xE7 then
    m:set16(r + 0x85, (at(2) == 0xA5 and at(1) == 0xA9) and 0x18 or 2)
  elseif c3 == 0xE8 then
    m:set16(r + 0x85, at(2) == 0xAE and 6 or 2)
  elseif c3 == 0xE9 then
    m:set16(r + 0x85, 2)
  else
    matched = false
  end
  if matched then m:set8(r + 0x0B, 3); return 0 end
  local sseg, soff = m:far(linear(ds, 0x4840))
  m:set8(linear(sseg, soff), at(2))
  m:set8(linear(sseg, (soff + 1) & 0xFFFF), at(1))
  m:set8(linear(seg, (off + length - 2) & 0xFFFF), 0x2A)
  m:set8(linear(seg, (off + length - 1) & 0xFFFF), 0x41)
  return 1
end

-- 151F:1F6F: a copy of the record (its first 26Bh bytes) for an alternative
-- reading with text `text`: unlinked, its alternative fields cleared, the
-- text in its own +11C. Returns (0, 0) when allocation fails.
function senses.clone(m, rseg, roff, tseg, toff)
  local seg, off = heap.calloc(m, 1, heap.RECORD_SIZE)
  if memory.null(seg, off) then return seg, off end
  local n = linear(seg, off)
  m:copy(n, linear(rseg, roff), heap.RECORD_SIZE)
  m:set8(n + 0x89, 0)
  m:set_far(n + 0x8B, 0, 0)
  m:set_far(n + 0x8F, 0, 0)
  m:set_far(n + 0x98, seg, (off + 0x11C) & 0xFFFF)
  m:set_far(n, 0, 0)
  m:strcpy(seg, (off + 0x11C) & 0xFFFF, tseg, toff)
  senses.skip_prefix(m, seg, off)
  return seg, off
end

-- 151F:056E: expand a multi-word entry. The reading (after an optional 'W')
-- is a sequence of tagged components, e.g. "WAаналого-цифровойNпреобразователь";
-- the first component stays in the record (its tag and code parsed here),
-- each later one becomes a new record linked after it, tagged by the letter
-- that ends the previous component (a space starts a 'w' component). Text
-- after the first '/' is cut off and {...} annotations are skipped.
-- Returns the record's original tag, or 0 when the record limit is hit.
function senses.expand_phrase(m, rseg, roff)
  local r = linear(rseg, roff)
  local seg, off = m:far(r + 0x98)
  local function c(o) return m:u8(linear(seg, (o or off) & 0xFFFF)) end
  local function set(v, o) m:set8(linear(seg, (o or off) & 0xFFFF), v) end
  local function step() off = (off + 1) & 0xFFFF end
  if c() == 0x57 then step() end
  if alpha(c()) or c() == 0x23 then
    if c() == 0x6E then m:set8(r + 0x72, 1); set(0x4E) end
    local t = c()
    if t ~= 0x47 and t ~= 0x56 and t ~= 0x45 then m:set8(r + 0x66, t); m:set8(r + 0x0C, t) end
    if c() == 0x23 then
      step()
      if digit(c()) then
        if m:u8(r + 0x72) == 0 then m:set8(r + 0x72, c() - 0x30) end
        step()
      end
      if digit(c()) then m:set8(r + 0x77, c() - 0x30); step()
      elseif c() == 0xAC then m:set8(r + 0x77, 1); step()
      elseif c() == 0xA6 then m:set8(r + 0x77, 2); step()
      elseif c() == 0x63 then m:set8(r + 0x77, 0); step() end
      m:set8(r + 0x74, 3)
    else
      step()
    end
  end
  m:set_far(r + 0x98, seg, off)
  local q = off
  while c(q) ~= 0 and c(q) ~= 0x2F do q = (q + 1) & 0xFFFF end
  set(0, q)
  m:set8(r + 0x0F, 0x77)
  local tag = m:u8(r + 0x0C)
  -- Find the end of the current component and the tag of the next one.
  local function component(current)
    local high = 0
    if current == 0x23 then
      while c() ~= 0 and c() ~= 0x23 do step() end
      if c() ~= 0 then set(0); step() end
    else
      while c() ~= 0 do
        local b = c()
        if alpha(b) or b == 0x20 or b == 0x23 then break end
        if b == 0x7B then
          while c() ~= 0 and c() ~= 0x7D do step() end
        end
        step()
      end
    end
    local following = 0
    if c() ~= 0 then
      following = c() == 0x20 and 0x77 or c()
      set(0)
    end
    return following, high
  end
  local following = component(tag)
  local current = following
  local rec_seg, rec_off = rseg, roff
  while current ~= 0 do
    step()
    local text = off
    local high
    following, high = component(current)
    local nseg, noff = heap.new_record(m, 0, 0, (high << 8) | current, seg, text)
    local last = linear(rec_seg, rec_off)
    if memory.null(nseg, noff) then
      set(following)
      m:set8(last + 0x0B, 0xFF)
      return 0
    end
    local n = linear(nseg, noff)
    m:set8(n + 0x0B, 3)
    m:set8(n + 0x0F, 0x77)
    if current == 0x56 then
      if tag == 0x47 or tag == 0x45 then m:set8(n + 0x0C, tag)
      elseif m:u8(last + 0x74) == 3 then m:set8(n + 0x74, 3) end
    end
    if current == 0x4E and m:u8(last + 0x72) ~= 0 then m:set8(n + 0x72, 1) end
    m:set8(n + 0x66, current == 0x6E and 0x4E or current)
    local pseg, poff = m:far(n + 0x98)
    m:set_far(n + 0x98, senses.parse_code(m, pseg, poff, nseg, noff))
    m:set_far(n, m:far(last))
    m:set_far(last, nseg, noff)
    rec_seg, rec_off = nseg, noff
    current = following
  end
  return tag
end

local function profile_gated(m, name)
  error(name .. ' is reachable only with a profile flag (DS:BB9E/BBA0) that the frozen profile clears')
end

-- 151F:0C03: choose the record's reading and derive its grammatical state.
-- `alt` is nonzero for an alternative reading, `wtag`/`wflag` request the
-- multi-word expansion. The tag is kept in the global byte DS:484D. Russian
-- base forms are looked up in BASE.RUS ("\nword*" lines) and their paradigm
-- codes stored by 151F:000F. Returns 1 when a reading was established.
function senses.select(m, r0seg, r0off, rseg, roff, alt, wtag, wflag)
  local ds = m.ds
  local T = linear(ds, 0x484D)
  local C7B4 = linear(ds, 0xC7B4)
  local r = linear(rseg, roff)
  local result, bar = 1, 0
  local pseg, poff, lseg, loff, t, c, d, xs, xo
  local function r98() return m:far(r + 0x98) end
  local function r98byte(i) local s0, o0 = r98(); return m:u8(linear(s0, (o0 + (i or 0)) & 0xFFFF)) end
  local function r98set(i, v) local s0, o0 = r98(); m:set8(linear(s0, (o0 + i) & 0xFFFF), v) end
  local function r98inc() local s0, o0 = r98(); m:set_far(r + 0x98, s0, (o0 + 1) & 0xFFFF) end
  local function length() return m:u16(C7B4) end
  local function set_length() local s0, o0 = r98(); m:set16(C7B4, m:strlen(s0, o0)) end
  local function lookup(prefix) local s0, o0 = r98(); return russian.lookup(m, ds, 0xC8B4, s0, o0, prefix) end
  local function ends(at) local s0, o0 = r98(); return memory.ends_with(m, s0, o0, length(), ds, at) ~= 0 end
  local function strcat_r98(at) local s0, o0 = r98(); m:strcat(s0, o0, ds, at) end
  local function bit6D(n) return (m:u8(r + 0x6D) >> n) & 1 end
  local function same_record() return r0seg == rseg and r0off == roff end
  local function release_aux()
    -- free(aux->94) when set, then free(aux); aux = +62.
    local aseg, aoff = m:far(r + 0x62)
    local a = linear(aseg, aoff)
    if not memory.null(m:far(a + 0x94)) then heap.free(m, m:far(a + 0x94)) end
    heap.free(m, aseg, aoff)
    m:set_far(r + 0x62, 0, 0)
  end
  local function aux_set() return not memory.null(m:far(r + 0x62)) end
  local function copy_from(sseg, soff)
    m:strcpy(rseg, (roff + 0x11C) & 0xFFFF, sseg, soff)
    m:set_far(r + 0x98, rseg, (roff + 0x11C) & 0xFFFF)
  end

  m:set8(T, m:u8(r + 0x0C))
  pseg, poff = senses.skip_prefix(m, rseg, roff)
  if r98byte(0) == 0x57 or wtag == 0x57 or wflag ~= 0 then
    t = senses.expand_phrase(m, rseg, roff)
    m:set8(T, t & 0xFF)
    if t & 0xFF == 0 then return 0 end
  end
  if m:u16(linear(ds, 0xBBB8)) == 0 and not same_record() then return 1 end
  if m:u8(T) == 0x4E and m:u8(r + 0x66) == 0x41 and (m:u8(r + 0x0F) == 0x77 or m:u8(r + 0x0F) == 0x57) then
    m:set8(T, 0x41); m:set8(r + 0x0C, 0x41); m:set8(r + 0x76, 0)
  end
  t = m:u8(T)
  if t == 0x41 or t == 0x45 or t == 0x46 or t == 0x47 or t == 0x56 or t == 0x65 or t == 0x76 then
    c = m:u8(r + 0x66)
    if t == 0x41 and not (c == 0x45 or c == 0x65 or c == 0x56 or c == 0x47) then goto adjective end
    if t ~= 0x41 or alt ~= 0 then goto verb end
    ::adjective::
    set_length()
    c = m:u8(r + 0x66)
    if c == 0x23 or c == 0x3F or c == 0x48 then
      m:set8(r + 0x0B, 1); result = 0
    elseif c == 0x49 or m:s16(C7B4) < 3 then
      result = 0
    else
      if alt == 0 then m:set8(r + 0x66, 0x41) end
      result = senses.reflexive(m, rseg, roff)
    end
    goto established
    ::verb::
    xs, xo = r98()
    lseg, loff = m:strchr(xs, xo, 0x7C)
    goto verb_body
  elseif t == 0x4E then
    goto noun
  elseif t == 0x44 then
    if m:u8(r + 0x66) == 0x50 then xs, xo = r98(); m:set_far(r + 0x98, senses.parse_code(m, xs, xo, rseg, roff)) end
    if alt == 0 then m:set8(r + 0x66, 0x44) end
    goto none
  elseif t == 0x64 then
    m:set8(r + 0x0C, 0x44); goto none
  elseif t == 0x6E or t == 0x23 then
    if t == 0x23 then m:set8(T, 0x4E) end
    m:set8(r + 0x0C, 0x4E); goto established
  elseif t == 0x4C then
    m:set8(r + 0x74, 3); m:set8(r + 0x77, 1); goto none
  elseif t == 0x4A then
    if m:u8(r + 0x66) == 0x50 and memory.is_upper_cyrillic(r98byte(0)) then m:set8(r + 0x0C, 0x50) end
    goto code
  elseif t == 0x49 or t == 0x4D or t == 0x4F or t == 0x50 or t == 0x51 or t == 0x52 or t == 0x53 or
         t == 0x70 or t == 0x72 or t == 0x78 or t == 0x79 then
    goto code
  else
    goto none
  end

  ::code::
  xs, xo = r98()
  m:set_far(r + 0x98, senses.parse_code(m, xs, xo, rseg, roff))
  ::none::
  result = 0
  ::established::
  if result == 0 then return 0 end
  -- A Russian lower-case word (or one-letter word): look its form up with
  -- the tag appended ("word*T") unless it is an adjective.
  if r98byte(0) == 0 or not memory.is_lower_cyrillic(r98byte(0)) then return 0 end
  c = r98byte(1)
  if not memory.is_lower_cyrillic(c) and not (c == 0 or c == 0x20 or c == 0x2E or c == 0x2D or c == 0x2A) then return 0 end
  if m:u8(T) ~= 0x41 then
    set_length()
    r98set(length(), 0x2A)
    r98set(length() + 1, m:u8(T))
    r98set(length() + 2, 0)
  end
  lseg, loff = lookup(1)
  if memory.null(lseg, loff) then goto not_found end
  pseg, poff = m:strchr(lseg, loff, 0x2A)
  if memory.null(pseg, poff) then return 0 end
  poff = (poff + 1) & 0xFFFF
  m:set8(r + 0x6C, m:u8(linear(pseg, poff)))
  poff = (poff + 1) & 0xFFFF
  senses.store_code(m, 0, pseg, poff, rseg, roff)
  if m:u8(r + 0x0C) == 0x41 then
    local sseg, soff = m:far(linear(ds, 0x4840))
    r98set(length() - 2, m:u8(linear(sseg, soff)))
    r98set(length() - 1, m:u8(linear(sseg, (soff + 1) & 0xFFFF)))
    m:set8(r + 0x77, 1)
  end
  r98set(length(), 0)
  m:set8(r + 0x0B, 4)
  do return 1 end

  ::not_found::
  t = m:u8(T)
  if t == 0x41 then
    local sseg, soff = m:far(linear(ds, 0x4840))
    r98set(length() - 2, m:u8(linear(sseg, soff)))
    r98set(length() - 1, m:u8(linear(sseg, (soff + 1) & 0xFFFF)))
    m:set8(r + 0x77, 1)
    if ends(0x486B) or ends(0x486F) or ends(0x4873) or ends(0x4877) then
      m:set16(r + 0x85, 4)
    elseif ends(0x487B) or ends(0x487E) or ends(0x4881) or ends(0x4884) then
      m:set16(r + 0x85, r98byte(length() - 3) == 0xE6 and 1 or 0)
    end
    m:set8(r + 0x74, 3)
  elseif t == 0x4E then
    r98set(length(), 0)
    m:set8(r + 0x77, 1)
    if m:u16(linear(ds, 0xBBA0)) ~= 0 and m:s16(C7B4) > 4 then profile_gated(m, '1E71:0015') end
    m:set8(r + 0x74, 3)
  end
  r98set(length(), 0)
  if m:u16(linear(ds, 0xBB9E)) ~= 0 then profile_gated(m, '043A:2307') end
  do return 0 end

  ::noun::
  m:set8(r + 0x0C, 0x4E)
  c = m:u8(r + 0x66)
  if c == 0x23 or c == 0x3F then
    -- Gender of a number word from the text after the reading's prefix.
    c = m:u8(linear(pseg, poff))
    if digit(c) then m:set8(r + 0x77, c - 0x30); poff = (poff + 1) & 0xFFFF
    elseif c == 0xAC then m:set8(r + 0x77, 1); poff = (poff + 1) & 0xFFFF
    elseif c == 0xA6 then m:set8(r + 0x77, 2); poff = (poff + 1) & 0xFFFF
    elseif c == 0xE1 then m:set8(r + 0x77, 0); poff = (poff + 1) & 0xFFFF end
    m:set8(r + 0x0B, 1)
    return 1
  end
  if digit(r98byte(0)) then
    m:set8(r + 0x75, r98byte(0) - 0x30)
    r98inc()
  elseif m:u8(r + 0x66) == 0x4E or alt == 0 then
    -- nothing
  else
    if wtag ~= 0 and wtag ~= 0x56 then
      xs, xo = r98()
      lseg, loff = m:strchr(xs, xo, 0x56)
      if not memory.null(lseg, loff) then
        loff = (loff + 1) & 0xFFFF
        m:set_far(r + 0x98, lseg, loff)
      else
        lseg, loff = r98()
      end
      while m:u8(linear(lseg, loff)) ~= 0 and memory.ctype(m:u8(linear(lseg, loff))) & 4 == 0 do
        loff = (loff + 1) & 0xFFFF
      end
      m:set8(linear(lseg, loff), 0)
    end
    xs, xo = r98()
    if not memory.null(russian.replace_ending(m, xs, xo, rseg, (roff + 0x11C) & 0xFFFF)) then
      m:set_far(r + 0x98, rseg, (roff + 0x11C) & 0xFFFF)
    end
  end
  m:set8(r + 0x76, 0)
  m:set8(r + 0x74, 3)
  goto established

  ::verb_body::
  -- An alternative after '|' is used when +75 (aspect) is 1.
  if m:u8(r + 0x75) == 1 and not memory.null(lseg, loff) then
    m:set8(linear(lseg, loff), 0)
    loff = (loff + 1) & 0xFFFF
    m:set_far(r + 0x98, lseg, loff)
    bar = 0
  else
    if not memory.null(lseg, loff) then m:set8(linear(lseg, loff), 0) end
    bar = 1
  end
  if m:u8(r + 0x0C) ~= 0x45 then m:set8(r + 0x77, 1) end
  if m:u8(r + 0x66) == 0x5A then m:set8(r + 0x72, 0) end
  if digit(r98byte(0)) then
    d = (r98byte(0) - 0x30) & 0x3F
    r98inc()
    m:set8(r + 0x68, (m:u8(r + 0x68) & 0xC0) | d)
    m:set8(r + 0x68, (m:u8(r + 0x68) & 0xBF) | ((d & 1) << 6))
  end
  if digit(r98byte(0)) then
    d = (r98byte(0) - 0x30) & 1
    r98inc()
    m:set8(r + 0x6A, (m:u8(r + 0x6A) & 0xBF) | (d << 6))
  end
  if digit(r98byte(0)) then
    d = (r98byte(0) - 0x30) & 0x3F
    r98inc()
    m:set8(r + 0x6A, (m:u8(r + 0x6A) & 0xC0) | d)
  end
  if r98byte(0) == 0 or not memory.is_lower_cyrillic(r98byte(0)) then return 0 end
  c = r98byte(1)
  if not memory.is_lower_cyrillic(c) and not (c == 0 or c == 0x20 or c == 0x2E or c == 0x2D) then return 0 end
  lseg, loff = lookup(0)
  set_length()
  if memory.null(lseg, loff) and ends(0x4850) then
    r98set(length() - 2, 0)
    lseg, loff = lookup(0)
    strcat_r98(0x4853)
  end
  if memory.null(lseg, loff) then
    if m:u16(linear(ds, 0xBB9E)) ~= 0 then profile_gated(m, '043A:2307') end
    if m:u16(linear(ds, 0xBBA0)) ~= 0 then profile_gated(m, '1E71:0015') end
    return 0
  end
  pseg, poff = m:strchr(lseg, loff, 0x2A)
  if memory.null(pseg, poff) then return 0 end
  poff = (poff + 1) & 0xFFFF
  senses.store_code(m, 0, pseg, (poff + 1) & 0xFFFF, rseg, roff)
  if m:u8(r + 0x75) == 1 and bar ~= 0 and m:u8(linear(pseg, poff)) == 0x56 and
     m:u8(linear(pseg, (poff + 1) & 0xFFFF)) ~= 0 and m:u8(linear(pseg, (poff + 5) & 0xFFFF)) ~= 0 and
     bit6D(3) == 0 and bit6D(1) == 0 then
    -- The perfective partner named after the code ("V....partner").
    copy_from(pseg, (poff + 5) & 0xFFFF)
    if memory.is_lower_cyrillic(r98byte(0)) and memory.is_lower_cyrillic(r98byte(1)) then
      lseg, loff = lookup(0)
      set_length()
      if memory.null(lseg, loff) and ends(0x4856) then
        r98set(length() - 2, 0)
        lseg, loff = lookup(0)
        strcat_r98(0x4859)
      end
      if not memory.null(lseg, loff) then
        -- No null check natively: a missing '*' yields 0000:0001.
        pseg, poff = m:strchr(lseg, loff, 0x2A)
        poff = (poff + 1) & 0xFFFF
      end
    end
  end
  m:set8(r + 0x6C, m:u8(linear(pseg, poff)))
  poff = (poff + 1) & 0xFFFF
  senses.store_code(m, 0, pseg, poff, rseg, roff)
  if bit6D(2) ~= 0 and bit6D(3) == 0 then m:set8(r + 0x75, 1) end
  if bit6D(3) ~= 0 and bit6D(2) == 0 then m:set8(r + 0x75, 0) end
  if ends(0x485C) then
    m:set8(r + 0x76, m:u8(r + 0x79))
  elseif bit6D(4) ~= 0 then
    strcat_r98(0x485F)
    m:set8(r + 0x76, m:u8(r + 0x79))
  elseif m:u8(r + 0x78) & 1 == 0 then
    -- nothing
  elseif bit6D(5) == 0 then
    strcat_r98(0x4862)
    m:set8(r + 0x76, m:u8(r + 0x79))
  else
    m:set8(r + 0x78, m:u8(r + 0x78) & 0xFE)
    m:set8(r + 0x7A, (m:u8(r + 0x0C) == 0x56 and m:u8(r + 0x73) == 1) and 0 or 1)
    m:set8(r + 0x7B, 1)
    m:set8(r + 0x73, 1)
    if m:u8(linear(pseg, (poff + 4) & 0xFFFF)) ~= 0 and m:u8(r + 0x75) == 0 and bit6D(3) == 0 and bit6D(1) == 0 then
      copy_from(pseg, (poff + 4) & 0xFFFF)
    end
    m:set8(r + 0x75, 1)
  end
  if m:u8(r + 0x73) == 2 and aux_set() then
    if bit6D(3) ~= 0 then
      m:set8(r + 0x78, 8); m:set8(r + 0x74, 0); m:set8(r + 0x72, 0)
    elseif same_record() then
      release_aux()
    end
  end
  if m:u8(r + 0x0C) == 0x56 and m:u8(r + 0x7A) ~= 0 and not aux_set() and bit6D(3) ~= 0 and
     m:u8(r + 0x6A) & 0x3F == 0 and m:u8(r + 0x75) == 0 then
    m:set8(r + 0x75, 0); m:set8(r + 0x78, 1); m:set8(r + 0x73, 0)
    strcat_r98(0x4865)
    m:set8(r + 0x7A, 0); m:set8(r + 0x7B, 0)
  end
  if m:u8(r + 0x7A) ~= 0 and aux_set() then
    if bit6D(3) ~= 0 then
      m:set8(r + 0x75, 0); m:set8(r + 0x78, 1)
      strcat_r98(0x4868)
      m:set8(r + 0x7A, 0); m:set8(r + 0x7B, 0)
      if same_record() then release_aux() end
    else
      m:set8(r + 0x73, 1)
    end
  end
  m:set8(r + 0x0B, 4)
  return 1
end

-- 151F:2029: for a record with several readings (+0B > 1), find the reading
-- for its tag ("T." or the tag letter, 'n' for plural nouns), cut the text
-- after it at the next tag letter, then split the remaining senses at ';'
-- into alternative records chained through +8F (counted in the first
-- record's +89, numbered at +8) when DS:BBB6 enables the meanings list.
-- {annotations} are stripped, the first kept via strdup at +8B. Finally
-- 151F:0C03 establishes the record's own reading.
function senses.choose(m, rseg, roff)
  local ds = m.ds
  local r = linear(rseg, roff)
  local tagbuf = linear(ds, 0x4887)
  local unmarked, wtag, wflag = 0, 0x23, 0
  local pseg, poff, bseg, boff, qseg, qoff
  local function r98() return m:far(r + 0x98) end
  local function at(seg, off, i) return m:u8(linear(seg, (off + (i or 0)) & 0xFFFF)) end
  local t = m:u8(r + 0x0C)
  if t == 0x47 or t == 0x46 or t == 0x45 or t == 0x65 then t = 0x56 end
  m:set8(tagbuf, t)
  local s98, o98 = r98()
  pseg, poff = m:strstr(s98, o98, ds, 0x4887)
  if not memory.null(pseg, poff) then
    poff = (poff + 1) & 0xFFFF
  else
    bseg, boff = m:strchr(s98, o98, 0x7B)
    if m:u8(tagbuf) == 0x4E then
      m:set8(tagbuf, 0x6E)
      pseg, poff = m:strstr(s98, o98, ds, 0x4887)
      m:set8(tagbuf, 0x4E)
      if not memory.null(pseg, poff) then
        m:set8(r + 0x72, 1)
        poff = (poff + 1) & 0xFFFF
      elseif memory.null(bseg, boff) then
        pseg, poff = m:strchr(s98, o98, m:u8(tagbuf))
        if memory.null(pseg, poff) then
          pseg, poff = m:strchr(s98, o98, 0x6E)
          if not memory.null(pseg, poff) then m:set8(r + 0x72, 1) end
        end
      end
    elseif memory.null(bseg, boff) then
      pseg, poff = m:strchr(s98, o98, m:u8(tagbuf))
    end
  end
  if not memory.null(pseg, poff) then
    m:set_far(r + 0x98, pseg, poff)
  else
    pseg, poff = r98()
    unmarked = 1
  end
  -- Cut the reading at the next tag letter, '#' or '\\'.
  qseg, qoff = pseg, (poff + 1) & 0xFFFF
  while at(qseg, qoff) ~= 0 do
    local c = at(qseg, qoff)
    if c == 0x57 or at(pseg, poff) == 0x57 then
      repeat qoff = (qoff + 1) & 0xFFFF until at(qseg, qoff) == 0 or at(qseg, qoff) == 0x2F
    elseif c == 0x7B then
      repeat qoff = (qoff + 1) & 0xFFFF until at(qseg, qoff) == 0 or at(qseg, qoff) == 0x7D
    elseif alpha(c) or c == 0x23 or c == 0x5C then
      break
    end
    qoff = (qoff + 1) & 0xFFFF
  end
  m:set8(linear(qseg, qoff), 0)
  if m:u8(r + 0x0F) ~= 0x77 and m:u16(linear(ds, 0xBBA2)) ~= 0 then
    error('151F:2029 subject-domain filtering (DS:BBA2) is off in the frozen profile and not ported')
  end
  senses.skip_prefix(m, rseg, roff)
  s98, o98 = r98()
  if at(s98, (o98 - 1) & 0xFFFF) == 0x57 then wflag = 1 end
  if at(s98, o98) == 0x2E then
    wtag = 0x2E
    m:set_far(r + 0x98, s98, (o98 + 1) & 0xFFFF)
  else
    wtag = at(s98, o98)
    if alpha(wtag) or wtag == 0x23 then
      o98 = (o98 + 1) & 0xFFFF
      m:set_far(r + 0x98, s98, o98)
    end
    if at(s98, o98) == 0x2E then m:set_far(r + 0x98, s98, (o98 + 1) & 0xFFFF) end
  end
  s98, o98 = r98()
  if at(s98, o98) == 0x57 or wtag == 0x57 or wflag ~= 0 then wflag = 1 end
  -- Senses: "first;second{note};third/...".
  local current_seg, current_off = rseg, roff
  local current = r
  local last_seg, last_off = rseg, roff
  pseg, poff = m:strpbrk(s98, o98, ds, 0x4890)
  if not memory.null(pseg, poff) then
    while at(pseg, poff) ~= 0 do
      while at(pseg, poff) ~= 0 and at(pseg, poff) ~= 0x3B and at(pseg, poff) ~= 0x7B and at(pseg, poff) ~= 0x2F do
        poff = (poff + 1) & 0xFFFF
      end
      if at(pseg, poff) == 0x2F then m:set8(linear(pseg, poff), 0); poff = (poff + 1) & 0xFFFF end
      if at(pseg, poff) == 0x7B then
        m:set8(linear(pseg, poff), 0); poff = (poff + 1) & 0xFFFF
        local nseg, noff = pseg, poff
        while at(pseg, poff) ~= 0 and at(pseg, poff) ~= 0x7D do poff = (poff + 1) & 0xFFFF end
        if at(pseg, poff) ~= 0 then m:set8(linear(pseg, poff), 0); poff = (poff + 1) & 0xFFFF end
        local l = linear(last_seg, last_off)
        if memory.null(m:far(l + 0x8B)) then m:set_far(l + 0x8B, heap.strdup(m, nseg, noff)) end
      end
      local clone_seg, clone_off = 0, 0
      if at(pseg, poff) == 0x3B then
        m:set8(current + 0x89, (m:u8(current + 0x89) + 1) & 0xFF)
        m:set8(linear(pseg, poff), 0); poff = (poff + 1) & 0xFFFF
        if m:u16(linear(ds, 0xBBB6)) ~= 0 and at(pseg, poff) ~= 0 then
          -- Clones copy the original record; the chain runs through the last.
          clone_seg, clone_off = senses.clone(m, current_seg, current_off, pseg, poff)
          if not memory.null(clone_seg, clone_off) then
            m:set_far(linear(last_seg, last_off) + 0x8F, clone_seg, clone_off)
            m:set8(linear(clone_seg, clone_off) + 8, m:u8(current + 0x89))
          end
        end
      end
      if m:u16(linear(ds, 0xBBB6)) == 0 then break end
      if not memory.null(clone_seg, clone_off) then
        last_seg, last_off = clone_seg, clone_off
        pseg, poff = m:far(linear(clone_seg, clone_off) + 0x98)
      end
    end
  end
  senses.select(m, current_seg, current_off, current_seg, current_off, unmarked, wtag, wflag)
  return 1
end

-- 151F:2740: driver stage after reordering. Clears DS:BCF4 (the Russian
-- dictionary that matched last), then for every word record: numbers ('H')
-- get number from the last digit(s) of the source (1 but not 11 is
-- singular, 2-4 but not 12-14 ... natively only the tens digit 2-4 is
-- excluded) and person 3; records with several readings are resolved by
-- 151F:2029 unless they are '#'/'?' placeholders.
function senses.numeric_pass(m, root_seg, root_off)
  local ds = m.ds
  m:set_far(linear(ds, 0xBCF4), 0, 0)
  local seg, off = m:far(linear(root_seg, root_off))
  while not memory.null(seg, off) do
    local r = linear(seg, off)
    if m:u8(r + 0x0E) == 0x57 then
      if m:u8(r + 0x0C) == 0x48 then
        if m:u8(r + 0x0F) ~= 0x68 then
          local length = m:s16(r + 0x87)
          local function back(n) return m:u8(linear(seg, (off + length + 0x12 - n) & 0xFFFF)) end
          local last = back(1)
          if last == 0x31 then
            if length > 1 and back(2) == 0x31 then m:set8(r + 0x72, 1) end
          elseif last >= 0x32 and last <= 0x34 then
            if length > 1 then
              local tens = back(2)
              if tens ~= 0x32 and tens ~= 0x33 and tens ~= 0x34 then m:set8(r + 0x72, 1) end
            end
          else
            m:set8(r + 0x72, 1)
          end
        end
        m:set8(r + 0x74, 3)
        m:set8(r + 0x77, 1)
      elseif m:u8(r + 0x0B) > 1 then
        local tag = m:u8(r + 0x0C)
        if not (tag == 0x23 and m:u8(r + 0x0F) ~= 0x3D) and tag ~= 0x3F then
          senses.choose(m, seg, off)
        end
      end
    end
    seg, off = m:far(r)
  end
  return 1
end

return senses
