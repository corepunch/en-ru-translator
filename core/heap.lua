local memory = require 'core.memory'

local heap = {}

-- Borland C far heap of LTPRO (library segment 0000: malloc 1CB4, calloc
-- 1951, free 1BAA, strdup 3D6A, sbrk 1F51, brk 1F12/1E9C), so that records
-- allocated by the ported stages receive the native addresses.
--
-- Blocks are paragraph aligned; the header is in the block's own segment:
--   +0 size in paragraphs (header included)
--   +2 previous physical block, or 0 when the block is free
--   +4/+6 previous/next free block (free blocks only)
--   +8 previous physical block while free
-- User data starts at offset 4. The heap's first, last and rover segments are
-- words in the library code segment at CS:1A6A, CS:1A6C and CS:1A6E. The DS
-- words 7B (program block segment), 87/89 (heap base), 8B/8D (break level),
-- 8F/91 (heap top) and C3D8 (allocated size in 64-paragraph units) control
-- growth, which resizes the program's DOS memory block (INT 21h 4Ah).
local linear = memory.linear

local function cs_word(m, offset) return linear(m.library_segment, offset) end
local FIRST, LAST, ROVER = 0x1A6A, 0x1A6C, 0x1A6E

local function get(m, offset) return m:u16(cs_word(m, offset)) end
local function put(m, offset, value) m:set16(cs_word(m, offset), value) end
local function hw(m, seg, at) return m:u16(linear(seg, at)) end
local function set_hw(m, seg, at, value) m:set16(linear(seg, at), value) end
local function ds(m, at) return linear(m.ds, at) end

-- 0000:07EE: compare far pointers after normalization (seg + off>>4, off&15).
local function compare(aseg, aoff, bseg, boff)
  local a1, b1 = (aseg + (aoff >> 4)) & 0xFFFF, (bseg + (boff >> 4)) & 0xFFFF
  if a1 ~= b1 then return a1 < b1 and -1 or 1 end
  local a2, b2 = aoff & 0xF, boff & 0xF
  if a2 ~= b2 then return a2 < b2 and -1 or 1 end
  return 0
end

-- INT 21h 4Ah on the program block: grow or shrink it, absorbing the
-- following free block as DOSBox does. Returns true, or false and the
-- largest available size.
local function setblock(m, segment, wanted)
  local mcb = (segment - 1) * 16
  local size = m:u16(mcb + 3)
  local following = mcb + (size + 1) * 16
  local kind = m:u8(mcb)
  local available = size
  if m:u16(following + 1) == 0 then
    available = available + m:u16(following + 3) + 1
    kind = m:u8(following)
  end
  if wanted > available then return false, available end
  m:set16(mcb + 3, wanted)
  if wanted < available then
    local free = mcb + (wanted + 1) * 16
    m:set8(mcb, 0x4D)
    m:set8(free, kind)
    m:set16(free + 1, 0)
    m:set16(free + 3, available - wanted - 1)
  else
    m:set8(mcb, kind)
  end
  return true
end

-- 0000:1E9C: set the break level, resizing the DOS block in 64-paragraph
-- steps. Returns 1 on success.
local function set_break(m, seg, off)
  local base = m:u16(ds(m, 0x7B))
  local units = (((seg + 1 - base) & 0xFFFF) + 0x3F & 0xFFFF) >> 6
  if units ~= m:u16(ds(m, 0xC3D8)) then
    local paragraphs = (units << 6) & 0xFFFF
    local top = m:u16(ds(m, 0x91))
    if (paragraphs + base) & 0xFFFF > top then paragraphs = (top - base) & 0xFFFF end
    local ok, largest = setblock(m, base, paragraphs)
    if not ok then
      m:set16(ds(m, 0x91), (base + largest) & 0xFFFF)
      m:set16(ds(m, 0x8F), 0)
      return 0
    end
    m:set16(ds(m, 0xC3D8), paragraphs >> 6)
  end
  m:set16(ds(m, 0x8D), seg)
  m:set16(ds(m, 0x8B), off)
  return 1
end

-- 0000:0573 (positive increments): huge-pointer addition, normalized.
local function huge_add(seg, off, increment)
  local lo, hi = increment & 0xFFFF, (increment >> 16) & 0xFFFF
  local ax = off + lo
  local dx = seg
  if ax > 0xFFFF then ax = ax & 0xFFFF; dx = dx + 0x1000 end
  dx = (dx + ((hi & 0xFF) << 12) + (ax >> 4)) & 0xFFFF
  return dx, ax & 0xF
