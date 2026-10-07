local matching = {}
local delimiters = '`~<[!'
local function has(s, c) return c ~= '' and s:find(c, 1, true) ~= nil end
local function upper(s) return (s:gsub('[a-z]', string.upper)) end
local function field(node, offset) return node and node[offset] or '' end
local function word(node, value)
  return upper(field(node, 0x12)) == upper(value) or field(node, 0x9C) == value
end
local function plain_run(pattern, p)
  while has(delimiters, pattern:sub(p, p)) do p = p + 1 end
  local first = p
  while p <= #pattern and not has(delimiters, pattern:sub(p, p)) do p = p + 1 end
  return pattern:sub(first, p - 1)
end

-- One pattern interpreter; views keep live tags separate from cached spans.
local function match_pattern(pattern, start, view)
  local lexical = view.word ~= nil
  local function run(i, p)
    local neg = false
    local function read_until(stops)
      local first = p
      while p <= #pattern and not has(stops, pattern:sub(p, p)) do p = p + 1 end
      return pattern:sub(first, p - 1)
    end
    local function alternatives()
      if lexical then
        assert(not has('`!', pattern:sub(p, p)), 'embedded lexical alternatives are not ported')
      elseif view.skip_alternatives then
        local count = 0
        while pattern:sub(p, p) == '`' and count < 10 do
          p = p + 1
          read_until('`')
          if p > #pattern then return false end
          p, count = p + 2, count + 1
        end
      end
      return true
    end
    local function member(set, tag)
      return view.null_matches and tag == '\0' or has(set, tag)
    end
    while p <= #pattern do
      local c = pattern:sub(p, p)
      if c == '~' then neg = true
      elseif c == '.' and not lexical then i = i + 1
      elseif c == '[' then
        p = p + 1
        local classes = read_until(lexical and ']`!' or ']`')
        if not lexical and p > #pattern then return 0 end
        if not alternatives() then return 0 end
        if lexical and classes == '$' then
          i = i + 1
        else
          if classes ~= '' and member(classes, view.tag(i)) == neg then return 0 end
          i, neg = i + 1, false
        end
      elseif lexical and (c == '`' or c == '!') then
        p = p + 1
        local value = read_until(c)
        if p > #pattern then return 0 end
        local ok = c == '`' and view.word(i, value) or c == '!' and view.text(i, value .. ')')
        if ok == neg then return 0 end
        i, neg = i + 1, false
      elseif c == '<' then
        p = p + 1
        local classes = read_until(lexical and '>`!' or '>`')
        if p > #pattern or not alternatives() then return 0 end
        local cache = view.cache(i)
        local anchor, width = nil, 1
        local next_c = pattern:sub(p + 1, p + 1)
        if next_c == '[' or lexical and has('`!', next_c) then
          p = p + 2
          local sought = read_until(lexical and ']`!' or ']`')
          if p > #pattern then return 0 end
          local close = pattern:sub(p, p)
          if close == '!' then sought = sought .. ')' end
          p = p - 1
          for offset = 0, #cache - 1 do
            local hit = lexical and close == '`' and view.word(i + offset, sought)
              or lexical and close == '!' and view.text(i + offset, sought)
              or (not lexical or close == ']') and has(sought, cache:sub(offset + 1, offset + 1))
            if hit then anchor = offset; break end
          end
        else
          local sought = view.token and view.token(p + 1) or plain_run(pattern, p + 1)
          local found = cache:find(sought, 1, true)
          anchor, width = found and found - 1, #sought
        end
        if not anchor then return 0 end
        if anchor == 0 then
          if neg then return 0 end
        else
          if classes:sub(1, 1) ~= '$' and classes ~= '' then
            for offset = 1, anchor do
              if has(classes, cache:sub(offset, offset)) == neg then return 0 end
            end
          end
          neg = false
        end
        i, p = i + anchor + width, p + width
      elseif lexical and c == '$' then
        local result = run(i, p + 1)
        if result ~= 0 then return result end
        i = i + 1
      else
        if (view.tag(i) == c) == neg then return 0 end
        i, neg = i + 1, false
      end
      p = p + 1
    end
    return (i - 1) & 0xFFFF
  end
  return run(start, 1)
end

