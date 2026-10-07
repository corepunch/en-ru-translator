-- LTPRO's constituent array (segment 1C3D and the 2269 list helpers).
--
-- After the numeric pass the word records are regrouped into constituents:
-- an array of 12-byte elements at the far pointer DS:C7FA (count DS:C7FE):
--   +0 constituent tag   +2 class ('*', 'W', 'w', 'G', 'K', 'k', 'P', 'Y',
--   'y', 'C', 'D', 'q', ...)   +4/+8 first/last record of its sub-list
-- Bytes +1 and +3 are never written by the builder. A parallel tag string
-- (element tags, '*' first, NUL after the last) is kept at DS:C7B6 for the
-- constituent matcher 1C3D:0135. The rule table at DS:4FEC has 8-byte
-- entries: pattern far pointer, word, selector word (1-21).
local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'
local records = require 'core.ltpro.records'
local constituents = {}
local linear = memory.linear

-- 2269:0442: an empty list: first = null, last = the list itself.
function constituents.list_init(m, seg, off)
  local l = linear(seg, off)
  m:set_far(l, 0, 0)
  m:set_far(l + 4, seg, off)
end

-- 2269:01B2: remove and return the first item (+0 links the next).
function constituents.list_pop(m, seg, off)
  local l = linear(seg, off)
  local iseg, ioff = m:far(l)
  if not memory.null(iseg, ioff) then m:set_far(l, m:far(linear(iseg, ioff))) end
  local lseg, loff = m:far(l + 4)
  if lseg == iseg and loff == ioff then m:set_far(l + 4, seg, off) end
  return iseg, ioff
end

local function array(m) return m:far(linear(m.ds, 0xC7FA)) end
local function element(m, aseg, aoff, i) return linear(aseg, (aoff + i * 12) & 0xFFFF) end
local function tags(m, i) return linear(m.ds, (0xC7B6 + i) & 0xFFFF) end

-- 1C3D:00B1: insert a 12-byte element (given as a 12-byte string) at `at`,
-- shifting the elements and tag string up; returns the new count.
function constituents.insert(m, aseg, aoff, bytes, at, count)
  if not (at < count and at > 0) then return count end
  for i = count, at + 1, -1 do
    m:copy(element(m, aseg, aoff, i), element(m, aseg, aoff, i - 1), 12)
    m:set8(tags(m, i), m:u8(tags(m, i - 1)))
  end
  m:write_string(aseg, (aoff + at * 12) & 0xFFFF, bytes)
  m:set8(tags(m, at), bytes:byte(1))
  m:set8(tags(m, count + 1), 0)
  return count + 1
end

-- 1C3D:0025: exchange elements i and j and their tags.
function constituents.swap(m, aseg, aoff, i, j)
  local a, b = element(m, aseg, aoff, i), element(m, aseg, aoff, j)
  for k = 0, 11 do
    local t = m:u8(a + k); m:set8(a + k, m:u8(b + k)); m:set8(b + k, t)
  end
  local t = m:u8(tags(m, i)); m:set8(tags(m, i), m:u8(tags(m, j))); m:set8(tags(m, j), t)
end

-- 1C3D:1A97: chain the elements' sub-lists back into one list at `list`.
function constituents.relink(m, lseg, loff, aseg, aoff, count)
  local l = linear(lseg, loff)
  local e0 = element(m, aseg, aoff, 0)
  m:set_far(l, m:far(e0 + 4))
  m:set_far(l + 4, m:far(e0 + 8))
  local i = 1
  while i < count do
    local e = element(m, aseg, aoff, i)
    if not memory.null(m:far(e + 4)) then
      m:set_far(m:far_linear(l + 4), m:far(e + 4))
      m:set_far(l + 4, m:far(e + 8))
    end
    i = i + 1
  end
  return i
end

