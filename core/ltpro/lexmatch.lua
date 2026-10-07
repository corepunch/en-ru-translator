-- LTPRO's record vector and lexical matcher on the memory model:
-- rebuild (1313:000E) and the lexical-vector matcher (1313:0A67), as used by
-- T7. The node-table versions in nodes.lua and matcher.lua serve T1-T4.
--
-- A vector is a Lua array indexed from 0 of {seg, off} record pointers, as
-- the native far-pointer array on the stack: entry `count` is null, and
-- entries after it keep values from an earlier, longer rebuild.
local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'
local runtime = require 'core.ltpro.runtime'
local lexmatch = {}
local linear = memory.linear

-- 1313:000E: collect the records of the list at (seg, off) into `vector`
-- and their tags into DS:C5AE, unlinking blank (' ') records: their
-- auxiliary record (+62) and its sub-rules are freed, and the record itself
-- with its sub-rules (+94) unless it is an 'X' record, which is only retagged
-- 'x' (it is referenced elsewhere). At most 200h records. Returns the count.
function lexmatch.rebuild(m, seg, off, vector)
  local ds = m.ds
  local si = 0
  local pseg, poff = m:far(linear(seg, off))
  local cseg, coff = pseg, poff
  while not memory.null(cseg, coff) do
    local r = linear(cseg, coff)
    if m:u8(r + 0x0C) ~= 0x20 then
      vector[si] = {cseg, coff}
      m:set8(linear(ds, (0xC5AE + si) & 0xFFFF), m:u8(r + 0x0C))
      si = si + 1
      pseg, poff = cseg, coff
    else
      m:set_far(linear(pseg, poff), m:far(r))
      if m:u8(r + 0x0E) == 0x57 and not memory.null(m:far(r + 0x62)) then
        local aseg, aoff = m:far(r + 0x62)
        local a = linear(aseg, aoff)
        if not memory.null(m:far(a + 0x94)) then heap.free(m, m:far(a + 0x94)) end
        heap.free(m, aseg, aoff)
      end
      if m:u8(r + 0x0F) == 0x58 then
        m:set8(r + 0x0C, 0x78)
      else
        if m:u8(r + 0x0E) == 0x57 and not memory.null(m:far(r + 0x94)) then heap.free(m, m:far(r + 0x94)) end
        heap.free(m, cseg, coff)
      end
    end
    cseg, coff = m:far(linear(pseg, poff))
    if si >= 0x200 then break end
  end
  vector[si] = {0, 0}
  m:set8(linear(ds, (0xC5AE + si) & 0xFFFF), 0)
  return si
end

local function record(vector, i)
  local entry = assert(vector[i], 'lexical matcher read beyond the native vector')
  return linear(entry[1], entry[2]), entry[1], entry[2]
end

