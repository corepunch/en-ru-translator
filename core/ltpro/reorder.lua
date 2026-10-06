-- Port of LTPRO 1279:000D (file 0x1619D), operating on original-shaped lexical nodes.
-- The native +98 text pointer addresses the record's own +11C translation.
local nodes = require "core.ltpro.nodes"
local rules = require "core.rules"
local reorder = {}
local byte = nodes.byte

local handlers = {
  [1] = function(v, first, last)
    return not (byte(v[first], 0x0F) == 0x77 and byte(v[last], 0x0F) == 0x77)
  end,
  [2] = function(v, first, last)
    v[last][0x0C] = 0x41
    return true
  end,
  [3] = function(v, first, last)
    local prior = byte(v[first - 1], 0x0C)
    return byte(v[first], 0x66) ~= 0x45 and
      prior ~= 0x44 and prior ~= 0x48 and prior ~= 0x2C and prior ~= 0x26 and
      not (byte(v[last], 0x0F) == 0x77 and byte(v[first + 1], 0x0F) == 0x77)
  end,
  [4] = function(v, first)
    return not assert(v[first][0x11C], "missing native lexical text"):find("P", 1, true)
  end,
  [5] = function(v, first)
    if assert(v[first + 1][0x11C], "missing native lexical text") == "-" then
      v[first + 1][0x0C] = 0x2D
      return false
    end
    return true
  end,
  [6] = function(v, first, last) return byte(v[last], 0x72) ~= 0 end,
  [7] = function(v, first, last) return byte(v[last], 0x0F) == 0x72 end,
  [8] = function(v, first)
    -- CP866 "мес)" at DS:43DB; strstr, not an English-source-word special case.
    return assert(v[first][0x11C], "missing native lexical text"):find("\xAC\xA5\xE1)", 1, true) ~= nil
  end,
  [9] = function(v, first, last)
    return byte(v[last], 0x0F) == 0x77 or byte(v[last - 1], 0x0F) == 0x77
  end,
  [10] = function(v, first)
    return not assert(v[first + 1][0x11C], "missing native lexical text"):find("P", 1, true)
  end,
  [11] = function(v, first, last) return byte(v[last], 0x0F) ~= 0x77 end,
  [12] = function(v, first) return first <= 5 end,
  [97] = function(v, first, last) return byte(v[last], 0x0F) == 0x61 end,
}

function reorder.matches(vector, first, pattern)
  -- 1313:07FD compares resolved tags literally; brackets and W alternatives are not expanded.
  for i = 1, #pattern do
    if byte(vector[first + i - 1], 0x0C) ~= pattern:byte(i) then return false end
  end
  return true
end

function reorder.allowed(vector, first, last, handler)
  local apply = handlers[handler]
  return not apply or apply(vector, first, last)
end

function reorder.swaps(vector, first, digits)
  for i = 1, #digits do
    local a, b = first + i - 1, first + digits:byte(i) - 0x31
    assert(vector[a] and vector[b] and b >= first, "numeric action outside native vector")
    if a ~= b then
      nodes.swap(vector[a - 1], vector[a], vector[b - 1], vector[b])
      vector[a], vector[b] = vector[b], vector[a]
    end
  end
end

local function eligible(v, first)
  local kind = byte(v[first], 0x0F)
  local next_kind = byte(v[first + 1], 0x0F)
  local prior = byte(v[first - 1], 0x0C)
  return kind ~= 0x67 and kind ~= 0x2F and
    ((kind ~= 0x25 and kind ~= 0x3D) or (byte(v[first], 0x76) & 2) ~= 0) and
    next_kind ~= 0x25 and next_kind ~= 0x3D and v[first + 2] ~= nil and
    byte(v[first + 2], 0x0F) ~= 0x3D and prior ~= 0x44 and prior ~= 0x2D
end

function reorder.apply(root, tables)
  tables = tables or { rules[5], rules[6] }
  local vector, count = nodes.vector(root)
  local first = 1
  while first < count - 1 do
    local consumed = 1
    if eligible(vector, first) then
      local applied = false
      for _, block in ipairs(tables) do
        for _, rule in ipairs(block) do
          local handler, pattern, digits = table.unpack(rule)
          local last = first + #pattern - 1
          if reorder.matches(vector, first, pattern) and vector[last + 1] and
             byte(vector[last + 1], 0x0C) ~= 0x2F and byte(vector[last + 1], 0x0C) ~= 0x2D and
             not (byte(vector[first], 0x0F) == 0x77 and byte(vector[first + 1], 0x0C) == 0x2D) and
             reorder.allowed(vector, first, last, handler) then
            reorder.swaps(vector, first, digits or "")
            if handler == 0x2D then
              for i = first, last do
                if byte(vector[i], 0x0C) == 0x2D and byte(vector[i], 0x0F) == 0x2F then
                  vector[i][0x0C] = 0x20
                end
              end
            end
            consumed, applied = #pattern, true
            break
          end
        end
        if applied then break end
      end
    end
    first = first + consumed
  end
  -- The pass removes determiners after all reorder rules, then compacts the linked stream.
  for i = 1, count - 1 do
    if vector[i][0x0C] == 0x54 then vector[i][0x0C] = 0x20 end
  end
  -- Native rebuilds its vector, count and tag cache only when a record was
  -- blanked; otherwise DS:C5AE and DS:C7B1 keep their pre-reorder values
  -- although the linked records are already swapped. The third result says
  -- whether that rebuild happened.
  local rebuilt = false
  for i = 0, count - 1 do
    if vector[i][0x0C] == 0x20 then rebuilt = true end
  end
  local compacted, compacted_count = nodes.vector(root)
  return compacted, compacted_count, rebuilt
end

return reorder
