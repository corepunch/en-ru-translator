-- Translate an injected corpus with the same BASE files as the executable capture.
local dictionary_store = require 'dictionary_store'
local translator = require 'core.translator'
local cases = dofile(assert(arg[1], 'case list required'))
local data = assert(arg[2], 'dictionary directory required')
local selected = arg[3] and assert(tonumber(arg[3]), 'invalid selected case')
local english, russian = dictionary_store.load(data .. '/BASE.DIC', data .. '/BASE.RUS')
local engine = translator.new(english, russian)
local function hex(text) return (text:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
for i, case in ipairs(cases) do
  if not selected or selected == i then
    local ok, output, err = pcall(engine.translate, engine, case.input)
    if ok and output then print(i .. '\tOK\t' .. hex(output))
    else print(i .. '\tERROR\t' .. hex(tostring(ok and err or output))) end
  end
end
