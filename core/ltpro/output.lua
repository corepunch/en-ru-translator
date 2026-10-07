-- Sentence text and meanings appendix: 0687:0BB7 and 0687:01C8
-- (file offsets AE27 and A438). These append to caller-owned C strings.
local memory = require 'core.ltpro.memory'
local runtime = require 'core.ltpro.runtime'
local output = {}
local linear, null = memory.linear, memory.null
local function upper(c)
  if c >= 0xE0 and c < 0xF0 then return c - 0x50 end
  if c >= 0xA0 and c < 0xB0 then return c - 0x20 end
  return c == 0xF1 and 0xF0 or c
end
local function append(m, s, o, text)
  m:write_string(s, (o + m:strlen(s, o)) & 0xFFFF, text .. '\0')
end
local function textat(m, p) return m:cstring(m:far(p)) end
local function capitals(m, s, o)
  local n = 0
  for c in m:cstring(s, o):gmatch('.') do
    if m:u8(linear(m.ds, 0xBF77 + c:byte())) & 4 ~= 0 then n = n + 1 end
  end
  return n
end
local function capital(m, s, o, all, skip)
  if skip then
    if m:u8(linear(s, o)) == 0x2C then o = (o + 1) & 0xFFFF end
    if m:u8(linear(s, o)) == 0x20 then o = (o + 1) & 0xFFFF end
  end
  if all then
    while m:u8(linear(s, o)) ~= 0 do
      m:set8(linear(s, o), upper(m:u8(linear(s, o)))); o = (o + 1) & 0xFFFF
    end
  else m:set8(linear(s, o), upper(m:u8(linear(s, o)))) end
end

