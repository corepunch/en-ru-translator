
local memory = {}

-- Byte-addressed model of LTPRO's real-mode memory for the post-reorder stages.
--
-- Those stages keep far pointers into translation strings, split strings in
-- place with NUL bytes, chain allocated records and read Russian dictionary
-- text into a shared buffer. Their observable behaviour depends on exact
-- addresses and segment:offset representations, so the ports operate on this
-- model rather than on string fields. A far pointer is a (segment, offset)
-- pair; arithmetic on it changes only the 16-bit offset, as the 8086 code does.
memory.__index = memory

-- `base` is an optional string holding initial memory from linear address 0
-- (a DOS snapshot); writes go to an overlay table, so the changed bytes can be
-- reported without copying the whole image.
function memory.new(base)
  return setmetatable({base = base or '', overlay = {}, files = {}, positions = {}}, memory)
end

function memory:u8(address)
  local value = self.overlay[address]
  if value then return value end
  return self.base:byte(address + 1) or 0
end

function memory:set8(address, value)
  self.overlay[address] = value & 0xFF
  if self.log then self.log[address] = true end
end

function memory:u16(address)
  return self:u8(address) | (self:u8(address + 1) << 8)
end

function memory:s16(address)
  local value = self:u16(address)
  return value >= 0x8000 and value - 0x10000 or value
end

function memory:set16(address, value)
  self:set8(address, value)
  self:set8(address + 1, value >> 8)
end

function memory:u32(address)
  return self:u16(address) | (self:u16(address + 2) << 16)
end

function memory:s32(address)
  local value = self:u32(address)
  return value >= 0x80000000 and value - 0x100000000 or value
end

function memory:set32(address, value)
  self:set16(address, value & 0xFFFF)
  self:set16(address + 2, (value >> 16) & 0xFFFF)
end

function memory.linear(segment, offset)
  return ((segment << 4) + offset) & 0xFFFFF
end

-- Far pointer stored at `address` as offset word then segment word.
function memory:far(address)
  return self:u16(address + 2), self:u16(address)
end

function memory:far_linear(address)
  return memory.linear(self:far(address))
end

function memory:set_far(address, segment, offset)
  self:set16(address, offset & 0xFFFF)
  self:set16(address + 2, segment & 0xFFFF)
end

function memory.null(segment, offset)
  return segment == 0 and offset == 0
end

