local text = require 'core.text'
local russian = {}

function russian.from_bytes(bytes, overlay)
  local entries = {}
  local function ingest(image)
    assert(image:sub(1,20) == 'LTech DIC File 2.00 ', 'unsupported BASE.RUS header')
    local finish = string.unpack('<I4', image, 0x1F)
    assert(string.unpack('<I4',image,0x23) == #image, 'BASE.RUS header length does not match asset')
    assert(finish >= 0x28 and finish + 32*33*4 == #image and string.unpack('<I2',image,0x1D) == 32,
      'BASE.RUS does not contain the expected 32x33 index tail')
    for line in image:sub(0x29,finish):gmatch('[^\n]+') do
      local key = line:match('^(.-)%*')
      if key then
        entries[key] = entries[key] or {}
        entries[key][#entries[key]+1] = line
      end
    end
  end
  ingest(bytes)
  if overlay then ingest(overlay) end
  return {entries=entries}
end

-- The .RUS verb record: V, flags, government, paradigm, 0, partner lemma.
function russian.verb_record(state, word)
  local line = russian.lookup(state, word, 0, 'V')
  if not line then return nil end
  local code = line:match('%*(.*)') or ''
  local partner = code:sub(6)
  return {perfective = (code:byte(2) or 0) & 0x06 ~= 0, paradigm = (code:byte(4) or 0) & 0x7F,
    partner = partner ~= '' and partner or nil}
end
-- Whether the lemma has a verb of this aspect: the .RUS verb record's byte 2
-- carries the perfective flags (0x04 forced, 0x02 native), and an
-- imperfective lists its perfective partner after the code.
function russian.has_verb_aspect(state, word, aspect)
  local line=russian.lookup(state, word, 0, 'V')
  if not line then return false end
  local code=line:match('%*(.*)') or ''
  local perfective=(code:byte(2) or 0) & 0x06 ~= 0
  if aspect==1 then return perfective or #code>5 end
  return not perfective
end

-- Dictionary lines are immutable strings; no shared read buffer or DOS handles.
-- A lemma can be both a noun and a verb (помочь), so callers that know the
-- class ask for it; without a match the first record is returned as before.
local function lower_initial(s)
  local b = s:byte()
  if not b then return s end
  if b == 0xF0 then b = 0xF1 elseif b >= 0x80 and b <= 0x8F then b = b + 0x20 elseif b >= 0x90 and b <= 0x9F then b = b + 0x50 else return s end
  return string.char(b) .. s:sub(2)
end
function russian.lookup(state, key, prefix, class)
  local base = key:match('^(.-)%*') or key
  local wanted = key .. (prefix == 0 and '*' or '')
  -- Records are keyed lowercase (LTGOLD: новый under "нов"); a capitalized
  -- lemma inside a composite (Новый год) is looked up the same way.
  if not state.russian.entries[base] and lower_initial(base) ~= base then
    base, wanted = lower_initial(base), lower_initial(wanted)
  end
  local first
  for _, line in ipairs(state.russian.entries[base] or {}) do
    local code=line:byte(#wanted+1)
    if line:sub(1,#wanted) == wanted and code ~= 0x51 and code ~= 0x4D then
      if not class or code == class:byte() then return line end
      first = first or line
    end
  end
  return first
end

local function tables(class, variant)
  -- The ending list for a class, from the two native switches.
  if class == 0x01 or class == 0x4E then
    if variant == 1 then return 'endings_noun_m' end
    if variant == 2 then return 'endings_noun_f' end
    if variant == 0 then return 'endings_noun_n' end
    return 'endings_noun_m'
  end
  if class == 0x02 or class == 0x05 or class == 0x06 or class == 0x07 or class == 0x41 or class == 0x49 then
    return 'endings_adjective'
  end
  if class == 0x03 or class == 0x45 or class == 0x46 or class == 0x47 or class == 0x56 or class == 0x76 then
    if variant == 1 then return 'endings_verb_perfective' end
    if variant == 0x67 or variant == 0x6E or variant == 0xA3 then return 'endings_replacement' end
    return 'endings_verb_imperfective'
  end
  return nil
end

local function tokens(value, first, rest)
  local list, i, delimiters = {}, 1, first
  while true do
    while i <= #value and delimiters:find(value:sub(i,i),1,true) do i=i+1 end
    if i > #value then break end
    local j=i
    while j <= #value and not delimiters:find(value:sub(j,j),1,true) do j=j+1 end
    list[#list+1]=value:sub(i,j-1); i=j+1; delimiters=rest
  end
  return list
end

function russian.ending_matches(state, word, class, variant)
  local a, length = state.assets, #word
  local list_name = tables(class, variant)
  if (class == 3 or class == 0x45 or class == 0x46 or class == 0x47 or class == 0x56 or class == 0x76) and length > 2 then
    local reflexive=a:list('reflexive')
    if text.ends(word,reflexive[0]) or text.ends(word,reflexive[1]) then length=length-2 end
  end
  local matches = {}
  if list_name then
    local list = a:list(list_name)
    for id=0,#list do
      for _, suffix in ipairs(tokens(list[id],a:string('space'),a:string('space'))) do
        if #suffix > 0 and text.ends(word,suffix,length) then matches[#matches+1]={length=#suffix,id=id} end
      end
    end
  end
  return matches
end

-- Preserve the original ordering of equal-length suffix candidates, expressed
-- as a sort of Lua objects rather than swaps in a byte-addressed array.
local function exchange(items, a, b) items[a],items[b]=items[b],items[a] end
local function compare(items,a,b) return items[b].length-items[a].length end
local function sort(items, pivot, count)
  local width = 1
  while true do
    if count <= 2 then
      if count == 2 then
        local right = (pivot + width)
        if compare(items, pivot, right) > 0 then exchange(items, pivot, right) end
      end
      return
    end
    local right = (pivot + (count - 1) * width)
    local left = (pivot + (count >> 1) * width)
    -- Median of three.
    if compare(items, left, right) > 0 then exchange(items, left, right) end
    if compare(items, left, pivot) > 0 then exchange(items, left, pivot)
    elseif compare(items, pivot, right) > 0 then exchange(items, pivot, right) end
    if count == 3 then exchange(items, pivot, left); return end
    left = (pivot + width)
    local pivot_end = left
    local broke = false
    repeat
      local result = compare(items, left, pivot)
      while result <= 0 do
        if result == 0 then
          exchange(items, left, pivot_end)
          pivot_end = (pivot_end + width)
        end
        if left < right then left = (left + width)
        else broke = true; break end
        result = compare(items, left, pivot)
      end
      if broke then break end
      while left < right do
        result = compare(items, pivot, right)
        if result < 0 then
          right = (right - width)
        else
          exchange(items, left, right)
          if result ~= 0 then
            left = (left + width)
            right = (right - width)
          end
          break
        end
      end
    until not (left < right)
    if compare(items, left, pivot) <= 0 then left = (left + width) end
    local low, pivot_temp = (left - width), pivot
    while pivot_temp < pivot_end and low >= pivot_end do
      exchange(items, pivot_temp, low)
      pivot_temp = (pivot_temp + width)
      low = (low - width)
    end
    local function quotient(a) return (a >= 0 and a // width or -((-a) // width)) end
    local left_count = quotient(left - pivot_end)
    local right_count = quotient(((pivot + count * width)) - left)
    if right_count < left_count then
      sort(items, left, right_count)
      count = left_count
    else
      sort(items, pivot, left_count)
      pivot, count = left, right_count
    end
  end
end

-- LTPRO's paradigm candidates for a lemma: the rows of the class table whose
-- ending list matches its end, longest ending first, in native order.
-- class: 0x4E noun (variant: gender 1 m, 2 f, 0 n), 0x41 adjective,
-- 0x56 verb (variant 1 perfective).
function russian.paradigm_candidates(state, word, class, variant)
  local matches = russian.ending_matches(state, word, class, variant)
  sort(matches,1,#matches)
  local ids = {}
  for i, m in ipairs(matches) do ids[i] = m.id end
  return ids
end

function russian.replace_ending(state, word)
  local matches = russian.ending_matches(state, word, 3, 0x6E)
  if #matches == 0 then return nil end
  sort(matches,1,#matches)
  local cut, ending = state.assets:paradigm('replacement',matches[1].id)
  if ending == '' or ending:sub(1,1) == '-' then return nil end
  local keep = #word-cut
  local stem = keep > 0 and word:sub(1,keep) or word
  return stem .. (ending:sub(1,1) == '=' and '' or ending)
end
return russian
