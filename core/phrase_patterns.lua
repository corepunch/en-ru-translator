local patterns = {}

-- A dictionary ~ gap is at most one record (0A4F:1713): when the record at
-- the gap already equals the next key word the gap is empty, otherwise it
-- holds that record and the next key word must follow it.
function patterns.match(key, records, first, head)
  local parts = {}
  for part in key:gmatch('%S+') do parts[#parts + 1] = part:lower() end
  if #parts < 2 or parts[1] ~= head then return end
  local captures, index = {}, first + 1
  local function same(node, part)
    return node and not node.literal and (node.source or ''):lower() == part
  end
  local part = 2
  while part <= #parts do
    local node = records[index]
    if not node then return end
    if parts[part] == '~' then
      local following = parts[part + 1]
      if following and same(node, following) then
        captures[#captures + 1] = {}
      elseif node.literal then return
      else
        captures[#captures + 1] = {node}
        index = index + 1
        if following and not same(records[index], following) then return end
      end
      if following then index, part = index + 1, part + 2 else part = part + 1 end
    elseif same(node, parts[part]) then
      index, part = index + 1, part + 1
    else return end
  end
  return index - 1, captures
end

function patterns.segments(value)
  local segments, start, inside, literal = {}, 1, false, false
  for i=1,#value do
    local c=value:sub(i,i)
    if c=='{' then inside=true elseif c=='}' then inside=false end
    if c=='#' and not inside then literal=not literal end
    if c=='~' and not inside and not literal then segments[#segments+1]=value:sub(start,i-1);start=i+1 end
  end
  segments[#segments+1]=value:sub(start)
  return segments
end

-- How many records a W reading's components take: one per selector letter,
-- a space starting a w component (the loop of lexicon.apply_phrase).
function patterns.components(value)
  local pos, tag, count = 3, value:sub(2, 2), 0
  while tag ~= '' and tag:match('[A-Za-z#]') do
    local stop = pos
    while stop <= #value and not value:sub(stop, stop):match(tag == '#' and '#' or '[A-Za-z ~#/]') do
      if value:sub(stop, stop) == '{' then stop = value:find('}', stop, true) or #value end
      stop = stop + 1
    end
    local following = value:sub(stop, stop)
    if tag == '#' and following == '#' then stop = stop + 1; following = value:sub(stop, stop) end
    if following == ' ' then following = 'w' end
    count, tag, pos = count + 1, following, stop + 1
  end
  return count
end

function patterns.readings(value)
  local readings, start, annotation, literal = {}, 1, false, false
  for i=1,#value do
    local c=value:sub(i,i)
    if c=='{' then annotation=true elseif c=='}' then annotation=false end
    if not annotation and c=='#' then literal=not literal end
    if c=='/' and not annotation and not literal then
      readings[#readings+1]=value:sub(start,i-1);start=i+1
    end
  end
  readings[#readings+1]=value:sub(start)
  return readings
end

return patterns
