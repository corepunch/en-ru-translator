-- LTPRO's Russian dictionary (BASE.RUS) lookup: 1FCD:1031, 1FCD:007F,
-- 1FCD:057B and the two-letter index routines 043A:074D and 043A:0850.
--
-- A dictionary is described by a structure in memory (the list head is at
-- DS:C8B4; each descriptor's +0 links the next one):
--   +0B  1 when the buffer was allocated by the loader (freed on read errors)
--   +5C  'R' Russian / 'E' English key alphabet
--   +60  alphabet size: 20h for Russian (33 index columns), otherwise 26 letters
--   +62  remaining bytes of the current two-letter block (signed 32-bit)
--   +66  file size; +6A DOS handle; +6C size of the current read (32-bit)
--   +70  buffer; +74 current line; +78 rest of buffer; +7C index pointer
-- The index holds, for each first letter (row) and second letter or word end
-- (column), the file offset of the first line with that prefix, or -1.
-- Lines are read in chunks of at most DS:BCE8 bytes and searched with strstr.
local memory = require 'core.ltpro.memory'
local runtime = require 'core.ltpro.runtime'
local russian = {}
local linear = memory.linear

local END_OF_WORD = {[0] = true, [0x20] = true, [0x27] = true, [0x2F] = true, [0x2E] = true,
  [0x2D] = true, [0x2A] = true, [0x26] = true}

local function signed32(value)
  value = value & 0xFFFFFFFF
  return value >= 0x80000000 and value - 0x100000000 or value
end

local function row(alphabet, c)
  if alphabet == 0x20 then
    local r = c - 0xA0
    if c > 0xAF then r = r - 0x30 end
    return r
  end
  return c - 0x61
end

local function column(alphabet, c)
  if END_OF_WORD[c] then return alphabet end
  return row(alphabet, c)
end

local function entry(m, d, r, c, alphabet)
  local stride = alphabet == 0x20 and 0x84 or 0x6C
  local seg, off = m:far(d + 0x7C)
  return m:s32(linear(seg, (off + r * stride + c * 4) & 0xFFFF))
end

-- Row and column arithmetic is 16-bit like the native DI/SI registers.
local function word(v) return v & 0xFFFF end
local function sword(v) v = v & 0xFFFF; return v >= 0x8000 and v - 0x10000 or v end

-- 043A:074D: file offset of the block for the key's first two letters.
-- `d` is the descriptor's linear address; k0/k1 are the key's first bytes.
function russian.index_offset(m, d, k0, k1)
  local alphabet = m:u16(d + 0x60)
  return entry(m, d, word(row(alphabet, k0)), word(column(alphabet, k1)), alphabet)
end

-- 043A:0850: length of the key's block: the offset of the next non-empty
-- entry after it, minus its own offset. The native scan's starting column is
-- an uninitialized local; natively it holds the CS that the INT 21h inside
-- lseek pushed into that stack slot, i.e. the C library's load segment
-- (`garbage`). Any value above the alphabet size skips the rest of the row.
function russian.index_length(m, d, k0, k1, garbage)
  local alphabet = sword(m:u16(d + 0x60))
  local r = sword(row(alphabet, k0))
  local c = sword(column(alphabet, k1))
  local current = entry(m, d, word(r), word(c), alphabet)
  if current == -1 then return 0 end
  local following = -1
  if alphabet - 1 > c then
    -- The incremented column is never used: the scan starts at `garbage`.
  elseif alphabet - 1 > r then
    r = r + 1
  else
    return signed32(m:s32(d + 0x66) - current)
  end
  local scan_row, scan_column = r, sword(garbage)
  while scan_row < alphabet do
    local found = false
    while scan_column <= alphabet do
      local e = entry(m, d, word(scan_row), word(scan_column), alphabet)
      if e ~= -1 and e > current then following = e; found = true; break end
      scan_column = scan_column + 1
    end
    if found then break end
    scan_row, scan_column = scan_row + 1, 0
  end
  if following == -1 then following = m:s32(d + 0x66) end
  local length = signed32(following - current)
  if length < 0 then return 0 end
  return length
end

-- Borland lseek/read/eof over the dictionary handle. Positions are 32-bit.
local function lseek(m, handle, offset, whence)
  local data = assert(m.files[handle], 'unknown DOS handle')
  local position
  if whence == 0 then position = offset
  elseif whence == 1 then position = (m.positions[handle] or 0) + offset
  else position = #data + offset end
  m.positions[handle] = position & 0xFFFFFFFF
  return m.positions[handle]
end

local function read(m, handle, seg, off, count)
  -- read() returns 0 for a count of 0 or FFFFh without calling DOS.
  if count == 0 or count == 0xFFFF then return 0 end
  local data = assert(m.files[handle], 'unknown DOS handle')
  local position = m.positions[handle] or 0
  local chunk = data:sub(position + 1, position + count)
  m:write_string(seg, off, chunk)
  m.positions[handle] = position + #chunk
  return #chunk
end

local function eof(m, handle)
  return (m.positions[handle] or 0) >= #assert(m.files[handle], 'unknown DOS handle')
end

local function set_error(m, value) m:set16(linear(m.ds, 0xC8E0), value) end

-- 1FCD:057B: return the next line of the current block (its '\n' replaced by
-- NUL), refilling the buffer from the file when the block continues.
function russian.next_line(m, dseg, doff)
  local d = linear(dseg, doff)
  set_error(m, 0)
  if memory.null(m:far(d + 0x74)) then return 0, 0 end
  local rseg, roff = m:far(d + 0x78)
  if not memory.null(rseg, roff) and m:u8(linear(rseg, roff)) == 0x0A then return 0, 0 end
  local qseg, qoff = m:strchr(rseg, roff, 0x0A)
  if not memory.null(qseg, qoff) then
    m:set8(linear(qseg, qoff), 0)
    m:set_far(d + 0x74, m:far(d + 0x78))
    m:set_far(d + 0x78, qseg, (qoff + 1) & 0xFFFF)
    return m:far(d + 0x74)
  end
  if m:s32(d + 0x62) > 0 then
    local bseg, boff = m:far(d + 0x70)
    m:strcpy(bseg, boff, rseg, roff)
    local length = m:strlen(bseg, boff)
    local wanted = (m:u32(d + 0x6C) - length) & 0xFFFFFFFF
    local eseg, eoff = m:strchr(bseg, boff, 0)
    local n = read(m, m:u16(d + 0x6A), eseg, eoff, wanted & 0xFFFF)
    if n ~= wanted and not eof(m, m:u16(d + 0x6A)) then
      if m:u8(d + 0x0B) == 1 then error('heap free of the dictionary buffer is not modeled') end
      m:set_far(d + 0x70, 0, 0)
      m:set_far(d + 0x74, 0, 0)
      set_error(m, 0xC3)
      return 0, 0
    end
    m:set32(d + 0x62, m:u32(d + 0x62) - n)
    m:set8(linear(eseg, (eoff + n) & 0xFFFF), 0)
    local nseg, noff = m:strchr(eseg, eoff, 0x0A)
    m:set_far(d + 0x74, bseg, boff)
    -- No null check natively: a missing newline writes to 0000:0000.
    m:set8(linear(nseg, noff), 0)
    m:set_far(d + 0x78, nseg, (noff + 1) & 0xFFFF)
    return m:far(d + 0x74)
  end
  if memory.null(rseg, roff) then
    m:set_far(d + 0x74, 0, 0)
  else
    m:set_far(d + 0x74, rseg, roff)
    m:set_far(d + 0x78, 0, 0)
  end
  return m:far(d + 0x74)
end

-- 1FCD:007F: position on the key's block and find the line "\n<key>*" (or
-- "\n<key>" when `prefix` is nonzero) in it, chunk by chunk. A null key reads
-- from file offset 28h line by line. Returns the line pointer or (0, 0).
function russian.search(m, dseg, doff, kseg, koff, prefix)
  local d = linear(dseg, doff)
  local ds = m.ds
  local pattern = m:cstring(ds, 0xBCF8)
  local k0, second
  local handle = m:u16(d + 0x6A)
  local kind = m:u8(d + 0x5C)
  local position
  local has_key = not memory.null(kseg, koff)
  if not has_key then
    position = lseek(m, handle, 0x28, 0)
  else
    k0 = m:u8(linear(kseg, koff))
    if k0 == 0 then return 0, 0 end
    if kind == 0x45 and (runtime.ctype(k0) & 8) == 0 then return 0, 0 end
    if kind == 0x52 and not runtime.is_lower_cyrillic(k0) then return 0, 0 end
    -- The two-letter key: the second byte is dropped at a word end or when
    -- it is not a lower-case letter of the dictionary's alphabet.
    local k1 = m:u8(linear(kseg, (koff + 1) & 0xFFFF))
    second = k1
    if END_OF_WORD[k1] then second = 0
    elseif kind == 0x45 and (runtime.ctype(k1) & 8) == 0 then second = 0
    elseif kind == 0x52 and not runtime.is_lower_cyrillic(k1) then second = 0 end
    local offset = russian.index_offset(m, d, k0, second)
    if offset == -1 then return 0, 0 end
    position = lseek(m, handle, offset & 0xFFFFFFFF, 0)
  end
  -- lseek's result is tested by its low word only.
  if position & 0xFFFF == 0 then return 0, 0 end
  m:set_far(d + 0x74, 0, 0)
  m:set_far(d + 0x78, 0, 0)
  local length
  if has_key then
    length = russian.index_length(m, d, k0, second, m.library_segment)
  else
    length = signed32(m:s32(d + 0x66) - m.positions[handle])
  end
  m:set32(d + 0x62, length)
  local function chunk()
    local cap = sword(m:u16(linear(ds, 0xBCE8)))
    local remaining = m:s32(d + 0x62)
    if cap < remaining or cap == remaining then return cap end
    return remaining
  end
  local size = chunk()
  m:set32(d + 0x6C, size)
  local bseg, boff = m:far(d + 0x70)
  if memory.null(bseg, boff) then set_error(m, 0xC4); return 0, 0 end
  set_error(m, 0)
  m:set_far(d + 0x74, bseg, (boff + 1) & 0xFFFF)
  m:set_far(d + 0x78, bseg, (boff + 1) & 0xFFFF)
  m:set8(linear(bseg, (boff + size) & 0xFFFF), 0)
  m:set8(linear(bseg, (boff + size + 1) & 0xFFFF), 0)
  if has_key then
    pattern = pattern .. m:cstring(kseg, koff)
    if prefix == 0 then pattern = pattern .. m:cstring(ds, 0xBD7C) end
  end
  local kept = 0
  while m:s32(d + 0x62) > 0 do
    local n = read(m, handle, bseg, (boff + kept) & 0xFFFF, (size - kept) & 0xFFFF)
    if size - kept ~= n then set_error(m, 0xC3); return 0, 0 end
    m:set8(linear(bseg, (boff + n + kept) & 0xFFFF), 0)
    if not has_key then
      local current_seg, current_off = m:far(d + 0x78)
      local qseg, qoff = m:strchr(current_seg, current_off, 0x0A)
      if not memory.null(qseg, qoff) then
        m:set8(linear(qseg, qoff), 0)
        m:set_far(d + 0x78, qseg, (qoff + 1) & 0xFFFF)
      end
      m:set32(d + 0x62, m:u32(d + 0x62) - size)
      return m:far(d + 0x74)
    end
    local text = m:cstring(bseg, boff)
    local found = text:find(pattern, 1, true)
    if found then
      local poff = (boff + found - 1) & 0xFFFF
      m:set_far(d + 0x74, bseg, poff)
      m:set_far(d + 0x78, bseg, (poff + 1) & 0xFFFF)
      local lseg, loff = russian.next_line(m, dseg, doff)
      m:set_far(d + 0x74, lseg, loff)
      return m:far(d + 0x74)
    end
    m:set_far(d + 0x74, 0, 0)
    m:set_far(d + 0x78, 0, 0)
    local qseg, qoff = m:strrchr(bseg, boff, 0x0A)
    local cap = sword(m:u16(linear(ds, 0xBCE8)))
    if not memory.null(qseg, qoff) and cap - kept == n then
      kept = m:strlen(qseg, qoff)
      m:strcpy(bseg, boff, qseg, qoff)
    else
      kept = 0
    end
    m:set32(d + 0x62, m:u32(d + 0x62) - (size - kept))
    size = chunk()
  end
  return m:far(d + 0x74)