function matching.match(vector, start, pattern, cached_tags)
  if not cached_tags then
    local tags, i = {}, 0
    while vector[i] do tags[#tags + 1] = string.char(vector[i][0x0C] or 0); i = i + 1 end
    cached_tags = table.concat(tags)
  end
  return match_pattern(pattern, start, {
    tag = function(i) return string.char(assert(vector[i], 'native matcher read beyond lexical vector')[0x0C] or 0) end,
    cache = function(i) return cached_tags:sub(i + 1) end,
    word = function(i, value) return word(vector[i], value) end,
    text = function(i, value) return has(field(vector[i], 0x11C), value) end,
  })
end

function matching.match_constituents(tags, start, pattern, current_tags)
  assert(not pattern:find('`', 1, true), 'T8 embedded lexical alternatives are not ported')
  current_tags = current_tags or tags
  return match_pattern(pattern, start, {
    tag = function(i) return current_tags:sub(i + 1, i + 1) end,
    cache = function(i) return tags:sub(i + 1) end,
  })
end

-- Post-grammar matching permits the sentinel tag and keeps cached spans
-- independent of live tags. Tokenization is local to each pattern.
function matching.words(vector, start, pattern, tags)
  return match_pattern(pattern, start, {
    null_matches = true,
    tag = function(i) return string.char(vector[i] and vector[i][0x0C] or 0) end,
    cache = function(i) return tags:sub(i + 1) end,
    word = function(i, value) return word(vector[i], value) end,
    text = function(i, value) return has(field(vector[i], 0x11C), value) end,
  })
end

function matching.constituents(state, start, pattern)
  return match_pattern(pattern, start, {
    null_matches = true, skip_alternatives = true,
    tag = function(i) return string.char(state.elements[i] and state.elements[i].tag or 0) end,
    cache = function(i)
      local chars = {}
      while state.tags[i] and state.tags[i] ~= 0 do
        chars[#chars + 1] = string.char(state.tags[i]); i = i + 1
      end
      return table.concat(chars)
    end,
  })
end

local function russian(byte) return byte and ((byte > 0x7F and byte < 0xB0) or (byte > 0xDF and byte < 0xF2)) end

function matching.replace(vector, first, last, pattern, action, state)
  if not action then return 0 end
  if not state then
    local tags, j = {}, 0
    while vector[j] do tags[#tags + 1] = string.char(vector[j][0x0C]); j = j + 1 end
    state = {tags = table.concat(tags)}
  end
  local i, p, a, removed = first, 1, 1, 0
  local function change(c)
    local node = assert(vector[i], 'native replacement read beyond lexical vector')
    node[0x66], node[0x0C] = node[0x0C], c:byte()
    state.tags = state.tags:sub(1, i) .. c .. state.tags:sub(i + 2)
  end
  local function literal()
    a = a + 1
    local c = action:sub(a, a)
    if c == '?' or c == '@' then a = a + 1
    elseif not russian(action:byte(a)) then change(c); a = a + 1 end
    local start = a
    while a <= #action and action:sub(a, a) ~= '`' and a - start < 80 do a = a + 1 end
    vector[i][0x11C] = action:sub(start, a - 1)
  end
  local function skip_pattern(stops)
    while p <= #pattern and not has(stops, pattern:sub(p, p)) do p = p + 1 end
  end
  local function ordinary_pattern()
    if pattern:sub(p, p) == '~' then p = p + 1 end
    local c = pattern:sub(p, p)
    if c == '[' then skip_pattern(']')
    elseif c == '`' or c == '!' then p = p + 1; skip_pattern(c) end
  end
  while a <= #action and i <= last and vector[i] do
    local c = action:sub(a, a)
    if c == '$' then
      skip_pattern('>$')
      if p > #pattern then return removed end
      if pattern:sub(p + 1, p + 1) == '>' then p = p + 1 end
      local next_c = pattern:sub(p + 1, p + 1)
      if has('[`!', next_c) then
        p = p + 2
        local start = p
        skip_pattern(']`!')
        if p > #pattern then return removed end
        local sought, close = pattern:sub(start, p - 1), pattern:sub(p, p)
        if close == '!' then sought = sought .. ')' end
        local found
        for j = i, last do
          local node = vector[j]
          local cached = state.tags:sub(j + 1, j + 1)
          if cached == '' or cached == '\0' then break end
          local ok = (close == '`' and word(node, sought))
            or (close == '!' and (node[0x11C] or ''):find(sought, 1, true))
            or (close == ']' and has(sought, cached))
          if ok then found = j; break end
        end
        if not found then return removed end
        -- Native consumes the anchor's pattern but leaves its node for the next action.
        i = found
      else
        local q = p + 1
        while has(delimiters, pattern:sub(q, q)) do q = q + 1 end
        local start = q
        while q <= #pattern and not has(delimiters, pattern:sub(q, q)) do q = q + 1 end
        local sought = pattern:sub(start, q - 1)
        if sought ~= '' then
          local found = state.tags:sub(i + 1):find(sought, 1, true)
          if not found then return removed end
          i = i + found - 1
          for _ = 1, #sought do
            if a > #action then break end
            a = a + 1
            if a > #action then return removed end
            local instruction = action:sub(a, a)
            if instruction == ' ' then removed = 1 end
            if instruction == '`' then
              literal() -- Unlike an ordinary literal, this native branch does not advance i.
            elseif instruction ~= '@' then
              change(instruction); i = i + 1
            end -- Native @ in a plain run also leaves i unchanged.
          end
          p = p + #sought
        end
      end
    elseif c == '.' then
      if pattern:sub(p, p) == '~' then p = p + 1 end
      if pattern:sub(p, p) == '[' then
        skip_pattern(']')
        if p > #pattern then return removed end
      end
      i = i + 1
    else
      if c == ' ' then removed = 1 end
      if c == '`' then literal()
      elseif c ~= '@' then change(c) end
      i = i + 1
      ordinary_pattern()
    end
    if p <= #pattern then p = p + 1 end
    if a <= #action then a = a + 1 end
  end
  return removed
end

return matching
