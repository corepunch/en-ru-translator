-- LTPRO 1C3D:0135 (file 0x1FF05): T8's distinct 12-byte constituent matcher.
-- Input is its cached tag string, not a lexical vector; indices remain zero-based.
local matcher = {}
local function has(s, c) return c ~= '' and s:find(c, 1, true) ~= nil end
function matcher.match(tags, start, pattern, current_tags)
  -- The original separately reads the 12-byte records and DS:C7B6 tag cache.
  current_tags = current_tags or tags
  -- No recovered T8 pattern contains embedded lexical alternatives. The original
  -- parses but does not test their word values; keep this unsupported form explicit.
  assert(not pattern:find('`', 1, true), 'T8 embedded lexical alternatives are not ported')
  local p, i, neg = 1, start, false
  local function read_class(close)
    local first = p
    while p <= #pattern and pattern:sub(p, p) ~= close do p = p + 1 end
    return pattern:sub(first, p - 1)
  end
  while p <= #pattern do
    local c = pattern:sub(p, p)
    if c == '~' then neg = true
    elseif c == '.' then i = i + 1 -- Unlike the lexical matcher, '.' accepts one node.
    elseif c == '[' then
      p = p + 1
      local classes = read_class(']')
      if p > #pattern then return 0 end
      if classes ~= '' and has(classes, current_tags:sub(i + 1, i + 1)) == neg then return 0 end
      i, neg = i + 1, false
    elseif c == '<' then
      p = p + 1
      local classes = read_class('>')
      if p > #pattern then return 0 end
      local span_start, anchor, length = i, nil, 1
      if pattern:sub(p + 1, p + 1) == '[' then
        p = p + 2
        local sought = read_class(']')
        if p > #pattern then return 0 end
        p = p - 1
        for j = i, #tags - 1 do
          if has(sought, tags:sub(j + 1, j + 1)) then anchor = j; break end
        end
      else
        local q = p + 1
        while has('`~<[!', pattern:sub(q, q)) do q = q + 1 end
        local first = q
        while q <= #pattern and not has('`~<[!', pattern:sub(q, q)) do q = q + 1 end
        local sought = pattern:sub(first, q - 1)
        local found = tags:find(sought, i + 1, true)
        anchor, length = found and found - 1, #sought
      end
      if not anchor then return 0 end
      if anchor == i then
        if neg then return 0 end
      elseif classes:sub(1, 1) ~= '$' and classes ~= '' then
        for j = i, anchor - 1 do
          if has(classes, tags:sub(j + 1, j + 1)) == neg then return 0 end
        end
      end
      i, p = anchor + length, p + length
      if anchor ~= span_start then neg = false end
    else
      if (current_tags:sub(i + 1, i + 1) == c) == neg then return 0 end
      i, neg = i + 1, false
    end
    p = p + 1
  end
  return (i - 1) & 0xFFFF
end
return matcher
