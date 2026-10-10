-- core/rules.lua is LTPRO's grammar data: it must be exactly what
-- demo/extract_ltpro.lua extracts from the executable, carry no LTPRO
-- addresses, and every table and literal in it must be read by the engine.
local rules = require 'core.rules'

local listing = assert(io.popen('ls core/*.lua'))
local code = {}
for path in listing:lines() do
  if path ~= 'core/rules.lua' then local f = assert(io.open(path)); code[#code + 1] = f:read('a'); f:close() end
end
listing:close()
code = table.concat(code, '\n')

local f = assert(io.open('core/rules.lua')); local current = f:read('a'); f:close()
assert(not current:find('0x%x%x%x'), 'core/rules.lua must name its data, not give LTPRO addresses')
local file = io.open('LTGOLD/LTPRO.EXE', 'rb')
if file then
  file:close()
  local extract = assert(io.popen('lua demo/extract_ltpro.lua LTGOLD/LTPRO.EXE'))
  local fresh = extract:read('a'); extract:close()
  assert(fresh == current, 'core/rules.lua differs from demo/extract_ltpro.lua output; regenerate it')
end

local unused = {}
local function check(kind, name, ...)
  for _, pattern in ipairs({ ... }) do if code:find(pattern) then return end end
  unused[#unused + 1] = kind .. ' ' .. tostring(name)
end
local function quoted(name) return "'" .. name:gsub('%p', '%%%0') .. "'" end
for name in pairs(rules.strings) do check('string', name, quoted(name)) end
for name in pairs(rules.values) do check('value', name, quoted(name)) end
for name in pairs(rules.lists) do check('list', name, quoted(name), 'lists%.' .. name) end
for name in pairs(rules.paradigms) do check('paradigm table', name, quoted(name)) end
-- Rule tables: T1-T8 by index, the others by key.
local readers = {
  [1] = 'rules%[1%]', [2] = 'rules%[2%]', [3] = 'rules%[3%]', [4] = 'rules%[4%]', [5] = 'rules%[5%]',
  [6] = 'rules%[6%]', [7] = 'rules%[7%]', [8] = 'NOUN_TABLE, ADJECTIVE_TABLE = 8', [9] = 'assets:rules%(9%)',
  adjective = "ADJECTIVE_TABLE = 8, 'adjective'", constituent = "assets:rules%('constituent'%)",
  suffixes = 'ltpro_rules%.suffixes', contractions = 'ltpro_rules%.contractions',
}
for key, value in pairs(rules) do
  if type(value) == 'table' and not ({ strings = 1, values = 1, lists = 1, paradigms = 1 })[key] then
    check('rule table', key, assert(readers[key], 'rule table ' .. tostring(key) .. ' has no known reader'))
  end
end
assert(#unused == 0, 'unused LTPRO data: ' .. table.concat(unused, ', '))
print('rules_test: passed')
