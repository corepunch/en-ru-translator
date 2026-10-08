local patterns = {}

-- Dictionary ~ gaps capture zero or more word records, stopping at punctuation
-- or a protected span. Memoize failed suffixes to bound ambiguous searches.
function patterns.match(key, records, first, head)
  local parts = {}
  for part in key:gmatch('%S+') do parts[#parts + 1] = part:lower() end
  if #parts < 2 or parts[1] ~= head then return end
  local failed = {}
  local function match(part, index)
    if part > #parts then return index - 1, {} end
    local memo=part .. ':' .. index
    if failed[memo] then return end
    if parts[part] == '~' then
      local finish=index
      while true do
        local last, captures=match(part + 1, finish)
        if last then
          local capture={}
          for at=index,finish-1 do capture[#capture + 1]=records[at] end
          table.insert(captures,1,capture)
          return last,captures
        end
        local node=records[finish]
        if not node or node.kind ~= 0x57 or node.literal then break end
        finish=finish+1
      end
    else
      local node=records[index]
      if node and not node.literal and node.source:lower() == parts[part] then
        return match(part+1,index+1)
      end
    end
    failed[memo]=true
  end
  -- The head can be a dictionary backreference rather than the surface token.
  return match(2,first+1)
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