-- 1C3D:05C5: move the records of the list at (rseg, roff) into constituent
-- elements of the array (aseg, aoff); returns the element count. The array
-- has 42h elements but up to 44h are written, as natively.
function constituents.build(m, rseg, roff, aseg, aoff)
  local si = 0
  local rec_seg, rec_off, v
  local function E(i) return element(m, aseg, aoff, i) end
  local function e0(i) return m:u8(E(i)) end
  local function e2(i) return m:u8(E(i) + 2) end
  local function set_tag(i, t) m:set8(tags(m, i), t); m:set8(E(i), t) end
  local function set_class(i, c) m:set8(E(i) + 2, c) end
  local function list(i) return aseg, (aoff + i * 12 + 4) & 0xFFFF end
  local function open(i) constituents.list_init(m, list(i)) end
  local function append(i) local s0, o0 = list(i); records.append(m, s0, o0, rec_seg, rec_off) end
  local function new(i, tag, class) set_tag(i, tag); set_class(i, class); open(i) end
  local function r(at) return m:u8(linear(rec_seg, rec_off) + at) end
  local function set_r(at, value) m:set8(linear(rec_seg, rec_off) + at, value) end
  local function following(at)
    -- The record still linked after this one in the source list.
    local nseg, noff = m:far(linear(rec_seg, rec_off))
    return linear(nseg, noff) + at
  end
  local function is(at) return m:stricmp(rec_seg, (rec_off + 0x12) & 0xFFFF, m.ds, at) == 0 end
  local function either(c, set) return set:find(string.char(c), 1, true) ~= nil end
  local function drop_boundary(i)
    -- Free the 't' boundary record that opened element i, reusing i.
    local bseg, boff = constituents.list_pop(m, list(i))
    local b = linear(bseg, boff)
    if m:u8(b + 0x0E) == 0x57 and not memory.null(m:far(b + 0x94)) then heap.free(m, m:far(b + 0x94)) end
    heap.free(m, bseg, boff)
  end

  rec_seg, rec_off = constituents.list_pop(m, rseg, roff)
  if memory.null(rec_seg, rec_off) then return 0 end
  m:set8(E(0), r(0x0C))
  set_class(0, 0x2A)
  m:set8(tags(m, 0), 0x2A)
  open(0)
  append(0)
  while true do
    rec_seg, rec_off = constituents.list_pop(m, rseg, roff)
    if memory.null(rec_seg, rec_off) or si > 0x42 then break end
    v = r(0x0C)
    if si == 0 then
      if v == 0x44 or v == 0x2C or v == 0x43 or v == 0x29 then append(si); goto continue end
      if v == 0x48 and (m:u8(following(0x0C)) == 0x2E or m:u8(following(0x0C)) == 0x29) then
        append(si); goto continue
      end
    end
    if v == 0x52 or v == 0x72 or v == 0x53 then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    if v == 0x51 and e0(si) ~= 0x50 then
      si = si + 1; new(si, v, 0x77); append(si); goto continue
    end
    if v == 0x47 or v == 0x46 then
      if e0(si) ~= v then si = si + 1; new(si, v, 0x47) end
      append(si); goto continue
    end
    if v == 0x4C or v == 0x6B then
      si = si + 1; new(si, v, 0x6B); append(si); goto continue
    end
    if v == 0x50 and not is(0x506C) and e2(si) == 0x50 then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    -- Element 1's class (the array's byte at +0E) and tag (+0C).
    if v == 0x50 and e2(1) ~= 0x50 and e0(1) == 0x50 and si == 1 and not is(0x506F) and not is(0x5072) then
      set_class(1, 0x50); append(si); goto continue
    end
    if v == 0x50 and si ~= 0 and e2(si) ~= 0x59 and e2(si) ~= 0x4B and e2(si) ~= 0x44 and
       m:u8(following(0x0C)) ~= 0x4D then
      if not is(0x5075) or e0(si) == 0x53 then
        si = si + 1; new(si, v, 0x57)
      elseif e2(si) == 0x77 then
        set_class(si, 0x57)
      elseif e2(si) ~= 0x47 and e0(si) ~= 0x57 then
        set_class(si, 0x77)
      end
      append(si); goto continue
    end
    if v == 0x77 and is(0x5078) then
      if e2(si) == 0x77 then set_class(si, 0x57) elseif e2(si) == 0x57 then set_class(si, 0x77) end
      append(si); goto continue
    end
    if v == 0x50 and e2(si) == 0x59 and m:u8(following(0x0C)) ~= 0x4D then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    if v == 0x50 and e2(si) == 0x44 then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    if v == 0x49 then
      if not either(e2(si), 'WwKP') then si = si + 1; new(si, v, 0x57) end
      if e0(si) ~= 0x50 then set_tag(si, v); set_class(si, 0x4B) end
      append(si); goto continue
    end
    if v == 0x48 then
      if not either(e2(si), 'WwKP') then si = si + 1; new(si, v, 0x57) end
      if e0(si) ~= 0x50 and e0(si) ~= 0x4E then
        set_tag(si, v)
        set_class(si, is(0x507B) and 0x57 or 0x4B)
      end
      append(si); goto continue
    end
    if v == 0x4F then
      if not either(e2(si), 'WwPGK') then
        if e0(si) == 0x74 then drop_boundary(si) else si = si + 1 end
        new(si, v, 0x57)
      end
      if not either(e0(si), 'WPI') and not either(e2(si), 'KGP') then
        set_tag(si, v)
        if m:u8(following(0x0C)) == 0x50 then
          set_class(si, 0x4B)
        elseif r(0x75) ~= 0 then
          set_tag(si, 0x6B); set_class(si, 0x4B)
        end
      end
      append(si); goto continue
    end
    if v == 0x4E or v == 0x41 or v == 0x23 or v == 0x3F or v == 0x69 or v == 0x24 then
      if e0(si) == 0x6B then set_class(si, 0x4B) end
      if not either(e2(si), 'WwPKG') then
        if e0(si) == 0x74 then drop_boundary(si) else si = si + 1 end
        new(si, v, 0x57)
      end
      if v == 0x41 and e0(si) == 0x4F and e2(si) ~= 0x4B and e0(si) ~= 0x57 then set_tag(si, v) end
      if (v == 0x4E or v == 0x23) and not either(e2(si), 'GK') and not either(e0(si), 'PQNWRk') then
        set_tag(si, v)
      end
      if v == 0x4E and e0(si) == 0x51 then set_class(si, 0x57) end
      append(si); goto continue
    end
    if either(v, 'UXYBbxyf') then
      si = si + 1; new(si, v, r(0x0F) == 0x72 and 0x79 or 0x59); append(si); goto continue
    end
    if v == 0x56 or v == 0x76 then
      if e2(si) ~= 0x59 then si = si + 1; new(si, v, 0x59) end
      append(si); goto continue
    end
    if v == 0x45 then
      if e0(si) ~= 0x50 and e0(si) ~= 0x47 then
        si = si + 1
        if r(0x0F) ~= 0x6E and e2(si - 1) ~= 0x43 and e0(si - 1) ~= 0x4C and e0(si - 1) ~= 0x2A then
          set_r(0x0C, 0x56); set_tag(si, 0x56); set_r(0x7A, 0)
        else
          set_tag(si, v)
        end
        set_class(si, 0x59); open(si); append(si)
      elseif r(0x0F) == 0x6E then
        append(si)
      elseif e0(si - 1) == 0x2A or e0(si - 1) == 0x56 then
        append(si)
      else
        si = si + 1; new(si, v, 0x59); append(si)
      end
      goto continue
    end
    if either(v, ';Jj|^t()=:pul_') then
      si = si + 1; new(si, v, 0x44); append(si); goto continue
    end
    if v == 0x26 and (e0(si) == 0x4E or e0(si) == 0x50) then
      if e2(si) == 0x57 or (e2(si) == 0x77 and r(0x66) ~= 0x43) then
        if e0(si) == 0x4E then set_tag(si, 0x57) end
        set_class(si, 0x57)
      end
      append(si); goto continue
    end
    if (v == 0x2C or v == 0x43) and si ~= 0 then
      if e2(si) ~= 0x59 then
        si = si + 1; new(si, v, 0x43)
      else
        local c = m:u8(following(0x0C))
        if not ((c == 0x56 or c == 0x43) and memory.null(m:far(following(0x62)))) then
          si = si + 1; new(si, v, 0x43)
        end
      end
      append(si); goto continue
    end
    if v == 0x2A and r(0x0D) == 0x2A then
      si = si + 1; new(si, v, 0x2A); append(si); goto continue
    end
    if si == 0 or e0(si) == 0x29 then si = si + 1; new(si, v, 0x57) end
    append(si)
    ::continue::
  end
  si = si + 1
  m:set8(tags(m, si), 0)
  return si
