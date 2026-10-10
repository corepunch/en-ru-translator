-- With original=true (--original) the engine gives LTPRO's own output where
-- it otherwise improves on it (the reviewed differences in
-- test/ltpro/review-2026-10-08). Every captured translation must match, as a
-- sentence and as a whole output file.
local engine = require 'core.engine'
local document = require 'core.document'
local encoding = require 'core.encoding'
local decode_json = require 'test.json'

local function read(path)
  local file = assert(io.open(path, 'rb')); local bytes = file:read('a'); file:close(); return bytes
end
local function unhex(value) return (value:gsub('..', function(h) return string.char(tonumber(h, 16)) end)) end
local options = {data_dir = 'LTGOLD', dictionary = 'LTGOLD/BASE.DIC', russian = 'LTGOLD/BASE.RUS', original = true}

local review = 'test/ltpro/review-2026-10-08/'
local corpora = {
  review .. 'reference.json', review .. 'phrase-reference.json', review .. 'natural-reference.json',
  review .. 'control-reference.json', 'test/ltpro/reference.json', 'test/ltpro/holdout_reference.json',
  'test/ltpro/macro_reference.json', 'test/ltpro/capitalization-reference.json',
  'test/ltpro/prepositions/reference.json', 'test/ltpro/prepositions/adverb-reference.json',
}
local failures, total = {}, 0
for _, path in ipairs(corpora) do
  for _, case in ipairs(decode_json(read(path)).cases) do
    total = total + 1
    local translated = engine.translate(case.input, options)
    if translated ~= case.translation then
      failures[#failures + 1] = string.format('%s %s\n  LTPRO: %s\n  Lua:   %s', case.id, case.input, case.translation, translated)
    end
    local file = document.translate(encoding.encode(case.input) .. '\r\n', options)
    if file ~= unhex(case.raw_cp866_hex) then
      failures[#failures + 1] = string.format('%s %s: output file differs\n  Lua: %s', case.id, case.input, encoding.decode(file))
    end
  end
end
assert(#failures == 0, #failures .. ' differences from LTPRO with original=true:\n' .. table.concat(failures, '\n'))
print(total .. ' captures match LTPRO with original=true')
