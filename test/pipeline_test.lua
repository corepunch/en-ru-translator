local engine = require 'core.engine'
local function bytes(path)
  local file = assert(io.open(path, 'rb'))
  local value = file:read('*a')
  file:close()
  return value
end

local cases = {
	{"I'm testing this.", 'Я тестирую это.'},
	{'I’m testing this.', 'Я тестирую это.'},
	{'I‘m testing this.', 'Я тестирую это.'},
	{"I'M TESTING THIS.", 'Я ТЕСТИРУЮ ЭТО.'},
  {'He is in the house.', 'Он - в доме.'},
  {'If he comes then I go.', 'Если он приходит тогда Я иду.'},
  {'EXHIBIT A.', 'ПОКАЖИТЕ A.'},
  {'He said, "I agree."', 'Он сказал, "Я соглашаюсь{1.согласовывать}."'},
  {'He said: "Go."', 'Он сказал: "Идти."'},
  {'ABC-123.', 'ABC-123.'},
  {'The xyzness is deep.', 'xyzness глубоко.'},
  {'The strongness is deep.', 'strongness глубоко.'},
  {'The xyzzy is deep.', 'xyzzy глубок.'},
}

for _, case in ipairs(cases) do
  local input, expected = table.unpack(case)
  local actual, state = engine.translate(input, {
    data_dir = 'LTGOLD',
    dictionary = 'LTGOLD/BASE.DIC',
    russian = 'LTGOLD/BASE.RUS',
  })
  assert(actual == expected, string.format('%q => %q, expected %q', input, actual, expected))
  if input == 'ABC-123.' then
    assert(state.stages.lexical_word_count == 0 and not state.stages.T1 and not state.stages.numeric)
  else
    assert(state.stages.lexical_word_count > 0)
  end
end

-- The explicit asset arguments also accept the raw byte strings used by
-- embedding callers, including the executable image with embedded NULs.
local raw_options = {
  executable = bytes('LTGOLD/LTPRO.EXE'),
  dictionary = bytes('LTGOLD/BASE.DIC'),
  russian = bytes('LTGOLD/BASE.RUS'),
}
local raw_result = engine.translate('He is in the house.', raw_options)
assert(raw_result == 'Он - в доме.')

print('pipeline_test: passed')