end

-- The element tags as the constituent matcher reads them (byte 0 of each
-- element, beyond the count too).
local function element_tags(m, aseg, aoff)
  local bytes = {}
  for i = 0, 0xFF do bytes[#bytes + 1] = string.char(m:u8(element(m, aseg, aoff, i))) end
  return table.concat(bytes)
end

-- 1C3D:0135: match a constituent pattern at element `start`. Tests read
-- element tags (byte 0 of each element) and the tag string DS:C7B6:
--   X       the element's tag is X ('~X': is not X)
--   .       any one element (a pending '~' stays pending)
--   [AB]    the tag is one of A, B ('~[..]': none); '[]' accepts any
--   <AB>XY  skip to the next occurrence of XY in the tag string; every
--           skipped tag must be one of A, B ('~': none); '<$>' accepts any
--   <AB>[XY] the same with the next tag that is one of X, Y
-- `word``word` lists after a class are parsed and ignored. Returns the
-- index of the last matched element, or 0.
function constituents.match(m, aseg, aoff, start, pseg, poff)
  local ds = m.ds
  local runtime = require 'core.ltpro.runtime'
  local at = start
  local negate = 0
  local function c(i) return m:u8(linear(pseg, (poff + (i or 0)) & 0xFFFF)) end
  local function tag(i) return m:u8(element(m, aseg, aoff, i)) end
  -- Collect characters up to one of `stops` (or NUL); nil when NUL ends it.
  local function collect(stops)
    local text = {}
    while c() ~= 0 and not stops:find(string.char(c()), 1, true) do
      text[#text + 1] = string.char(c()); poff = (poff + 1) & 0xFFFF
    end
    if c() == 0 then return nil end
    return table.concat(text)
  end
  local function skip_alternatives()
    local count = 0
    while c() ~= 0 and c() == 0x60 and count < 10 do
      poff = (poff + 1) & 0xFFFF
      while c() ~= 0 and c() ~= 0x60 do poff = (poff + 1) & 0xFFFF end
      if c() == 0 then return false end
      poff = (poff + 2) & 0xFFFF
      count = count + 1
    end
    return true
  end
  local function in_set(set, ch)
    -- strchr semantics: NUL is always found.
    return ch == 0 or set:find(string.char(ch), 1, true) ~= nil
  end
  while c() ~= 0 do
    local p = c()
    if p == 0x7E then
      negate = 0x7E
    elseif p == 0x5B then
      poff = (poff + 1) & 0xFFFF
      local classes = collect(']`')
      if not classes then return 0 end
      if not skip_alternatives() then return 0 end
      if classes ~= '' then
        local found = in_set(classes, tag(at))
        if (negate ~= 0x7E and not found) or (negate == 0x7E and found) then return 0 end
      end
      negate = 0
      at = at + 1
    elseif p == 0x3C then
      poff = (poff + 1) & 0xFFFF
      local classes = collect('>`')
      if not classes then return 0 end
      if not skip_alternatives() then return 0 end
      local cache = (0xC7B6 + at) & 0xFFFF
      local aseg2, aoff2, width
      if c(1) == 0x5B then
        poff = (poff + 2) & 0xFFFF
        local sought = collect(']`')
        if not sought then return 0 end
        width = 1
        poff = (poff - 1) & 0xFFFF
        aseg2, aoff2 = ds, cache
        while m:u8(linear(ds, aoff2)) ~= 0 and not sought:find(string.char(m:u8(linear(ds, aoff2))), 1, true) do
          aoff2 = (aoff2 + 1) & 0xFFFF
        end
        if m:u8(linear(ds, aoff2)) == 0 then return 0 end
      else
        local token = ''
        local dseg, doff = m:far(linear(ds, 0x44E8))
        runtime.gettoken(m, pseg, (poff + 1) & 0xFFFF, dseg, doff, function(t) token = t end)
        -- strstr(cache, token); the token is a stack copy natively.
        local found = m:cstring(ds, cache):find(token, 1, true)
        if not found then return 0 end
        aseg2, aoff2 = ds, (cache + found - 1) & 0xFFFF
        width = #token
      end
      if aoff2 == cache then
        if negate == 0x7E then return 0 end
        at = at + width
        poff = (poff + width) & 0xFFFF
      else
        local span = m:cstring(ds, cache):sub(1, (aoff2 - cache) & 0xFFFF)
        local first = classes:byte(1) or 0
        if first ~= 0x24 then
          if negate ~= 0x7E and first ~= 0 then
            for i = 1, #span do
              if not classes:find(span:sub(i, i), 1, true) then return 0 end
            end
          end
          if negate == 0x7E and first ~= 0 then
            for i = 1, #span do
              if classes:find(span:sub(i, i), 1, true) then return 0 end
            end
          end
        end
        negate = 0
        at = at + #span + width
        poff = (poff + width) & 0xFFFF
      end
    elseif p == 0x2E then
      at = at + 1
    else
      local t = tag(at)
      if (negate ~= 0x7E and t ~= p) or (negate == 0x7E and t == p) then return 0 end
      negate = 0
      at = at + 1
    end
    if c() == 0 then break end
    poff = (poff + 1) & 0xFFFF
  end
  return (at - 1) & 0xFFFF
end

-- 1C3D:1B3F: build the constituents of the record list `root`, then apply
-- the constituent rules (DS:4FEC) in order at every position.
-- `terminator` is the driver's SI (the sentence's final character).
function constituents.pass(m, root_seg, root_off, terminator, t7)
  local ds = m.ds
  local aseg, aoff = array(m)
  local count_at = linear(ds, 0xC7FE)
  m:set16(count_at, constituents.build(m, root_seg, root_off, aseg, aoff))
  if m:u16(count_at) == 0 then return end
  local function E(i) return element(m, aseg, aoff, i) end
  local function first(i) return m:far(E(i) + 4) end
  local function rec(seg, off) return linear(seg, off) end
  local function null(seg, off) return memory.null(seg, off) end
  local function source_is(seg, off, at) return m:stricmp(seg, (off + 0x12) & 0xFFFF, ds, at) == 0 end
  local function bit6D(r, n) return (m:u8(r + 0x6D) >> n) & 1 end
  local rule = 0x4FEC
  while not memory.null(m:far(linear(ds, rule))) do
    local si, more = 0, true
    while more and m:s16(count_at) - 1 > si do
      local pseg, poff = m:far(linear(ds, rule))
      local hit = constituents.match(m, aseg, aoff, si, pseg, poff)
      if hit ~= 0 then
        local selector = m:u16(linear(ds, rule + 6))
        if selector == 1 then
          local s, o = first(hit)
          if not null(s, o) and m:u8(rec(s, o) + 0x0F) == 0 and
             (source_is(s, o, 0x5107) or source_is(s, o, 0x510A) or source_is(s, o, 0x510D)) then
            m:set8(rec(s, o) + 0x76, 0x20)
          end
          more = false
        elseif selector == 3 then
          local lseg, loff = aseg, (aoff + (si + 1) * 12 + 4) & 0xFFFF
          t7(m, lseg, loff, m:u8(E(si + 1)), si, aseg, aoff)
          local ns, no = first(si + 1)
          local s, o = first(hit)
          while not null(s, o) do
            local c = m:u8(rec(s, o) + 0x0C)
            if c == 0x56 or c == 0x55 then break end
            s, o = m:far(rec(s, o))
          end
          if not null(ns, no) and not null(s, o) then
            m:set8(rec(s, o) + 0x77, m:u8(rec(ns, no) + 0x77))
            m:set8(rec(s, o) + 0x74, 3)
            m:set8(rec(s, o) + 0x72, m:u8(rec(ns, no) + 0x72))
          end
          more = false
        elseif selector == 4 then
          local di = hit
          while m:u8(E(di)) ~= 0x45 and di > si do di = di - 1 end
          local s, o = first(di)
          if not null(s, o) and m:u8(rec(s, o) + 0x0F) ~= 0x6E then
            m:set8(rec(s, o) + 0x0C, 0x56)
            m:set8(tags(m, di), 0x56)
            m:set8(E(di), 0x56)
            m:set8(rec(s, o) + 0x7A, 0)
          end
        elseif selector == 5 then
          local s, o = first(hit)
          if not null(s, o) then
            m:set8(tags(m, hit), 0x56)
            m:set8(E(hit), 0x56)
            m:set8(rec(s, o) + 0x0C, 0x56)
            m:set8(rec(s, o) + 0x7A, 0)
          end
        elseif selector == 7 then
          local s, o = first(si)
          if not null(s, o) and (m:u8(rec(s, o) + 0x6A) >> 6) & 1 ~= 0 then
            local bs, bo = first(hit)
            if not null(bs, bo) then
              local ts, to = m:far(rec(bs, bo) + 0x98)
              m:set8(linear(ts, to), 0)
            end
          end
        elseif selector == 9 then
          local as, ao = first(hit - 1)
          local bs, bo = first(hit)
          if not null(as, ao) and not null(bs, bo) then
            local a, b = rec(as, ao), rec(bs, bo)
            m:set8(a + 0x74, m:u8(b + 0x74))
            m:set8(a + 0x72, m:u8(b + 0x72))
            m:set8(a + 0x77, m:u8(b + 0x77))
            m:set8(E(hit) + 2, 0x71)
            m:set8(E(hit - 1) + 2, 0x71)
          end
          more = false
        elseif selector == 10 then
          -- Insert an 'L' constituent holding a new record with DS:5110's
          -- text. The element is built on the stack: bytes 1 and 3 are
          -- whatever the stack held (not modeled; written as 0 here).
          local nseg, noff = records.new(m, 0, 0, 0x4C, ds, 0x5110)
          local list = {first = {0, 0}, last = nil}
          local fseg, foff, lastseg, lastoff = 0, 0, 0, 0
          if not null(nseg, noff) then
            m:set8(rec(nseg, noff) + 0x0B, 3)
            m:set_far(rec(nseg, noff), 0, 0)
            fseg, foff, lastseg, lastoff = nseg, noff, nseg, noff
            local bytes = string.char(0x4C, 0, 0x4B, 0) ..
              string.pack('<I2I2I2I2', foff, fseg, lastoff, lastseg)
            m:set16(count_at, constituents.insert(m, aseg, aoff, bytes, hit, m:u16(count_at)))
          end
          more = false
        elseif selector == 18 then
          local s, o = first(hit)
          while not null(s, o) do
            if m:u8(rec(s, o) + 0x0C) == 0x56 then break end
            s, o = m:far(rec(s, o))
          end
          if not null(s, o) then
            local r = rec(s, o)
            if source_is(s, o, 0x511A) then
              local ts, to = m:far(r + 0x98)
              m:strcpy(ts, to, ds, 0x511E)
            elseif m:u8(r + 0x74) == 0 or m:u8(r + 0x66) == 0x65 then
              m:set8(r + 0x73, 0)
              m:set8(r + 0x78, m:u8(r + 0x78) | 4)
            end
          end
          m:set8(E(hit) + 2, 0x71)
          more = false
        elseif selector == 20 then
          local skip = m:u8(E(si - 1)) == 0x4C or terminator == 0x3A
          if not skip and m:u8(E(hit)) == 0x50 and m:u8(E(hit + 1)) == 0x4E then skip = true end
          local ps, po = first(hit - 1)
          if not skip then
            local p = rec(ps, po)
            if null(ps, po) or null(m:far(p)) or m:u8(p + 0x0E) == 0x44 then skip = true
            else
              local nc = m:u8(m:far_linear(p) + 0x0C)
              if nc == 0x56 or nc == 0x4D or nc == 0x77 or m:u8(p + 0x68) & 0x3F ~= 0 then skip = true end
            end
          end
          local as, ao = first(si)
          local bs, bo = first(hit)
          if not skip and (null(as, ao) or null(bs, bo)) then skip = true end
          if not skip then
            local a, b = rec(as, ao), rec(bs, bo)
            if m:u8(a + 0x0E) == 0x44 or m:u8(b + 0x0E) == 0x44 then skip = true
            elseif bit6D(a, 1) ~= 0 then skip = true
            elseif m:u8(b + 0x0C) == 0x50 and m:u8(b + 0x0F) == 0x77 then skip = true
            elseif m:u8(b + 0x0C) == 0x4A and source_is(bs, bo, 0x5125) then skip = true end
          end
          if not skip then
            local p = rec(ps, po)
            if m:u8(p + 0x0C) == 0x56 and bit6D(p, 0) ~= 0 and bit6D(p, 5) == 0 and bit6D(p, 4) == 0 and
               m:u8(p + 0x78) == 0 and m:u8(p + 0x7A) == 0 then
              local ts, to = m:far(p + 0x98)
              m:strcat(ts, to, ds, 0x512A)
            end
          end
        elseif selector == 21 then
          if m:u8(E(si - 1)) ~= 0x4C then
            local bs, bo = first(hit)
            if not null(bs, bo) and not (m:u8(rec(bs, bo) + 0x0C) == 0x50 and m:u8(rec(bs, bo) + 0x0F) == 0x77) then
              local ps, po = m:far(E(hit - 1) + 8)
              if not null(ps, po) then
                local p = rec(ps, po)
                if m:u8(p + 0x0C) == 0x56 and bit6D(p, 0) ~= 0 and bit6D(p, 5) == 0 and bit6D(p, 4) == 0 and
                   m:u8(p + 0x78) == 0 and m:u8(p + 0x7A) == 0 then
                  local ts, to = m:far(p + 0x98)
                  m:strcat(ts, to, ds, 0x512D)
                end
              end
            end
          end
        end
      end
      si = si + 1
    end
    rule = rule + 8
  end
end

return constituents
