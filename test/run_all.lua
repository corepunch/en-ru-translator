-- Run every Lua test in one process so BASE.DIC/BASE.RUS are parsed once and
-- shared through the engine's asset cache. One output line per test.
package.path = './?.lua;' .. package.path
local engine = require 'core.engine'
local cases = require 'test.cases'

local failures = 0
local function report(name, ok, message, seconds)
  if ok then print(string.format('ok    %-28s %6.2fs', name, seconds))
  else failures = failures + 1; print(string.format('FAIL  %-28s %s', name, message)) end
end

-- Line-per-case translation checks.
do
  local start, bad = os.clock(), {}
  local list = cases.load()
  for _, case in ipairs(list) do
    local ok, actual = cases.check(engine, case)
    if not ok then
      bad[#bad + 1] = string.format('line %d: %s %s %s (got %s)', case.line, case.input, case.op, case.expected, actual)
    end
  end
  report('translations.txt (' .. #list .. ')', #bad == 0, table.concat(bad, '; '), os.clock() - start)
end

local files = {}
local listing = io.popen('ls test/*_test.lua')
for path in listing:lines() do files[#files + 1] = path end
listing:close()

local real_print = print
for _, path in ipairs(files) do
  local name = path:match('([^/]+)%.lua$')
  local start = os.clock()
  print = function() end
  local ok, message = pcall(dofile, path)
  print = real_print
  report(name, ok, tostring(message):gsub('\n.*', ''), os.clock() - start)
end

if failures > 0 then
  print(failures .. ' failed')
  os.exit(1)
end
print('all ' .. (#files + 1) .. ' passed')
