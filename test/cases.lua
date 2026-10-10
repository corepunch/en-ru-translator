-- One translation check per line in test/translations.txt:
--   group[:entry] | input => expected   exact translation
--   group[:entry] | input ~> text       translation contains text
--   group[:entry] | input !> text       translation does not contain text
-- ~> and !> test the chosen words: inline alternatives ({1.кошка;кат}) are
-- removed first; => compares the whole output.
-- Quote an input with edge whitespace; inside quotes \t is a tab.
local cases = {}

local function unquote(value)
  local inner = value:match('^"(.*)"$')
  if not inner then return value end
  return (inner:gsub('\\t', '\t'))
end

function cases.load(path)
  local list = {}
  local number = 0
  for line in io.lines(path or 'test/translations.txt') do
    number = number + 1
    if line:match('%S') and not line:match('^%s*#') then
      local label, input, op, expected = line:match('^(.-)%s+|%s+(.-)%s+([=~!]>)%s+(.*)$')
      assert(label, 'malformed translation case at line ' .. number .. ': ' .. line)
      local group, entry = label:match('^([^:]+):(.+)$')
      list[#list + 1] = {group = group or label, entry = entry, input = unquote(input),
        op = op, expected = expected, line = number}
    end
  end
  return list
end

function cases.check(engine, case)
  local actual = engine.translate(case.input)
  local chosen = actual:gsub('{%d+%.[^}]*}', '')
  local found = chosen:find(case.expected, 1, true)
  local ok = (case.op == '=>' and actual == case.expected) or (case.op == '~>' and found)
    or (case.op == '!>' and not found)
  return ok and true or false, actual
end

function cases.group(list, name)
  local selected = {}
  for _, case in ipairs(list) do if case.group == name then selected[#selected + 1] = case end end
  return selected
end

return cases