end

-- 0000:1F51: grow the break level by `increment` bytes; returns the old
-- break (segment, offset) or nil.
local function sbrk(m, increment)
  local bseg, boff = m:u16(ds(m, 0x8D)), m:u16(ds(m, 0x8B))
  local target = bseg * 16 + boff + increment
  if target > 0xFFFFF then return nil end
  local nseg, noff = huge_add(bseg, boff, increment)
  if compare(nseg, noff, m:u16(ds(m, 0x89)), m:u16(ds(m, 0x87))) < 0 then return nil end
  if compare(nseg, noff, m:u16(ds(m, 0x91)), m:u16(ds(m, 0x8F))) > 0 then return nil end
  if set_break(m, nseg, noff) == 0 then return nil end
  return bseg, boff
end

-- 0000:1F12: set the break to a pointer; 0 on success, -1 on failure.
local function brk(m, seg, off)
  if compare(seg, off, m:u16(ds(m, 0x89)), m:u16(ds(m, 0x87))) < 0 then return -1 end
  if compare(seg, off, m:u16(ds(m, 0x91)), m:u16(ds(m, 0x8F))) > 0 then return -1 end
  if set_break(m, seg, off) == 0 then return -1 end
  return 0
end

-- 0000:1B4A: unlink a free block; the rover moves to its predecessor.
local function unlink(m, s)
  local nxt = hw(m, s, 6)
  if s == nxt then put(m, ROVER, 0); return end
  local prev = hw(m, s, 4)
  set_hw(m, prev, 6, nxt)
  set_hw(m, nxt, 4, prev)
  put(m, ROVER, prev)
end

-- 0000:1B73: insert a free block after the rover.
local function insert(m, s)
  local rover = get(m, ROVER)
  if rover == 0 then
    put(m, ROVER, s); set_hw(m, s, 4, s); set_hw(m, s, 6, s)
    return
  end
  local nxt = hw(m, rover, 6)
  set_hw(m, rover, 6, s)
  set_hw(m, s, 4, rover)
  set_hw(m, nxt, 4, s)
  set_hw(m, s, 6, nxt)
end

-- 0000:1BD3: first allocation creates the heap at the (aligned) break.
local function create(m, paragraphs)
  local _, off = sbrk(m, 0)
  if off and off & 0xF ~= 0 then sbrk(m, 0x10 - (off & 0xF)) end
  local seg, boff = sbrk(m, (paragraphs * 16) & 0xFFFFFFFF)
  if not seg then return 0, 0 end
  put(m, FIRST, seg); put(m, LAST, seg)
  set_hw(m, seg, 0, paragraphs)
  set_hw(m, seg, 2, seg)
  return seg, 4
end

-- 0000:1C37: append a block at the break.
local function grow(m, paragraphs)
  local seg, off = sbrk(m, (paragraphs * 16) & 0xFFFFFFFF)
  if not seg then return 0, 0 end
  if off & 0xF ~= 0 then
    -- Align: grow by the remainder and start at the next paragraph.
    if not sbrk(m, (0x10 - (off & 0xF)) & 0xFFFF) then return 0, 0 end
    seg = (seg + 1) & 0xFFFF
  end
  local previous = get(m, LAST)
  put(m, LAST, seg)
  set_hw(m, seg, 0, paragraphs)
  set_hw(m, seg, 2, previous)
  return seg, 4
end

-- 0000:1C91: allocate from the end of a larger free block.
local function split(m, free, paragraphs)
  set_hw(m, free, 0, (hw(m, free, 0) - paragraphs) & 0xFFFF)
  local seg = (free + hw(m, free, 0)) & 0xFFFF
  set_hw(m, seg, 0, paragraphs)
  set_hw(m, seg, 2, free)
  set_hw(m, (seg + paragraphs) & 0xFFFF, 2, seg)
  return seg, 4
end

-- 0000:1CB4 malloc(n): returns (segment, offset), (0, 0) on failure.
function heap.malloc(m, n)
  n = n & 0xFFFF
  if n == 0 then return 0, 0 end
  local total = n + 0x13
  if total > 0xFFFFF then return 0, 0 end
  local paragraphs = (total >> 4) & 0xFFFF
  if get(m, FIRST) == 0 then return create(m, paragraphs) end
  local rover = get(m, ROVER)
  if rover == 0 then return grow(m, paragraphs) end
  local s = rover
  repeat
    local size = hw(m, s, 0)
    if size >= paragraphs then
      if size > paragraphs then return split(m, s, paragraphs) end
      unlink(m, s)
      set_hw(m, s, 2, hw(m, s, 8))
      return s, 4
    end
    s = hw(m, s, 6)
  until s == rover
  return grow(m, paragraphs)
