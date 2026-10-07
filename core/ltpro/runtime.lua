-- Small LTPRO runtime helpers shared by the post-reorder stages.
local memory = require 'core.ltpro.memory'
local runtime = {}

-- 211E:113A: CP866 upper-case Cyrillic (80-9F) or Ё (F0).
function runtime.is_upper_cyrillic(c)
  c = c & 0xFF
  return (c >= 0x80 and c < 0xA0) or c == 0xF0
end

-- 211E:115A: CP866 lower-case Cyrillic (A0-AF, E0-F1).
function runtime.is_lower_cyrillic(c)
  c = c & 0xFF
  return (c >= 0xA0 and c < 0xB0) or (c >= 0xE0 and c < 0xF2)
end

-- 211E:117F: any CP866 Cyrillic letter (80-AF, E0-F1).
function runtime.is_cyrillic(c)
  c = c & 0xFF
  return (c >= 0x80 and c < 0xB0) or (c >= 0xE0 and c < 0xF2)
end

-- Borland _ctype at DS:BF77, indexed by the unsigned byte: 1 space, 2 digit,
-- 4 upper, 8 lower, 10h hex, 20h control, 40h punctuation. Only ASCII has bits.
function runtime.ctype(c)
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
function runtime.ends_with(m, seg, off, length, sseg, soff)
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
function runtime.gettoken(m, seg, off, dseg, doff, out)
  local ds = m.ds
  local memory = require 'core.ltpro.memory'
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

return runtime