-- The two output routines share this native W-reading expansion. A closing
-- # or } ends the displayed reading; ASCII letters outside it become spaces.
function output.reading(m, text)
  if text:sub(1, 1) ~= 'W' then return text end
  local bytes, i = {}, 2
  while i <= #text do
    local c = text:byte(i)
    if c == 0x23 or c == 0x7B then
      bytes[#bytes + 1] = ' '
      local close = text:find(c == 0x23 and '#' or '}', i + 1, true)
      -- Native code reads past the terminator for an unterminated annotation.
      assert(close, 'unterminated native W-reading annotation')
      bytes[#bytes + 1] = text:sub(i + 1, close - 1)
      break
    end
    bytes[#bytes + 1] = m:u8(linear(m.ds, 0xBF77 + c)) & 0x0C ~= 0 and ' ' or string.char(c)
    i = i + 1
  end
  local result = table.concat(bytes)
  return result:sub(1, 1) == ' ' and result:sub(2) or result, result
end

function output.sentence(m, s, o, os, oo)
  local ds = linear(m.ds, 0)
  local si, first, count, previous = 0, true, 0, nil
  s, o = m:far(linear(s, o))
  assert(not null(s, o), 'output requires the native leading boundary')
  local initial_caps = m:u8(linear(s, o) + 9)
  local function emit(text) append(m, os, oo, text) end
  while not null(s, o) do
    local p = linear(s, o)
    local function b(n) return m:u8(p + n) end
    local function ptr(n) return m:far(p + n) end
    local function str(n) return m:cstring(s, (o + n) & 0xFFFF) end
    local function leading_upper(n) return m:u8(ds + 0xBF77 + b(n)) & 4 ~= 0 end
    local function cap_translation(all, skip)
      local ts, to = ptr(0x98); capital(m, ts, to, all, skip)
    end
    if b(0x0E) == 0x44 then
      local delimiter = b(0x0D)
      if delimiter == 0x20 then
        local c = b(0x12); emit(' ' .. (c ~= 0 and string.char(c) or ''))
      elseif delimiter ~= 0x2A and delimiter ~= 0x5E and delimiter ~= 0x7C and b(0x12) ~= 0 then
        emit(string.char(b(0x12)))
      end
      local ns, no = ptr(0)
      if b(0x0F) ~= 0 and not null(ns, no) and m:u8(linear(ns, no) + 0x0E) == 0x57 then
        m:set8(linear(ns, no) + 0x0D, 0x20)
      end
    else
      if b(0x0C) ~= 0x3F then
        local ps, po = ptr(0x62)
        if not null(ps, po) then
          local pp = linear(ps, po)
          if textat(m, pp + 0x98) ~= '' then
            si = capitals(m, ps, (po + 0x12) & 0xFFFF)
            local ts, to = m:far(pp + 0x98)
            if m:u8(ds + 0xBF77 + m:u8(pp + 0x12)) & 4 ~= 0 then capital(m, ts, to, false) end
            if si > 1 then capital(m, ts, (to + 1) & 0xFFFF, true) end
            if b(0x0D) == 0 then emit(m:cstring(m.ds, 0x5F5)) end
            emit(textat(m, pp + 0x98))
          end
        end
        -- The native tests the address of the inline prefix buffer, not its
        -- contents. For allocated records that address is always non-null.
        local marker = b(0x0F)
        if (marker == 0x77 or marker == 0x57) and previous and
          (m:u8(previous + 0x0F) == 0x77 or m:u8(previous + 0x0F) == 0x57) then
          local ts, to = m:far(previous + 0x98)
          if runtime.is_upper_cyrillic(m:u8(linear(ts, to))) or leading_upper(0x12) then
            cap_translation(false)
            if si > 1 then ts, to = ptr(0x98); capital(m, ts, (to + 1) & 0xFFFF, true) end
          end
        elseif first and initial_caps ~= 0 then
          first = false
          si = math.max(initial_caps, capitals(m, s, (o + 0x21B) & 0xFFFF))
          capital(m, s, (o + 0x243) & 0xFFFF, si > 1)
          local ts, to = ptr(0x98)
          local suppressed = (marker == 0x3D or marker == 0x25) and leading_upper(0x12) and
            runtime.is_upper_cyrillic(m:u8(linear(ts, to)))
          si = suppressed and 0 or math.max(initial_caps, capitals(m, s, (o + 0x12) & 0xFFFF))
          cap_translation(si > 1, si <= 1)
        else
          local ts, to = ptr(0x98)
          local suppressed = (marker == 0x3D or marker == 0x25) and leading_upper(0x12) and
            runtime.is_upper_cyrillic(m:u8(linear(ts, to)))
          si = suppressed and 0 or capitals(m, s, (o + 0x21B) & 0xFFFF)
          if leading_upper(0x21B) then capital(m, s, (o + 0x243) & 0xFFFF, false) end
          if si > 1 then capital(m, s, (o + 0x244) & 0xFFFF, true) end
          si = suppressed and 0 or capitals(m, s, (o + 0x12) & 0xFFFF)
          if leading_upper(0x12) then cap_translation(false) end
          if si > 1 then ts, to = ptr(0x98); capital(m, ts, (to + 1) & 0xFFFF, true) end
        end
      end
      if b(0x0B) > 1 then
        local text = textat(m, p + 0x98)
        if text ~= '' then
          local c = text:byte(1)
          if b(0x0D) == 0 and c ~= 0x2C and c ~= 0x3A then emit(m:cstring(m.ds, 0x5F7)) end
          emit(str(0x243))
          if c == 0x2C then
            assert(previous, 'output reads an uninitialized previous record')
            if m:u8(previous + 0x0E) == 0x44 and (m:u8(previous + 0x0D) == 0x2A or
              m:u8(previous + 0x0C) == 0x28 or m:u8(previous + 0x12) == 0x2C) then
              m:set16(p + 0x98, m:u16(p + 0x98) + (m:u8(previous + 0x12) == 0x2C and 1 or 2))
            end
          end
          emit(textat(m, p + 0x98))
          local as, ao = ptr(0x8F)
          if m:u16(ds + 0xBBB6) ~= 0 and not null(as, ao) then
            if m:u16(ds + 0xBBB4) ~= 0 or m:u16(ds + 0xBBBA) ~= 0 then
              emit(m:cstring(m.ds, 0x45C) .. string.format(m:cstring(m.ds, 0x5F9), (m:u16(ds + 0x042B) + count) & 0xFFFF))
              count = count + 1
            else emit(m:cstring(m.ds, 0x5FD)) end
            while not null(as, ao) do
              local ap = linear(as, ao)
              emit(output.reading(m, textat(m, ap + 0x98)))
              as, ao = m:far(ap + 0x8F)
              if not null(as, ao) then emit(m:cstring(m.ds, 0x5FF)) end
            end
            emit(m:cstring(m.ds, 0x601))
          end
        end
      else
        if b(0x0D) == 0 then emit(m:cstring(m.ds, 0x603)) end
        emit(b(0x0C) == 0x23 and str(0x243):find('-', 1, true) and str(0x243) or str(0x21B))
        if b(0x66) == 0x23 and b(0x12) ~= 0 then
          local as, ao = m:strrchr(s, (o + 0x12) & 0xFFFF, 0x27)
          if not null(as, ao) then
            local c = m:u8(linear(as, (ao + 1) & 0xFFFF))
            if c == 0x73 or c == 0x53 then m:set8(linear(as, ao), 0) end
          end
        end
        emit(str(0x12))
      end
    end
    previous = p
    s, o = m:far(p)
  end
  return count
end

function output.meanings(m, s, o, os, oo)
  if m:strlen(os, oo) >= 0xEFD then return end
  local wrapped = m:u16(linear(m.ds, 0xBB92)) ~= 0
  local count = 0
  while true do
    s, o = m:far(linear(s, o))
    if null(s, o) then break end
    local p = linear(s, o)
    local as, ao = m:far(p + 0x8F)
    local ms, mo = m:far(p + 0x8B)
    if m:u8(p + 0x0E) == 0x57 and (not null(as, ao) or not null(ms, mo)) then
      local source = m:cstring(s, (o + 0x12) & 0xFFFF):gsub('[A-Z]', string.lower)
      local number = (m:u16(linear(m.ds, 0x042B)) + count) & 0xFFFF
      if number >= 0x8000 then number = number - 0x10000 end
      local header = string.format(m:cstring(m.ds, 0x5CE), number, source)
      append(m, os, oo, header)
      local indent = #header - 1
      local spacer = ';\n' .. string.rep(' ', indent)
      for _, c in ipairs({0x2C, 0x20}) do
        local ts, to = m:far(p + 0x98)
        if m:u8(linear(ts, to)) == c then m:set16(p + 0x98, to + 1) end
      end
      local value = textat(m, p + 0x98)
      local pending = not null(ms, mo) and string.format(m:cstring(m.ds, 0x5D9), m:cstring(ms, mo), value) or
        string.format(m:cstring(m.ds, 0x5E1), value)
      if not wrapped then append(m, os, oo, pending) end
      while not null(as, ao) do
        local ap = linear(as, ao)
        local scratch
        value, scratch = output.reading(m, textat(m, ap + 0x98))
        -- Native W expansion reuses the stack buffer holding indentation.
        if scratch then spacer = scratch end
        ms, mo = m:far(ap + 0x8B)
        local entry = not null(ms, mo) and string.format(m:cstring(m.ds, 0x5E6), m:cstring(ms, mo), value) or
          string.format(m:cstring(m.ds, 0x5F0), value)
        if not wrapped then append(m, os, oo, entry)
        elseif indent + #pending + #entry >= m:s16(linear(m.ds, 0xBBA6)) or indent + #pending + #entry >= 0x80 then
          append(m, os, oo, pending); append(m, os, oo, spacer)
          pending = entry:sub(3)
        else pending = pending .. entry end
        as, ao = m:far(ap + 0x8F)
      end
      if wrapped then append(m, os, oo, pending) end
      count = count + 1
    end
  end
end
return output