-- 1313:0A67: match `pattern` (seg, off) from vector position `start`.
-- Tags come from the records (+0C) and spans from DS:C5AE. Returns the
-- index of the last matched record, or 0.
--   X ~ [..] <..>X <..>[..] as in the constituent matcher (no '.'); also
--   `w`   the record's source (+12, case-insensitively) or base (+9C) is w
--   !t!   the record's text (+11C) contains "t)"
--   <..>`w` / <..>!t!  skip to the next record satisfying that test
--   $     try the rest here; failing that, skip one record and go on
-- Word alternatives after a class are not ported (no rule uses them).
function lexmatch.match(m, vector, start, pseg, poff)
  local ds = m.ds
  local at, negate = start, 0
  local function c(i) return m:u8(linear(pseg, (poff + (i or 0)) & 0xFFFF)) end
  local function step(n) poff = (poff + (n or 1)) & 0xFFFF end
  local function collect(stops)
    local text = {}
    while c() ~= 0 and not stops:find(string.char(c()), 1, true) do
      text[#text + 1] = string.char(c()); step()
    end
    return table.concat(text)
  end
  local function tag(i) local r = record(vector, i); return m:u8(r + 0x0C) end
  local function fold(t) return (t:gsub('%l', string.upper)) end
  local function word(i, w)
    -- stricmp(source, w) == 0 or strcmp(base, w) == 0
    local _, s, o = record(vector, i)
    return fold(m:cstring(s, (o + 0x12) & 0xFFFF)) == fold(w) or m:cstring(s, (o + 0x9C) & 0xFFFF) == w
  end
  local function text(i, t)
    local _, s, o = record(vector, i)
    return m:cstring(s, (o + 0x11C) & 0xFFFF):find(t, 1, true) ~= nil
  end
  local function alternatives()
    if c() == 0x60 or c() == 0x21 then error('word alternatives in lexical classes are not ported') end
  end
  while c() ~= 0 do
    local p = c()
    if p == 0x7E then
      negate = 0x7E
    elseif p == 0x5B then
      step()
      local classes = collect(']`!')
      alternatives()
      if classes == '$' then
        at = at + 1
      else
        local t = tag(at)
        local found = t == 0 or classes:find(string.char(t), 1, true) ~= nil
        if negate ~= 0x7E and classes ~= '' and not found then return 0 end
        if negate == 0x7E and classes ~= '' and found then return 0 end
        negate = 0
        at = at + 1
      end
    elseif p == 0x60 or p == 0x21 then
      step()
      local value = collect(p == 0x60 and '`' or '!')
      if c() == 0 then return 0 end
      local ok
      if p == 0x60 then ok = word(at, value) else ok = text(at, value .. ')') end
      if (negate ~= 0x7E and not ok) or (negate == 0x7E and ok) then return 0 end
      negate = 0
      at = at + 1
    elseif p == 0x3C then
      step()
      local classes = collect('>`!')
      if c() == 0 then return 0 end
      alternatives()
      local cache = (0xC5AE + at) & 0xFFFF
      local anchor, width
      local after = c(1)
      if after == 0x5B or after == 0x60 or after == 0x21 then
        step(2)
        local sought = collect(']`!')
        if c() == 0 then return 0 end
        local close = c()
        if close == 0x21 then sought = sought .. ')' end
        width = 1
        step(-1)
        local scan, di = cache, at
        while m:u8(linear(ds, scan)) ~= 0 do
          local hit
          if close == 0x60 then hit = word(di, sought)
          elseif close == 0x21 then hit = text(di, sought)
          else hit = sought:find(string.char(m:u8(linear(ds, scan))), 1, true) ~= nil end
          if hit then break end
          scan, di = (scan + 1) & 0xFFFF, di + 1
        end
        if m:u8(linear(ds, scan)) == 0 then return 0 end
        anchor = scan
      else
        local token = ''
        local dseg, doff = m:far(linear(ds, 0x44E8))
        runtime.gettoken(m, pseg, (poff + 1) & 0xFFFF, dseg, doff, function(t) token = t end)
        local found = m:cstring(ds, cache):find(token, 1, true)
        if not found then return 0 end
        anchor = (cache + found - 1) & 0xFFFF
        width = #token
      end
      if anchor == cache then
        if negate == 0x7E then return 0 end
        at = at + width
        step(width)
      else
        local span = m:cstring(ds, cache):sub(1, (anchor - cache) & 0xFFFF)
        if classes:byte(1) ~= 0x24 then
          if negate ~= 0x7E and classes ~= '' then
            for i = 1, #span do if not classes:find(span:sub(i, i), 1, true) then return 0 end end
          end
          if negate == 0x7E and classes ~= '' then
            for i = 1, #span do if classes:find(span:sub(i, i), 1, true) then return 0 end end
          end
        end
        negate = 0
        at = at + #span + width
        step(width)
      end
    elseif p == 0x24 then
      local saved = poff
      local result = lexmatch.match(m, vector, at, pseg, (poff + 1) & 0xFFFF)
      if result ~= 0 then return result end
      poff = saved
      at = at + 1
    else
      local t = tag(at)
      if (negate ~= 0x7E and t ~= p) or (negate == 0x7E and t == p) then return 0 end
      negate = 0
      at = at + 1
    end
    if c() == 0 then break end
    step()
  end
  return (at - 1) & 0xFFFF
end

return lexmatch
