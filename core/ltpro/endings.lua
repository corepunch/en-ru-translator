-- LTPRO 1E71:006F and 1E71:0BA0: replace a Russian word's ending using the
-- suffix tables in the data segment.
--
-- 1E71:006F selects a table of far pointers to suffix lists by word class and
-- variant, splits each list with strtok, and records (suffix length, list
-- index) for every suffix the word ends with in the array at DS:C808, ended
-- by an index of FFFFh. 1E71:0BA0 sorts the matches by length (Borland qsort,
-- so ties keep qsort's order), then applies the replacement entry of the best
-- list: a 6-byte record of (bytes to cut, far pointer to the new ending).
local memory = require 'core.ltpro.memory'
local runtime = require 'core.ltpro.runtime'
local clib = require 'core.ltpro.clib'
local endings = {}
local linear = memory.linear

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
function endings.matches(m, wseg, woff, class, variant, oseg, ooff)
  local length = m:strlen(wseg, woff)
  local out = linear(oseg, ooff)
  local table_offset, count = tables(class, variant)
  if (class == 0x03 or class == 0x45 or class == 0x46 or class == 0x47 or class == 0x56 or class == 0x76) and length > 2 then
    -- Ignore a reflexive ending held at DS:630C or DS:6310.
    local aseg, aoff = m:far(linear(m.ds, 0x630C))
    local bseg, boff = m:far(linear(m.ds, 0x6310))
    if runtime.ends_with(m, wseg, woff, length, aseg, aoff) == 2 or
       runtime.ends_with(m, wseg, woff, length, bseg, boff) == 2 then
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
function endings.replace(m, wseg, woff, oseg, ooff)
  local ds = m.ds
  local last = endings.matches(m, wseg, woff, 3, 0x6E, ds, 0xC808)
  m:set16(linear(ds, 0xC806), last & 0xFFFF)
  if last == -1 then return 0, 0 end
  if last > 0 then
    -- Comparator 1E71:0002, relocated by the library load segment.
    clib.qsort(m, ds, 0xC808, last + 1, 4, longer_first, (0x1E71 + m.library_segment) & 0xFFFF, 0x0002)
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

return endings