end

-- 1FCD:1031: search the dictionary list after `head` (DS:C8B4 for Russian),
-- trying the descriptor that matched last time first. Returns the line.
function russian.lookup(m, hseg, hoff, kseg, koff, prefix)
  local ds = m.ds
  local primary = hseg == ds and hoff == 0xC8B4
  local cache = linear(ds, primary and 0xBCF4 or 0xBCEC)
  local after = linear(ds, primary and 0xC8CC or 0xC8D4)
  local cseg, coff = m:far(cache)
  local aseg, aoff = m:far(after)
  local rseg, roff = 0, 0
  if not memory.null(cseg, coff) then
    rseg, roff = russian.search(m, cseg, coff, kseg, koff, prefix)
  end
  if not memory.null(rseg, roff) then
    aseg, aoff = m:far(linear(cseg, coff))
  else
    local pseg, poff = m:far(linear(hseg, hoff))
    while not memory.null(pseg, poff) do
      if not (pseg == cseg and poff == coff) then
        rseg, roff = russian.search(m, pseg, poff, kseg, koff, prefix)
        if not memory.null(rseg, roff) then break end
      end
      pseg, poff = m:far(linear(pseg, poff))
    end
    if not memory.null(pseg, poff) then
      cseg, coff = pseg, poff
      aseg, aoff = m:far(linear(pseg, poff))
    else
      cseg, coff, aseg, aoff = 0, 0, 0, 0
    end
  end
  m:set_far(cache, cseg, coff)
  m:set_far(after, aseg, aoff)
  return rseg, roff
end

return russian
