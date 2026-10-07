-- Prefix data is CP866, like the dictionaries. Keep file order for ties and
-- prefer the longest matching prefix. A leading * disables a data row.
local prefixes = {}

function prefixes.from_bytes(bytes)
  local rows = {}
  for line in bytes:gmatch('[^\r\n]+') do
    local source, translation = line:match('^%s*([A-Za-z]+)%s+(%S+)%s*$')
    if source then
      source = source:lower()
      rows[#rows + 1] = {source=source, text=translation .. (source == 're' and ' ' or ''), order=#rows + 1}
    end
  end
  table.sort(rows, function(a, b)
    return #a.source > #b.source or #a.source == #b.source and a.order < b.order
  end)
  return rows
end

function prefixes.lookup(rows, source, resolve)
  local lower = source:lower()
  for _, row in ipairs(rows) do
    if lower:sub(1, #row.source) == row.source then
      local stem = source:sub(#row.source + 1):gsub('^-', '')
      if stem ~= '' and not stem:find('[-/]') then
        local result = resolve(stem)
        if result and result.record and result.tag:match('^[ANZVDGEF]$') then
          return result, row.text
        end
      end
    end
  end
end

return prefixes
