-- core/rules.lua is LTPRO's grammar data: it must be exactly what
-- demo/extract_ltpro.lua extracts from the executable, and every table and
-- string in it must be read by the engine.
local rules = require 'core.rules'

local listing = assert(io.popen('ls core/*.lua'))
local code = {}
for path in listing:lines() do
  if path ~= 'core/rules.lua' then local f = assert(io.open(path)); code[#code + 1] = f:read('a'); f:close() end
end
listing:close()
code = table.concat(code, '\n')

local file = io.open('LTGOLD/LTPRO.EXE', 'rb')
if file then
  file:close()
  local extract = assert(io.popen('lua demo/extract_ltpro.lua LTGOLD/LTPRO.EXE'))
  local fresh = extract:read('a'); extract:close()
  local f = assert(io.open('core/rules.lua')); local current = f:read('a'); f:close()
  assert(fresh == current, 'core/rules.lua differs from demo/extract_ltpro.lua output; regenerate it')
end

local function referenced(at)
  return code:find(string.format('0x%04X%%f[^%%x]', at)) or code:find(string.format('0x%03X%%f[^%%x]', at))
end
local unused = {}
for _, section in ipairs({ 'strings', 'words', 'lists', 'paradigms' }) do
  for at in pairs(rules[section]) do
    if not referenced(at) then unused[#unused + 1] = string.format('%s 0x%04X', section, at) end
  end
end
-- Rule tables: T1-T8 by index, the others by key.
local uses = {
  [1] = 'rules%[1%]', [2] = 'rules%[2%]', [3] = 'rules%[3%]', [4] = 'rules%[4%]', [5] = 'rules%[5%]',
  [6] = 'rules%[6%]', [7] = 'rules%[7%]', [8] = 'NOUN_TABLE, ADJECTIVE_TABLE = 8', [9] = 'assets:rules%(9%)',
  adjective = "ADJECTIVE_TABLE = 8, 'adjective'", constituent = "assets:rules%('constituent'%)",
  suffixes = 'ltpro_rules%.suffixes', contractions = 'ltpro_rules%.contractions',
}
for key, value in pairs(rules) do
  if type(value) == 'table' and not ({ strings = 1, words = 1, lists = 1, paradigms = 1 })[key] then
    local pattern = assert(uses[key], 'rule table ' .. tostring(key) .. ' has no known reader')
    if not code:find(pattern) then unused[#unused + 1] = 'rule table ' .. tostring(key) end
  end
end
assert(#unused == 0, 'unused LTPRO data: ' .. table.concat(unused, ', '))
print('rules_test: passed')
