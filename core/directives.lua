local transliteration = require 'core.transliteration'
local directives = {}

-- Delimited spans remain one opaque lexical record. Positions are byte offsets
-- into the original CP866 input, including directive markers.
function directives.chunks(input)
  local chunks, cursor, previous_end = {}, 1, 0
  local function append(value, first, last, literal)
    chunks[#chunks + 1] = {text=value, position=first, literal=literal, joined=first == previous_end + 1 and #chunks > 0}
    previous_end = last
  end
  local function ordinary(first, last)
    for at, value in input:sub(first, last):gmatch('()([^%s]+)') do
      append(value, first + at - 1, first + at + #value - 2)
    end
  end
  while cursor <= #input do
    local start = input:find('{~', cursor, true)
    if not start then ordinary(cursor, #input); break end
    ordinary(cursor, start - 1)
    local content = start + 2
    local mode = input:sub(content, content)
    assert(mode ~= '\\', 'list directives are not supported; use delimited {~text~} or {~=text~} spans')
    if mode == '=' then content = content + 1 end
    local finish = assert(input:find('~}', content, true), 'unterminated inline directive')
    local value = input:sub(content, finish - 1)
    assert(not value:find('{~', 1, true), 'nested inline directives are not supported')
    if mode == '=' then value = transliteration.convert(value, false) end
    if value ~= '' then append(value, start, finish + 1, true) end
    cursor = finish + 2
  end
  return chunks
end

return directives
