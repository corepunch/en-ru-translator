local nodes = require 'core.nodes'
local rules = require "core.rules"

local reorder = {}

-- Port of LTPRO's reorder pass, operating on original-shaped lexical nodes.
-- The native +98 text pointer addresses the record's own +11C translation.
local number = nodes.number
local tag = nodes.tag

local function after_modifiers(vector, first, classes)
  while vector[first] and classes:find(tag(vector[first]), 1, true) do first = first + 1 end
  return first
end

local function has_noun(node)
  return node and (tag(node) == 'N' or tag(node) == 'Z' and
    (nodes.has_reading(node, 'N') or nodes.has_reading(node, 'n')))
end

local function possessive_form(node)
  -- Exact noun readings can already encode the genitive, as in john's*Nджона.
  if number(node, 'reading_state') < 2 or
    (number(node, 'case_mask') ~= 2 and tag(node) ~= 'N') then return false end
  return nodes.possessive_spelling(node)
end

function reorder.prepare_possessives(vector, count)
  for index = 1, count - 2 do
    local owner = vector[index]
    if possessive_form(owner) and has_noun(owner) then
      local head_index = after_modifiers(vector, index + 1, 'A')
      local head = vector[head_index]
      local modified = head_index > index + 1 or ('AO'):find(tag(vector[index - 1]), 1, true)
      -- The -'s/-s' suffix has already supplied the case and number.
      -- An ambiguous verb/noun head needs a modifier to resolve the group.
      if has_noun(head) and (tag(head) == 'N' or modified) then
        nodes.mark_possessive(owner)
      end
    end
  end
end

local function reverse(vector, first, last)
  while first < last do
    vector[first], vector[last] = vector[last], vector[first]
    first, last = first + 1, last - 1
  end
end

local function move_possessive(vector, first)
  local last = after_modifiers(vector, first, 'AOT')
  if not vector[last] or tag(vector[last]) ~= 'N' or not nodes.possessive(vector[last]) then return end
  local ends = {}
  while vector[last] and tag(vector[last]) == 'N' and nodes.possessive(vector[last]) do
    ends[#ends + 1] = last
    last = after_modifiers(vector, last + 1, 'A')
  end
  if not vector[last] or tag(vector[last]) ~= 'N' then return end

  -- Reverse the groups [owner ...] [head], keeping each group's modifiers.
  local initial = vector[first]
  if first == 1 and ('AO'):find(tag(initial), 1, true) and
    not initial.phrase_case and initial.source:match('^[A-Z][a-z]+$') then
    initial.phrase_case = {caps = 0}
  end
  local start, following = first, vector[last].next
  for _, finish in ipairs(ends) do
    reverse(vector, start, finish)
    start = finish + 1
  end
  reverse(vector, start, last)
  reverse(vector, first, last)
  for i = first - 1, last - 1 do vector[i].next = vector[i + 1] end
  vector[last].next = following
  return last - first + 1
end

local handlers = {
  [1] = function(v, first, last)
    return not (number(v[first], 'marker') == 0x77 and number(v[last], 'marker') == 0x77)
  end,
  [2] = function(v, first, last)
    v[last].tag = 0x41
    return true
  end,
  [3] = function(v, first, last)
    local prior = number(v[first - 1], 'tag')
    return number(v[first], 'previous_tag') ~= 0x45 and
      prior ~= 0x44 and prior ~= 0x48 and prior ~= 0x2C and prior ~= 0x26 and
      not (number(v[last], 'marker') == 0x77 and number(v[first + 1], 'marker') == 0x77)
  end,
  [4] = function(v, first)
    return not assert(v[first].reading, "missing native lexical text"):find("P", 1, true)
  end,
  [5] = function(v, first)
    if assert(v[first + 1].reading, "missing native lexical text") == "-" then
      v[first + 1].tag = 0x2D
      return false
    end
    return true
  end,
  [6] = function(v, first, last) return number(v[last], 'number') ~= 0 end,
  [7] = function(v, first, last) return number(v[last], 'marker') == 0x72 end,
  [8] = function(v, first)
    -- The month mark "мес)" by substring, not an English-source-word special case.
    return assert(v[first].reading, "missing native lexical text"):find("\xAC\xA5\xE1)", 1, true) ~= nil
  end,
  [9] = function(v, first, last)
    return number(v[last], 'marker') == 0x77 or number(v[last - 1], 'marker') == 0x77
  end,
  [10] = function(v, first)
    return not assert(v[first + 1].reading, "missing native lexical text"):find("P", 1, true)
  end,
  [11] = function(v, first, last) return number(v[last], 'marker') ~= 0x77 end,
  [12] = function(v, first) return first <= 5 end,
  [97] = function(v, first, last) return number(v[last], 'marker') == 0x61 end,
}

function reorder.matches(vector, first, pattern)
  -- LTPRO compares resolved tags literally; brackets and W alternatives are not expanded.
  for i = 1, #pattern do
    if number(vector[first + i - 1], 'tag') ~= pattern:byte(i) then return false end
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
  local kind = number(v[first], 'marker')
  local next_kind = number(v[first + 1], 'marker')
  local prior = number(v[first - 1], 'tag')
  return kind ~= 0x67 and kind ~= 0x2F and
    ((kind ~= 0x25 and kind ~= 0x3D) or (number(v[first], 'case_mask') & 2) ~= 0) and
    next_kind ~= 0x25 and next_kind ~= 0x3D and v[first + 2] ~= nil and
    number(v[first + 2], 'marker') ~= 0x3D and prior ~= 0x44 and prior ~= 0x2D
end

function reorder.apply(root, tables, possessives)
  tables = tables or { rules[5], rules[6] }
  local vector, count = nodes.vector(root)
  local first = 1
  while first < count - 1 do
    local grouped = possessives and move_possessive(vector, first)
    local consumed = grouped or 1
    if not grouped and eligible(vector, first) then
      local applied = false
      for _, block in ipairs(tables) do
        for _, rule in ipairs(block) do
          local handler, pattern, digits = table.unpack(rule)
          local last = first + #pattern - 1
          if reorder.matches(vector, first, pattern) and vector[last + 1] and
             number(vector[last + 1], 'tag') ~= 0x2F and number(vector[last + 1], 'tag') ~= 0x2D and
             not (number(vector[first], 'marker') == 0x77 and number(vector[first + 1], 'tag') == 0x2D) and
             reorder.allowed(vector, first, last, handler) then
            reorder.swaps(vector, first, digits or "")
            if handler == 0x2D then
              for i = first, last do
                if number(vector[i], 'tag') == 0x2D and number(vector[i], 'marker') == 0x2F then
                  vector[i].tag = 0x20
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
    if vector[i].tag == 0x54 then vector[i].tag = 0x20 end
  end
  -- Native rebuilds its vector, count and tag cache only when a record was
  -- blanked; otherwise LTPRO's counts keep their pre-reorder values
  -- although the linked records are already swapped. The third result says
  -- whether that rebuild happened.
  local rebuilt = false
  for i = 0, count - 1 do
    if vector[i].tag == 0x20 then rebuilt = true end
  end
  local compacted, compacted_count = nodes.vector(root)
  return compacted, compacted_count, rebuilt
end

function reorder.table_for(tag)
  local code = type(tag) == 'string' and tag:byte() or tag
  if code == 0x41 then return rules.adjective end
  if code and code >= 0 and code < 256 and ('#BEFGHILNOPQUVWbfk'):find(string.char(code), 1, true) then
    return rules[8]
  end
end
function reorder.endpoints(rule, first, last)
  if rule.endpoint_order ~= 0 then return last, first end
  return first, last
end

return reorder
