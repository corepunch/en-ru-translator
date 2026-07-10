local M = { level = 0 }

function M.set_level(n)
  M.level = n
end

function M.log(lvl, ...)
  if lvl <= M.level then
    local parts = {}
    for i = 1, select('#', ...) do
      local v = select(i, ...)
      parts[i] = tostring(v)
    end
    print(table.concat(parts, " "))
  end
end

function M.printf(lvl, fmt, ...)
  if lvl <= M.level then
    print(string.format(fmt, ...))
  end
end

return M
