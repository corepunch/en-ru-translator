-- Borland C library routines of LTPRO whose exact behaviour is observable:
-- qsort (0000:36D7; tie order) and strtok (0000:4047; its state at DS:CA24).
local memory = require 'core.ltpro.memory'
local clib = {}
local linear = memory.linear

-- 0000:3423 Exchange: swap `width` bytes.
local function exchange(m, seg, a, b, width)
  for i = 0, width - 1 do
    local x, y = linear(seg, (a + i) & 0xFFFF), linear(seg, (b + i) & 0xFFFF)
    local t = m:u8(x)
    m:set8(x, m:u8(y))
    m:set8(y, t)
  end
end

-- 0000:3451 qSortHelp over offsets in one segment; `compare(m, seg, a, b)`
-- returns a signed integer like the C comparator.
local function sort(m, seg, pivot, count, width, compare)
  while true do
    if count <= 2 then
      if count == 2 then
        local right = (pivot + width) & 0xFFFF
        if compare(m, seg, pivot, right) > 0 then exchange(m, seg, pivot, right, width) end
      end
      return
    end
    local right = (pivot + (count - 1) * width) & 0xFFFF
    local left = (pivot + (count >> 1) * width) & 0xFFFF
    -- Median of three.
    if compare(m, seg, left, right) > 0 then exchange(m, seg, left, right, width) end
    if compare(m, seg, left, pivot) > 0 then exchange(m, seg, left, pivot, width)
    elseif compare(m, seg, pivot, right) > 0 then exchange(m, seg, pivot, right, width) end
    if count == 3 then exchange(m, seg, pivot, left, width); return end
    left = (pivot + width) & 0xFFFF
    local pivot_end = left
    local broke = false
    repeat
      local result = compare(m, seg, left, pivot)
      while result <= 0 do
        if result == 0 then
          exchange(m, seg, left, pivot_end, width)
          pivot_end = (pivot_end + width) & 0xFFFF
        end
        if left < right then left = (left + width) & 0xFFFF
        else broke = true; break end
        result = compare(m, seg, left, pivot)
      end
      if broke then break end
      while left < right do
        result = compare(m, seg, pivot, right)
        if result < 0 then
          right = (right - width) & 0xFFFF
        else
          exchange(m, seg, left, right, width)
          if result ~= 0 then
            left = (left + width) & 0xFFFF
            right = (right - width) & 0xFFFF
          end
          break
        end
      end
    until not (left < right)
    if compare(m, seg, left, pivot) <= 0 then left = (left + width) & 0xFFFF end
    local low, pivot_temp = (left - width) & 0xFFFF, pivot
    while pivot_temp < pivot_end and low >= pivot_end do
      exchange(m, seg, pivot_temp, low, width)
      pivot_temp = (pivot_temp + width) & 0xFFFF
      low = (low - width) & 0xFFFF
    end
    -- Both counts are 32-bit signed quotients truncated to 16-bit registers.
    local function quotient(a) return (a >= 0 and a // width or -((-a) // width)) & 0xFFFF end
    local left_count = quotient(left - pivot_end)
    local right_count = quotient(((pivot + count * width) & 0xFFFF) - left)
    if right_count < left_count then
      sort(m, seg, left, right_count, width, compare)
      count = left_count
    else
      sort(m, seg, pivot, left_count, width, compare)
      pivot, count = left, right_count
    end
  end
end

-- `cseg, coff` is the comparator's far pointer as the native caller passes
-- it (relocated segment); qsort keeps width and comparator in DS:CA1E/CA20.
function clib.qsort(m, seg, off, count, width, compare, cseg, coff)
  m:set16(linear(m.ds, 0xCA1E), width)
  if width == 0 then return end
  m:set_far(linear(m.ds, 0xCA20), cseg or 0, coff or 0)
  sort(m, seg, off, count, width, compare)
end

-- 0000:4047 strtok. A null `seg, off` continues from the saved pointer.
function clib.strtok(m, seg, off, dseg, doff)
  local state = linear(m.ds, 0xCA24)
  if not memory.null(seg, off) then m:set_far(state, seg, off) end
  local delims = m:cstring(dseg, doff)
  local function current() local s, o = m:far(state); return s, o, m:u8(linear(s, o)) end
  local function advance() local s, o = m:far(state); m:set_far(state, s, (o + 1) & 0xFFFF) end
  local function is_delim(c) return c ~= 0 and delims:find(string.char(c), 1, true) ~= nil end
  while true do
    local _, _, c = current()
    if c == 0 or not is_delim(c) then break end
    advance()
  end
  local tseg, toff, c = current()
  if c == 0 then return 0, 0 end
  while true do
    local s, o, b = current()
    if b == 0 then break end
    if is_delim(b) then
      m:set8(linear(s, o), 0)
      advance()
      break
    end
    advance()
  end
  return tseg, toff
end

return clib
