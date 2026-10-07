local memory = require 'core.memory'

local russian = {}

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
    if kind == 0x45 and (memory.ctype(k0) & 8) == 0 then return 0, 0 end
    if kind == 0x52 and not memory.is_lower_cyrillic(k0) then return 0, 0 end
    -- The two-letter key: the second byte is dropped at a word end or when
    -- it is not a lower-case letter of the dictionary's alphabet.
    local k1 = m:u8(linear(kseg, (koff + 1) & 0xFFFF))
    second = k1
    if END_OF_WORD[k1] then second = 0
    elseif kind == 0x45 and (memory.ctype(k1) & 8) == 0 then second = 0
    elseif kind == 0x52 and not memory.is_lower_cyrillic(k1) then second = 0 end
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

-- LTPRO 1E71:006F and 1E71:0BA0: replace a Russian word's ending using the
-- suffix tables in the data segment.
--
-- 1E71:006F selects a table of far pointers to suffix lists by word class and
-- variant, splits each list with strtok, and records (suffix length, list
-- index) for every suffix the word ends with in the array at DS:C808, ended
-- by an index of FFFFh. 1E71:0BA0 sorts the matches by length (Borland qsort,
-- so ties keep qsort's order), then applies the replacement entry of the best
-- list: a 6-byte record of (bytes to cut, far pointer to the new ending).

local function tables(class, variant)
  -- (table offset in DS, list count), from the two native switches.
  if class == 0x01 or class == 0x4E then
    if variant == 1 then return 0x5130, 0x42 end
    if variant == 2 then return 0x53C4, 0x23 end
    if variant == 0 then return 0x5522, 0x21 end
    return 0x5130, 0x42
  end
  if class == 0x02 or class == 0x05 or class == 0x06 or class == 0x07 or class == 0x41 or class == 0x49 then
    return 0x566C, 0x1A
  end
  if class == 0x03 or class == 0x45 or class == 0x46 or class == 0x47 or class == 0x56 or class == 0x76 then
    if variant == 1 then return 0x5CCC, 0x71 end
    if variant == 0x67 or variant == 0x6E or variant == 0xA3 then return 0x6136, 0x2F end
    return 0x58A8, 0x6A
  end
  return nil
end

-- Split as strtok does with the delimiter sets at DS:B97F (first call) and
-- DS:B981 (following calls).
local function tokens(m, text)
  local first, rest = m:cstring(m.ds, 0xB97F), m:cstring(m.ds, 0xB981)
  local list, i, delims = {}, 1, first
  while true do
    while i <= #text and delims:find(text:sub(i, i), 1, true) do i = i + 1 end
    if i > #text then break end
    local j = i
    while j <= #text and not delims:find(text:sub(j, j), 1, true) do j = j + 1 end
    list[#list + 1] = text:sub(i, j - 1)
    i = j + 1
    delims = rest
  end
  return list
end

-- 1E71:006F. Returns the index of the last match, -1 when none.
function russian.ending_matches(m, wseg, woff, class, variant, oseg, ooff)
  local length = m:strlen(wseg, woff)
  local out = linear(oseg, ooff)
  local table_offset, count = tables(class, variant)
  if (class == 0x03 or class == 0x45 or class == 0x46 or class == 0x47 or class == 0x56 or class == 0x76) and length > 2 then
    -- Ignore a reflexive ending held at DS:630C or DS:6310.
    local aseg, aoff = m:far(linear(m.ds, 0x630C))
    local bseg, boff = m:far(linear(m.ds, 0x6310))
    if memory.ends_with(m, wseg, woff, length, aseg, aoff) == 2 or
       memory.ends_with(m, wseg, woff, length, bseg, boff) == 2 then
      length = length - 2
    end
  end
  m:set16(out + 2, 0xFFFF)
  local last = -1
  if table_offset then
    local word = m:cstring(wseg, woff)
    for index = 0, count - 1 do
      local lseg, loff = m:far(linear(m.ds, (table_offset + index * 4) & 0xFFFF))
      for _, suffix in ipairs(tokens(m, m:cstring(lseg, loff))) do
        local n = #suffix
        if length - n >= 0 and word:sub(length - n + 1, length) == suffix and n > 0 then
          last = last + 1
          m:set16(out + last * 4, n)
          m:set16(out + last * 4 + 2, index)
        end
      end
    end
  end
  m:set16(out + (last + 1) * 4 + 2, 0xFFFF)
  return last
end

-- 1E71:0002, the qsort comparator: longer matches first.
local function longer_first(m, seg, a, b)
  local v = (m:u16(linear(seg, b)) - m:u16(linear(seg, a))) & 0xFFFF
  return v >= 0x8000 and v - 0x10000 or v
end

-- 1E71:0BA0: write the word with its ending replaced to `out`, or return
-- (0, 0) when no verb-class suffix of variant 'n' applies.
function russian.replace_ending(m, wseg, woff, oseg, ooff)
  local ds = m.ds
  local last = russian.ending_matches(m, wseg, woff, 3, 0x6E, ds, 0xC808)
  m:set16(linear(ds, 0xC806), last & 0xFFFF)
  if last == -1 then return 0, 0 end
  if last > 0 then
    -- Comparator 1E71:0002, relocated by the library load segment.
    memory.qsort(m, ds, 0xC808, last + 1, 4, longer_first, (0x1E71 + m.library_segment) & 0xFFFF, 0x0002)
  end
  local index = m:u16(linear(ds, 0xC80A))
  local entry = linear(ds, (0x61F2 + index * 6) & 0xFFFF)
  local rseg, roff = m:far(entry + 2)
  local first = m:u8(linear(rseg, roff))
  if first == 0 or first == 0x2D then return 0, 0 end
  local length = m:strlen(wseg, woff)
  local keep = (length - m:u16(entry)) & 0xFFFF
  if keep >= 0x8000 then keep = keep - 0x10000 end
  if keep > 0 then
    -- strncpy(out, word, keep) then out[keep] = 0.
    local text = m:cstring(wseg, woff):sub(1, keep)
    m:write_string(oseg, ooff, text .. string.rep('\0', keep - #text))
    m:set8(linear(oseg, (ooff + keep) & 0xFFFF), 0)
  else
    m:strcpy(oseg, ooff, wseg, woff)
  end
  if first ~= 0x3D then m:strcat(oseg, ooff, rseg, roff) end
  return oseg, ooff
end

return russian
