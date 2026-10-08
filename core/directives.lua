local transliteration = require 'core.transliteration'
local directives = {}

-- List controls change formatting for the following text. Protected spans are
-- skipped as a unit, so a control-looking string inside one stays literal.
function directives.sections(input)
  local sections, cursor, first, columns, found = {}, 1, 1, nil, false
  local function append(last)
    local value=input:sub(first,last)
    if value:match('%S') then sections[#sections+1]={input=value, columns=columns} end
  end
  while cursor<=#input do
    local start=input:find('{~',cursor,true)
    if not start then break end
    if input:sub(start+2,start+2)=='\\' then
      append(start-1)
      local control=input:sub(start+3,start+3)
      if control=='.' then columns=nil;cursor=start+4
      else
        local count=assert(input:sub(start+3):match('^%d+'), 'list directive needs a column count or .')
        columns=tonumber(count)
        assert(columns>=1 and columns<=10, 'list column count must be between 1 and 10')
        cursor=start+3+#count
      end
      first,found=cursor,true
    else
      local finish=assert(input:find('~}',start+2,true), 'unterminated inline directive')
      cursor=finish+2
    end
  end
  if not found then return nil end
  append(#input)
  return sections
end

function directives.items(input)
  local items, cursor={},1
  while cursor<=#input do
    local first=input:find('%S',cursor)
    if not first then break end
    local last=first
    while last<=#input and not input:sub(last,last):match('%s') do
      if input:sub(last,last+1)=='{~' then
        last=assert(input:find('~}',last+2,true),'unterminated inline directive')+2
      else last=last+1 end
    end
    items[#items+1]=input:sub(first,last-1)
    cursor=last
  end
  return items
end

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
    assert(mode ~= '\\', 'list directives require engine.run or engine.translate')
    if mode == '=' then content = content + 1 end
    local finish = assert(input:find('~}', content, true), 'unterminated inline directive')
    local value = input:sub(content, finish - 1)
    assert(not value:find('{~', 1, true), 'nested inline directives are not supported')
    if mode == '=' then value = transliteration.convert(value, true) end
    if value ~= '' then append(value, start, finish + 1, true)
    elseif start==previous_end+1 then previous_end=finish+1 end
    cursor = finish + 2
  end
  return chunks
end

return directives
