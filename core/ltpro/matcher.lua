-- LTPRO 1313:0A67 (file 0x17597): lexical-vector matcher, with zero-based indices.
-- Nodes retain native offsets: current tag +0C, lexical strings +12/+9C, text +11C.
-- Boundary '*' is a real node. This module does not interpret packed Lua readings.
local matcher = {}
local delimiters = '`~<[!'
local function has(s, c) return c ~= '' and s:find(c, 1, true) ~= nil end
local function upper(s) return (s:gsub('[a-z]', string.upper)) end
local function field(node, offset) return node and node[offset] or '' end
local function word(node, value)
  return upper(field(node, 0x12)) == upper(value) or field(node, 0x9C) == value
end
local function text(node, value) return field(node, 0x11C):find(value, 1, true) ~= nil end
local function tag(vector, i)
  local node = assert(vector[i], 'native matcher read beyond lexical vector')
  return string.char(node[0x0C] or 0)
end

-- The original strtok-like helper skips delimiters then copies one plain-tag run.
local function plain_run(pattern, p)
  while has(delimiters, pattern:sub(p, p)) do p = p + 1 end
  local start = p
  while p <= #pattern and not has(delimiters, pattern:sub(p, p)) do p = p + 1 end
  return pattern:sub(start, p - 1)
end

function matcher.match(vector, start, pattern, cached_tags)
  local tags, index = {}, 0
  while vector[index] do tags[#tags + 1] = tag(vector, index); index = index + 1 end
  -- Native span searches use DS:C5AE, which can differ from node +0C. Callers
  -- reproducing intermediate handler state must pass that cache independently.
  local tag_string = cached_tags or table.concat(tags)
  local function run(start_at, from)
    local i, p, neg = start_at, from, false
    local function read_until(stops)
      local first = p
      while p <= #pattern and not has(stops, pattern:sub(p, p)) do p = p + 1 end
      return pattern:sub(first, p - 1)
    end
    local function no_embedded_literals()
      -- No recovered rule uses these paths. Native class alternatives read an
      -- uninitialized spare slot; span alternatives can overrun the requested span.
      -- Refuse this extension until those caller/stack dependencies are modeled.
      assert(not has('`!', pattern:sub(p, p)), 'embedded lexical alternatives are not ported')
    end
    while p <= #pattern do
      local c = pattern:sub(p, p)
      if c == '~' then
        neg = true
      elseif c == '[' then
        p = p + 1
        local classes = read_until(']`!')
        no_embedded_literals()
        if classes == '$' then
          i = i + 1 -- [$] bypasses the predicate and does not clear native negation.
        else
          local class_ok = classes == '' or has(classes, tag(vector, i))
          if neg then
            if classes ~= '' and has(classes, tag(vector, i)) then return 0 end
          elseif not class_ok then return 0 end
          i, neg = i + 1, false
        end
      elseif c == '`' or c == '!' then
        p = p + 1
        local value = read_until(c)
        if p > #pattern then return 0 end
        local ok = c == '`' and word(vector[i], value) or c == '!' and text(vector[i], value .. ')')
        if ok == neg then return 0 end
        i, neg = i + 1, false
      elseif c == '<' then
        local span_start = i
        p = p + 1
        local classes = read_until('>`!')
        if p > #pattern then return 0 end
        no_embedded_literals()
        local next_c, anchor, length = pattern:sub(p + 1, p + 1), nil, 1
        if has('[`!', next_c) then
          p = p + 2
          local sought = read_until(']`!')
          if p > #pattern then return 0 end
          local close = pattern:sub(p, p)
          if close == '!' then sought = sought .. ')' end
          p = p - 1
          for j = i, #tag_string - 1 do
            local ok = (close == '`' and word(vector[j], sought))
              or (close == '!' and text(vector[j], sought))
              or (close == ']' and has(sought, tag_string:sub(j + 1, j + 1)))
            if ok then anchor = j; break end
          end
        else
          local sought = plain_run(pattern, p + 1)
          local found = tag_string:find(sought, i + 1, true)
          anchor, length = found and found - 1, #sought
        end
        if not anchor then return 0 end
        if anchor == i then
          -- A negated span rejects an empty match, even when <$>-style skipping
          -- would otherwise bypass its predicate. There is no regex backtracking.
          if neg then return 0 end
        elseif classes:sub(1, 1) ~= '$' then
          for j = i, anchor - 1 do
            local hit = has(classes, tag_string:sub(j + 1, j + 1))
            if classes ~= '' and hit == neg then return 0 end
          end
        end
        i, p = anchor + length, p + length
        if anchor ~= span_start then neg = false end
      elseif c == '$' then
        -- Native '$' first tries the tail here; on failure it skips one node and
        -- continues the tail once. It is not an arbitrary-length regex wildcard.
        local result = run(i, p + 1)
        if result ~= 0 then return result end
        i = i + 1
      else
        if (tag(vector, i) == c) == neg then return 0 end
        i, neg = i + 1, false
      end
      p = p + 1
    end
    return (i - 1) & 0xFFFF
  end
  return run(start, 1)
end

return matcher
