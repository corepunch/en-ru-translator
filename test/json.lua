-- Minimal JSON decoder for the captured LTPRO fixtures under test/ltpro.
return function(text)
  local i = 1
  local function space() i = text:find('[^ \t\r\n]', i) or #text + 1 end
  local value
  local function str()
    local parts = {}
    i = i + 1
    while true do
      local c = text:sub(i, i)
      if c == '"' then i = i + 1; return table.concat(parts) end
      if c == '\\' then
        local e = text:sub(i + 1, i + 1)
        if e == 'u' then
          parts[#parts + 1] = utf8.char(tonumber(text:sub(i + 2, i + 5), 16)); i = i + 6
        else
          parts[#parts + 1] = ({n = '\n', t = '\t', r = '\r', b = '\b', f = '\f'})[e] or e; i = i + 2
        end
      else parts[#parts + 1] = c; i = i + 1 end
    end
  end
  function value()
    space()
    local c = text:sub(i, i)
    if c == '{' then
      local result = {}; i = i + 1; space()
      if text:sub(i, i) == '}' then i = i + 1; return result end
      while true do
        space(); local key = str(); space(); i = i + 1
        result[key] = value(); space()
        local d = text:sub(i, i); i = i + 1
        if d == '}' then return result end
      end
    elseif c == '[' then
      local result = {}; i = i + 1; space()
      if text:sub(i, i) == ']' then i = i + 1; return result end
      while true do
        result[#result + 1] = value(); space()
        local d = text:sub(i, i); i = i + 1
        if d == ']' then return result end
      end
    elseif c == '"' then return str()
    elseif text:find('^true', i) then i = i + 4; return true
    elseif text:find('^false', i) then i = i + 5; return false
    elseif text:find('^null', i) then i = i + 4; return nil
    else
      local number = text:match('^-?[%d.eE+-]+', i); i = i + #number; return tonumber(number)
    end
  end
  return value()
end
