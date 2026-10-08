local text = require 'core.text'
local russian = {}

function russian.from_bytes(bytes, overlay)
  local entries, source_forms, openrussian_forms, openrussian_rows = {}, {}, {}, {}
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
        local payload=line:match('^.-%*(O\t.*)$')
        if payload then
          local fields={}
          for field in (payload..'\t'):gmatch('(.-)\t') do
            local name,value=field:match('^([^=]+)=(.*)$')
            if name then fields[name]=value end
          end
          local pos=key:match('^@([nva])')
          local metadata=pos=='n' and fields.gender or fields.aspect
          if pos and fields.bare and metadata then
            local row={id=key:sub(3),pos=pos,lemma=fields.bare,metadata=metadata,columns=fields,forms={}}
            for slot,values in pairs(fields) do
              if slot:match('^sg_') or slot:match('^pl_') or slot:match('^imperative_') or
                 slot:match('^past_') or slot:match('^presfut_') or slot:match('^decl_') or
                 slot=='comparative' or slot=='superlative' or slot:match('^short_') then
                local forms={}
                for form in (values..','):gmatch('(.-),') do if form~='' then forms[#forms+1]=form end end
                row.forms[slot]=forms
              end
            end
            openrussian_rows[key]=row
            local by_pos=openrussian_forms[pos] or {};openrussian_forms[pos]=by_pos
            local by_lemma=by_pos[fields.bare] or {};by_pos[fields.bare]=by_lemma
            if pos=='v' then by_lemma[metadata=='perfective' and 'pf' or 'ipf']=row
            else by_pos[fields.bare]=row end
          end
        end
        local pos, aspect, slot, form = line:match('^.-%*Q(v)%*([^*]+)%*([^*]+)%*(.*)$')
        if not pos then pos, slot, form = line:match('^.-%*Q([na])%*([^*]+)%*(.*)$') end
        if pos then
          local folded = key:gsub(string.char(0xf0), string.char(0xa5))
          local by_pos = source_forms[key] or source_forms[folded] or {}
          source_forms[key], source_forms[folded] = by_pos, by_pos
          local by_slot = by_pos[pos]
          if aspect then
            local by_aspect = by_slot or {}
            by_pos[pos] = by_aspect
            by_slot = by_aspect[aspect] or {}
            by_aspect[aspect] = by_slot
          else by_slot = by_slot or {}; by_pos[pos] = by_slot end
          by_slot[slot] = by_slot[slot] or {}
          by_slot[slot][#by_slot[slot] + 1] = form
        end
      end
    end
  end
  ingest(bytes)
  if overlay then ingest(overlay) end
  return {entries=entries, source_forms=source_forms,openrussian_forms=openrussian_forms,openrussian_rows=openrussian_rows}
end

function russian.source_forms(state, word, pos, slot, aspect)
  local direct=state.russian.openrussian_forms and state.russian.openrussian_forms[pos]
  local row=direct and direct[word]
  if row and pos=='v' then row=row[aspect==1 and 'pf' or 'ipf'] end
  if row then
    local forms=row.forms[slot]
    if forms and #forms>0 then return forms end
  end
  local by_pos = state.russian.source_forms[word]
  if not by_pos then return nil end
  local forms = by_pos[pos]
  if not forms then return nil end
  if pos == 'v' then forms = forms[aspect == 1 and 'pf' or 'ipf'] end
  return forms and forms[slot] or nil
end

-- Dictionary lines are immutable strings; no shared read buffer or DOS handles.
function russian.lookup(state, key, prefix)
  local base = key:match('^(.-)%*') or key
  for _, line in ipairs(state.russian.entries[base] or {}) do
    local wanted = key .. (prefix == 0 and '*' or '')
    if line:sub(1,#wanted) == wanted and line:byte(#wanted + 1) ~= 0x51 then return line end
  end
end

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
  local offset, count = tables(class, variant)
  if (class == 3 or class == 0x45 or class == 0x46 or class == 0x47 or class == 0x56 or class == 0x76) and length > 2 then
    if text.ends(word,a:indirect(0x630C)) or text.ends(word,a:indirect(0x6310)) then length=length-2 end
  end
  local matches = {}
  if offset then
    for id=0,count-1 do
      for _, suffix in ipairs(tokens(a:indirect(offset+id*4),a:string(0xB97F),a:string(0xB981))) do
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

function russian.replace_ending(state, word)
  local matches = russian.ending_matches(state, word, 3, 0x6E)
  if #matches == 0 then return nil end
  sort(matches,1,#matches)
  local cut, ending = state.assets:paradigm(0x61F2,matches[1].id)
  if ending == '' or ending:sub(1,1) == '-' then return nil end
  local keep = #word-cut
  local stem = keep > 0 and word:sub(1,keep) or word
  return stem .. (ending:sub(1,1) == '=' and '' or ending)
end
return russian