end

-- 0000:1951 calloc(count, size): zeroed block, (0, 0) when count*size > FFFFh.
function heap.calloc(m, count, size)
  local n = (count & 0xFFFF) * (size & 0xFFFF)
  if n > 0xFFFF then return 0, 0 end
  local seg, off = heap.malloc(m, n)
  if not memory.null(seg, off) then
    for i = 0, n - 1 do m:set8(linear(seg, (off + i) & 0xFFFF), 0) end
  end
  return seg, off
end

-- 0000:3D6A strdup.
function heap.strdup(m, sseg, soff)
  local text = m:cstring(sseg, soff) .. '\0'
  local seg, off = heap.malloc(m, #text)
  if not memory.null(seg, off) then m:write_string(seg, off, text) end
  return seg, off
end

-- 0000:1BAA free(pointer): only the segment matters.
function heap.free(m, seg, off)
  if seg == 0 then return end
  if seg == get(m, LAST) then
    -- 0000:1A76: release the last block, and a free block before it.
    if seg == get(m, FIRST) then
      put(m, FIRST, 0); put(m, LAST, 0); put(m, ROVER, 0)
      brk(m, seg, 0)
      return
    end
    local previous = hw(m, seg, 2)
    if hw(m, previous, 2) ~= 0 then
      put(m, LAST, previous)
      brk(m, seg, 0)
      return
    end
    if previous == get(m, FIRST) then
      put(m, FIRST, 0); put(m, LAST, 0); put(m, ROVER, 0)
      brk(m, previous, 0)
      return
    end
    put(m, LAST, hw(m, previous, 8))
    unlink(m, previous)
    brk(m, previous, 0)
    return
  end
  -- 0000:1AD9: mark free and merge with free neighbours.
  local previous = hw(m, seg, 2)
  set_hw(m, seg, 2, 0)
  set_hw(m, seg, 8, previous)
  local current = seg
  if seg ~= get(m, FIRST) and hw(m, previous, 2) == 0 then
    set_hw(m, previous, 0, (hw(m, previous, 0) + hw(m, seg, 0)) & 0xFFFF)
    local following = (seg + hw(m, seg, 0)) & 0xFFFF
    if hw(m, following, 2) == 0 then set_hw(m, following, 8, previous)
    else set_hw(m, following, 2, previous) end
    current = previous
  else
    insert(m, seg)
  end
  local following = (current + hw(m, current, 0)) & 0xFFFF
  if hw(m, following, 2) ~= 0 then return end
  -- The following block is free: absorb it.
  set_hw(m, current, 0, (hw(m, current, 0) + hw(m, following, 0)) & 0xFFFF)
  set_hw(m, (following + hw(m, following, 0)) & 0xFFFF, 2, current)
  unlink(m, following)
end

-- LTPRO record construction shared by the post-reorder stages.

heap.RECORD_SIZE = 0x26B -- bytes allocated per record (calloc(1, 26Bh))

-- 2269:0007: append `item` to the list whose first/last far pointers are at
-- +0/+4 of `list`; items are chained through their +0 pointer.
function heap.append_record(m, lseg, loff, iseg, ioff)
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
function heap.new_record(m, pseg, poff, tag, tseg, toff)
  local ds = m.ds
  local count = m:s16(linear(ds, 0xC574))
  if count >= m:s16(linear(ds, 0x044D)) then return 0, 0 end
  local seg, off = heap.calloc(m, 1, heap.RECORD_SIZE)
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
    if not memory.null(pseg, poff) then heap.append_record(m, pseg, poff, seg, off) end
    if not numeric then m:strcpy(seg, (off + 0x11C) & 0xFFFF, tseg, toff) end
  end
  m:set16(linear(ds, 0xC574), (m:u16(linear(ds, 0xC574)) + 1) & 0xFFFF)
  return seg, off
end

-- 0687:0A50 (file ACC0): release sentence records, alternatives and owned
-- strings, then reset the list with 2269:0442. The root itself is retained.
function heap.clear_records(m, seg, off)
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

return heap