-- C strings at a far pointer; offsets wrap within the segment like the
-- string helpers' SI/DI registers.
function memory:cstring(segment, offset)
  local bytes = {}
  while true do
    local c = self:u8(memory.linear(segment, offset))
    if c == 0 then break end
    bytes[#bytes + 1] = string.char(c)
    offset = (offset + 1) & 0xFFFF
  end
  return table.concat(bytes)
end

function memory:strlen(segment, offset)
  return #self:cstring(segment, offset)
end

function memory:write_string(segment, offset, text)
  for i = 1, #text do
    self:set8(memory.linear(segment, (offset + i - 1) & 0xFFFF), text:byte(i))
  end
end

-- strcpy copies forwards byte by byte including the NUL; an overlapping
-- destination after the source therefore re-reads copied bytes, as natively.
function memory:strcpy(dseg, doff, sseg, soff)
  local i = 0
  while true do
    local c = self:u8(memory.linear(sseg, (soff + i) & 0xFFFF))
    self:set8(memory.linear(dseg, (doff + i) & 0xFFFF), c)
    if c == 0 then break end
    i = i + 1
  end
  return dseg, doff
end

function memory:strcat(dseg, doff, sseg, soff)
  self:strcpy(dseg, (doff + self:strlen(dseg, doff)) & 0xFFFF, sseg, soff)
  return dseg, doff
end

-- strchr/strrchr/strstr/strpbrk return a pointer in the searched string's
-- segment, or (0, 0). strchr with NUL finds the terminator.
function memory:strchr(segment, offset, c)
  local i = 0
  while true do
    local b = self:u8(memory.linear(segment, (offset + i) & 0xFFFF))
    if b == c then return segment, (offset + i) & 0xFFFF end
    if b == 0 then return 0, 0 end
    i = i + 1
  end
end

function memory:strrchr(segment, offset, c)
  local text = self:cstring(segment, offset)
  if c == 0 then return segment, (offset + #text) & 0xFFFF end
  for i = #text, 1, -1 do
    if text:byte(i) == c then return segment, (offset + i - 1) & 0xFFFF end
  end
  return 0, 0
end

function memory:strstr(segment, offset, nseg, noff)
  local found = self:cstring(segment, offset):find(self:cstring(nseg, noff), 1, true)
  if not found then return 0, 0 end
  return segment, (offset + found - 1) & 0xFFFF
end

function memory:strpbrk(segment, offset, cseg, coff)
  local text, set = self:cstring(segment, offset), self:cstring(cseg, coff)
  for i = 1, #text do
    if set:find(text:sub(i, i), 1, true) then return segment, (offset + i - 1) & 0xFFFF end
  end
  return 0, 0
end

-- Borland stricmp folds ASCII a-z only; the result sign is what callers use.
local function fold(text) return (text:gsub('%l', string.upper)) end
function memory:stricmp(aseg, aoff, bseg, boff)
  local a, b = fold(self:cstring(aseg, aoff)), fold(self:cstring(bseg, boff))
  if a == b then return 0 end
  return a < b and -1 or 1
end

function memory:strcmp(aseg, aoff, bseg, boff)
  local a, b = self:cstring(aseg, aoff), self:cstring(bseg, boff)
  if a == b then return 0 end
  return a < b and -1 or 1
end

function memory:strncmp(aseg, aoff, bseg, boff, n)
  local a, b = self:cstring(aseg, aoff):sub(1, n), self:cstring(bseg, boff):sub(1, n)
  if a == b then return 0 end
  return a < b and -1 or 1
end

function memory:copy(dest, source, n)
  for i = 0, n - 1 do self:set8(dest + i, self:u8(source + i)) end
end

-- Changed bytes as a sorted list of {address, value}.
function memory:changes()
  local list = {}
  for address, value in pairs(self.overlay) do
    if value ~= (self.base:byte(address + 1) or 0) then list[#list + 1] = {address, value} end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  return list
end

-- Small LTPRO runtime helpers shared by the post-reorder stages.

-- 211E:113A: CP866 upper-case Cyrillic (80-9F) or Ё (F0).
function memory.is_upper_cyrillic(c)
  c = c & 0xFF
  return (c >= 0x80 and c < 0xA0) or c == 0xF0
end

-- 211E:115A: CP866 lower-case Cyrillic (A0-AF, E0-F1).
function memory.is_lower_cyrillic(c)
  c = c & 0xFF
  return (c >= 0xA0 and c < 0xB0) or (c >= 0xE0 and c < 0xF2)
end

-- 211E:117F: any CP866 Cyrillic letter (80-AF, E0-F1).
function memory.is_cyrillic(c)
  c = c & 0xFF
  return (c >= 0x80 and c < 0xB0) or (c >= 0xE0 and c < 0xF2)
end

-- Borland _ctype at DS:BF77, indexed by the unsigned byte: 1 space, 2 digit,
-- 4 upper, 8 lower, 10h hex, 20h control, 40h punctuation. Only ASCII has bits.
function memory.ctype(c)
  c = c & 0xFF
  if c >= 0x80 then return 0 end
  if c >= 0x30 and c <= 0x39 then return 2 end
  if c >= 0x41 and c <= 0x5A then return (c <= 0x46) and 0x14 or 4 end
  if c >= 0x61 and c <= 0x7A then return (c <= 0x66) and 0x18 or 8 end
  if c == 0x20 then return 1 end
  if c >= 0x09 and c <= 0x0D then return 0x21 end
  if c < 0x20 or c == 0x7F then return 0x20 end
  return 0x40
end

-- 2104:0002: if the first `length` bytes of the string end with `suffix`,
-- return the suffix length, else 0. A negative start returns 0.
function memory.ends_with(m, seg, off, length, sseg, soff)
  local n = m:strlen(sseg, soff)
  local start = length - n
  if start >= 0x8000 or start < 0 then return 0 end
  if m:strncmp(seg, (off + start) & 0xFFFF, sseg, soff, n) == 0 then return n end
  return 0
end

-- 2104:008C: strtok-like tokenizer with its state in DS: BDA8/BDAA (token
-- start), BDAC/BDAE (end of the token, where a null `seg, off` resumes) and
-- BDB0 (token length). The token is copied to `out` when given (a Lua
-- callback here, since callers pass a stack buffer). Returns the token
-- start, or (0, 0).
function memory.gettoken(m, seg, off, dseg, doff, out)
  local ds = m.ds
  local linear = memory.linear
  if memory.null(seg, off) then seg, off = m:far(linear(ds, 0xBDAC)) end
  m:set_far(linear(ds, 0xBDA8), 0, 0)
  if memory.null(seg, off) then return 0, 0 end
  local delims = m:cstring(dseg, doff)
  local function c() return m:u8(linear(seg, off)) end
  while c() ~= 0 and delims:find(string.char(c()), 1, true) do off = (off + 1) & 0xFFFF end
  if c() == 0 then
    m:set_far(linear(ds, 0xBDA8), 0, 0)
    m:set_far(linear(ds, 0xBDAC), 0, 0)
    return 0, 0
  end
  m:set_far(linear(ds, 0xBDA8), seg, off)
  local eseg, eoff = m:strpbrk(seg, off, dseg, doff)
  m:set_far(linear(ds, 0xBDAC), eseg, eoff)
  if memory.null(eseg, eoff) then
    if out then out(m:cstring(seg, off)) end
  else
    local length = (eoff - off) & 0xFFFF
    m:set16(linear(ds, 0xBDB0), length)
    if out then out(m:cstring(seg, off):sub(1, length)) end
  end
  return seg, off
end

-- Borland C library routines of LTPRO whose exact behaviour is observable:
-- qsort (0000:36D7; tie order) and strtok (0000:4047; its state at DS:CA24).

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
function memory.qsort(m, seg, off, count, width, compare, cseg, coff)
  m:set16(linear(m.ds, 0xCA1E), width)
  if width == 0 then return end
  m:set_far(linear(m.ds, 0xCA20), cseg or 0, coff or 0)
  sort(m, seg, off, count, width, compare)
end

-- 0000:4047 strtok. A null `seg, off` continues from the saved pointer.
function memory.strtok(m, seg, off, dseg, doff)
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

return memory
