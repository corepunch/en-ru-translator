-- LTPRO 1313:01B4 (file 0x16CE4): replace tags/text on native lexical nodes.
-- This deliberately preserves positional quirks; it is not lexical-form selection.
local replacement = {}
local delimiters = '`~<[!'
local function has(s, c) return c ~= '' and s:find(c, 1, true) ~= nil end
local function word(node, value)
  return (node[0x12] or ''):upper() == value:upper() or (node[0x9C] or '') == value
end
local function russian(byte) return byte and ((byte > 0x7F and byte < 0xB0) or (byte > 0xDF and byte < 0xF2)) end

function replacement.apply(vector, first, last, pattern, action, state)
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

return replacement
