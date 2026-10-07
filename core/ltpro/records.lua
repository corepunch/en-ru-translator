-- LTPRO record construction shared by the post-reorder stages.
local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'
local records = {}
local linear = memory.linear

records.SIZE = 0x26B -- bytes allocated per record (calloc(1, 26Bh))

-- 2269:0007: append `item` to the list whose first/last far pointers are at
-- +0/+4 of `list`; items are chained through their +0 pointer.
function records.append(m, lseg, loff, iseg, ioff)
  local list = linear(lseg, loff)
  if memory.null(m:far(list)) then
    m:set_far(list + 4, iseg, ioff)
    m:set_far(list, iseg, ioff)
  else
    m:set_far(m:far_linear(list + 4), iseg, ioff)
    m:set_far(list + 4, iseg, ioff)
  end
  m:set_far(linear(iseg, ioff), 0, 0)
end

-- 0687:0892: allocate a word record (+0E 'W') with tag `tag` and text, append
-- it to `parent`'s list when given, and count it in DS:C574 (limit DS:044D).
-- Numbers ('#'), '?' and 'H' keep their text as the source string (+12),
-- truncated to 50h bytes and retagged '#' when 28h or longer; other tags
-- store it as the translation (+11C). Only the low byte of the pushed tag
-- word is used. Returns (0, 0) at the limit.
function records.new(m, pseg, poff, tag, tseg, toff)
  local ds = m.ds
  local count = m:s16(linear(ds, 0xC574))
  if count >= m:s16(linear(ds, 0x044D)) then return 0, 0 end
  local seg, off = heap.calloc(m, 1, records.SIZE)
  if memory.null(seg, off) then return seg, off end
  local r = linear(seg, off)
  m:set8(r + 0x0E, 0x57)
  m:set8(r + 0x0C, tag & 0xFF)
  m:set16(r + 0x85, 0xFFFF)
  m:set_far(r + 0x98, seg, (off + 0x11C) & 0xFFFF)
  if not memory.null(tseg, toff) then
    local length = m:strlen(tseg, toff)
    m:set16(r + 0x87, length)
    local t = tag & 0xFF
    local numeric = t == 0x3F or t == 0x23 or t == 0x48
    if numeric then
      if length >= 0x28 then
        m:set8(r + 0x0C, 0x23)
        -- strncpy(+12, text, 50h): copies at most 50h bytes, NUL padded.
        local text = m:cstring(tseg, toff):sub(1, 0x50)
        text = text .. string.rep('\0', 0x50 - #text)
        m:write_string(seg, (off + 0x12) & 0xFFFF, text)
        if length < 0x50 then m:set8(r + 0x12 + length, 0) else m:set8(r + 0x62, 0) end
      else
        m:strcpy(seg, (off + 0x12) & 0xFFFF, tseg, toff)
      end
    end
    if not memory.null(pseg, poff) then records.append(m, pseg, poff, seg, off) end
    if not numeric then m:strcpy(seg, (off + 0x11C) & 0xFFFF, tseg, toff) end
  end
  m:set16(linear(ds, 0xC574), (m:u16(linear(ds, 0xC574)) + 1) & 0xFFFF)
  return seg, off
end

-- 0687:0A50 (file ACC0): release sentence records, alternatives and owned
-- strings, then reset the list with 2269:0442. The root itself is retained.
function records.clear(m, seg, off)
  local root = linear(seg, off)
  local s, o = m:far(root)
  local function release(p)
    local fs, fo = m:far(p)
    if not memory.null(fs, fo) then heap.free(m, fs, fo) end
  end
  while not memory.null(s, o) do
    local p = linear(s, o)
    if m:u8(p + 0x0E) == 0x57 then
      local as, ao = m:far(p + 0x8F)
      while not memory.null(as, ao) do
        local ap = linear(as, ao)
        local ns, no = m:far(ap + 0x8F)
        release(ap + 0x8B); heap.free(m, as, ao)
        as, ao = ns, no
      end
      local ps, po = m:far(p + 0x62)
      if not memory.null(ps, po) then
        release(linear(ps, po) + 0x94); heap.free(m, ps, po)
      end
      release(p + 0x94); release(p + 0x8B)
    end
    local ns, no = m:far(p)
    heap.free(m, s, o); s, o = ns, no
  end
  m:set_far(root, 0, 0)
  m:set_far(root + 4, seg, off)
end

return records
