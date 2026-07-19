-- test/correct_test.lua — Tests with grammatically correct Russian outputs
-- Unlike ltgold200_test.lua which tests against LTPRO's sometimes-incorrect outputs,
-- this file tests against proper Russian grammar.

local load_mod = require "core.load"
local utils = require "core.utils"
local parser = require "core.parser"
local compiler = require "core.compiler"

local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
local en_ru = {}
compiler.base = {}
for line in file:lines() do
  load_mod.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local w, code = line:match("^(.-)\x2a(.*)$")
  if code then compiler.base[utils.decode(w)] = code end
end
file:close(); file2:close()

local cases = {
  -- Proper noun genitive (LTPRO gets this wrong — uses nominative)
  { "GENNAME", "The report of Anna was praised.", "Сообщение Анны было похвалено." },
  { "GENNAME", "The house of Peter burned down.", "Дом Питера сгорел." },

  -- Preposition: на for languages
  { "PREP", "He can write in Russian.", "Он может писать на русском." },
  { "PREP", "She spoke in English.", "Она говорила на английском." },

  -- not as...as (LTPRO gets this completely wrong)
  { "NOTAS", "He is not as tall as she is.", "Он не такой высокий, как она." },
  { "NOTAS", "This is not as simple as it looks.", "Это не так просто, как кажется." },

  -- Case agreement after ordinals (LTPRO uses genitive instead of accusative)
  { "ORD", "She read the 5th chapter last night.", "Она прочитала 5-ю главу вчера вечером." },

  -- either = каждый (not также)
  { "EITHER", "Either answer is correct.", "Каждый ответ правильный." },
}

local passed, failed = 0, 0
for _, case in ipairs(cases) do
  local group, input, expected = case[1], case[2], case[3]
  local tokens = utils.tokenize(input, en_ru)
  local parsed, err = parser.collect(en_ru, tokens)
  if not parsed then
    print(string.format("FAIL [%s] %s (parse error: %s)", group, input, err))
    failed = failed + 1
  else
    local got = compiler.compile(parsed, { quiet = true })
    if got == expected then
      passed = passed + 1
    else
      print(string.format("FAIL [%s] %s", group, input))
      print(string.format("  expected: %s", expected))
      print(string.format("  got:      %s", got))
      failed = failed + 1
    end
  end
end
print(string.format("\ncorrect: %d/%d passed", passed, passed + failed))
