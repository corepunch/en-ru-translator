local engine = require 'core.engine'
local output = require 'core.output'
local encoding = require 'core.encoding'
local function bytes(path)
  local file = assert(io.open(path, 'rb'))
  local value = file:read('*a')
  file:close()
  return value
end
local legacy_dictionary = bytes('LTGOLD/BASE.DIC')
local legacy_russian = bytes('LTGOLD/BASE.RUS')
local legacy_options = {dictionary=legacy_dictionary,russian=legacy_russian}

local plain = engine.translate('He said, "I agree."', legacy_options)
local expanded, state = engine.translate('He said, "I agree."', {
  dictionary=legacy_dictionary,russian=legacy_russian,meanings=true,
})
assert(state.meanings_text:find('agree', 1, true))
assert(state.meanings_text:find('согласовывать', 1, true))
assert(expanded == plain .. '\n\n' .. state.meanings_text)
assert(state.output == encoding.encode(expanded) and state.text == expanded)
local before = state.root.next.next.text
assert(output.meanings(state, state.root) == state.meanings)
assert(state.root.next.next.text == before, 'glossary must not mutate records')
assert(engine.translate('Two books.', {meanings = true}) == engine.translate('Two books.'))
local dictionary=encoding.encode('first*Nкот{animal}\nsecond*Nдом;здание\nthird*Nкнига;том\n')
local listing, list_state=engine.translate('{~\\1 first second third', {dictionary=dictionary,meanings=true,prefixes=false})
assert(listing:find('{1.',1,true) and listing:find('{2.',1,true),listing)
assert(list_state.meanings_text:find('\n1  second:',1,true),listing)
assert(list_state.meanings_text:find('\n2  third:',1,true),listing)
assert(not list_state.meanings_text:find('1  first:',1,true),listing)
assert(list_state.alternatives==2)
local single=engine.translate('first second third', {dictionary=dictionary,meanings=true,prefixes=false})
assert(single:find('\n1  third:',1,true) and single:find('\n2  second:',1,true),single)
print('meanings_test: passed')
