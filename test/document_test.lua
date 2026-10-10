-- Replays test/ltpro/documents: whole files translated by the original LTPRO
-- (`/I in /O out /F- /B- /N`, LTGOLD's own BASE.DIC/BASE.RUS), including
-- LTGOLD's DEMO.TXT. The document layer must reproduce every output file
-- byte for byte: layout, separators, inline alternatives and appendices.
local document = require 'core.document'
local encoding = require 'core.encoding'
local decode_json = require 'test.json'

local function read(path)
  local file = assert(io.open(path, 'rb')); local bytes = file:read('a'); file:close(); return bytes
end
local directory = 'test/ltpro/documents/'
local cases = decode_json(read(directory .. 'cases.json'))
local reference = decode_json(read(directory .. 'reference.json'))
assert(#cases == #reference.cases, 'reference.json is stale: recapture with tools/ltpro_capture.py')

local options = {data_dir = 'LTGOLD', dictionary = 'LTGOLD/BASE.DIC', russian = 'LTGOLD/BASE.RUS'}
local function unhex(value) return (value:gsub('..', function(h) return string.char(tonumber(h, 16)) end)) end

-- The first differing line, decoded, for a readable failure.
local function first_difference(expected, actual)
  local function lines(text)
    local result = {}
    for line in (encoding.decode(text) .. '\n'):gmatch('(.-)\r?\n') do result[#result + 1] = line end
    return result
  end
  local a, b = lines(expected), lines(actual)
  for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then
      return string.format('line %d\n  LTPRO: %s\n  Lua:   %s', i, a[i] or '<end>', b[i] or '<end>')
    end
  end
  return 'same lines, different bytes'
end

-- Documents whose sentences the engine does not yet translate as LTPRO does;
-- their layout already matches. Each must still differ, so the list shrinks.
local pending = {
  demo = true,
}

local failures = {}
for index, case in ipairs(reference.cases) do
  assert(case.id == cases[index].id and case.input == cases[index].input, 'reference.json is stale for ' .. cases[index].id)
  -- The capture writes the input as CP866 followed by CRLF.
  local expected = unhex(case.raw_cp866_hex)
  local actual = document.translate(encoding.encode(case.input) .. '\r\n', options)
  if pending[case.id] then
    if actual == expected then failures[#failures + 1] = case.id .. ': now matches; remove it from pending' end
  elseif actual ~= expected then
    failures[#failures + 1] = case.id .. ': ' .. first_difference(expected, actual)
  end
end
assert(#failures == 0, #failures .. ' of ' .. #reference.cases .. ' documents differ:\n' .. table.concat(failures, '\n'))
local count = 0
for _ in pairs(pending) do count = count + 1 end
print((#reference.cases - count) .. ' of ' .. #reference.cases .. ' documents match LTPRO byte for byte')
