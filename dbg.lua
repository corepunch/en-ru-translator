local M = { level = 0, categories = {}, file = nil }

function M.set_level(n) M.level = n end

function M.enable(cat) M.categories[cat] = true end

function M.disable(cat) M.categories[cat] = false end

function M.is_enabled(cat) return M.categories[cat] end

-- set_file: redirect all debug output to a file instead of stdout
function M.set_file(path)
  if M.file then M.file:close() end
  if path then M.file = assert(io.open(path, "w")) end
end

local function write(...)
  if M.file then
    local parts = {}
    for i = 1, select('#', ...) do
      local v = select(i, ...)
      parts[i] = tostring(v)
    end
    M.file:write(table.concat(parts, " ") .. "\n")
    M.file:flush()
  else
    print(...)
  end
end

function M.log(lvl, ...)
  if lvl <= M.level then write(...) end
end

-- diag: log a message under a named diagnostic category
-- Usage: dbg.diag("multi", "form:", t, "has", n, "variants")
function M.diag(cat, ...)
  if M.categories[cat] then write("["..cat.."]", ...) end
end

function M.printf(lvl, fmt, ...)
  if lvl <= M.level then write(string.format(fmt, ...)) end
end

return M