-- Compare translations from two dictionary states in one Lua process.
--   lua tools/dict_compare.lua                  corpus, HEAD vs working tree
--   lua tools/dict_compare.lua --base REV       corpus, REV vs working tree
--   lua tools/dict_compare.lua "Sentence." ...  only these inputs
-- The corpus is every `input` in test/ltpro/**/*cases*.json plus
-- test/translations.txt. Prints only changed lines, then a count.
package.path = './?.lua;' .. package.path
local engine = require 'core.engine'

local base, inputs = 'HEAD', {}
local i = 1
while arg[i] do
  if arg[i] == '--base' then base = assert(arg[i + 1], '--base needs a revision'); i = i + 2
  else inputs[#inputs + 1] = arg[i]; i = i + 1 end
end

local function capture(command)
  local pipe = assert(io.popen(command)); local out = pipe:read('a'); pipe:close(); return out
end
-- Write the base revision's files to a temp dir: the engine caches parsed
-- assets by path, so passing raw bytes would re-parse them for every input.
local old_dir = capture('mktemp -d'):gsub('%s+$', '')
local function from_git(path)
  local target = old_dir .. '/' .. path:match('[^/]+$')
  assert(os.execute("git show '" .. base .. ':' .. path .. "' > '" .. target .. "' 2>/dev/null"),
    'cannot read ' .. path .. ' at ' .. base)
  return target
end

if #inputs == 0 then
  local seen = {}
  local function add(text) if text ~= '' and not text:find('\n') and not seen[text] then seen[text] = true; inputs[#inputs + 1] = text end end
  for path in capture("find test/ltpro -name '*cases*.json' | sort"):gmatch('[^\n]+') do
    local json = assert(io.open(path)):read('a')
    for value in json:gmatch('"input"%s*:%s*"(.-[^\\])"') do
      add((value:gsub('\\u(%x%x%x%x)', function(h) return utf8.char(tonumber(h, 16)) end)
        :gsub('\\(.)', { n = '\n', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' })))
    end
  end
  local cases = require 'test.cases'
  for _, case in ipairs(cases.load()) do add(case.input) end
end

local old = { dictionary = from_git('reference/openrussian/BASE.DIC'),
  russian = from_git('reference/openrussian/BASE.RUS'),
  russian_morphology = from_git('reference/openrussian/BASE.MORPH') }
local changed = 0
for _, input in ipairs(inputs) do
  local ok_old, before = pcall(engine.translate, input, old)
  local ok_new, after = pcall(engine.translate, input)
  before, after = ok_old and before or ('ERROR ' .. tostring(before)), ok_new and after or ('ERROR ' .. tostring(after))
  if before ~= after then
    changed = changed + 1
    print(input); print('  old: ' .. before); print('  new: ' .. after)
  end
end
print(string.format('%d of %d inputs changed (%s -> working tree)', changed, #inputs, base))
os.execute("rm -rf '" .. old_dir .. "'")
