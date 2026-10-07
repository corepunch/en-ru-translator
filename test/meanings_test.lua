local engine = require 'core.engine'
local output = require 'core.output'
local encoding = require 'core.encoding'

local plain = engine.translate('He said, "I agree."')
local expanded, state = engine.translate('He said, "I agree."', {meanings = true})
assert(state.meanings_text:find('agree', 1, true))
assert(state.meanings_text:find('согласовывать', 1, true))
assert(expanded == plain .. '\n\n' .. state.meanings_text)
assert(state.output == encoding.encode(expanded) and state.text == expanded)
local before = state.root.next.next.text
assert(output.meanings(state, state.root) == state.meanings)
assert(state.root.next.next.text == before, 'glossary must not mutate records')
assert(engine.translate('Two books.', {meanings = true}) == engine.translate('Two books.'))
print('meanings_test: passed')
