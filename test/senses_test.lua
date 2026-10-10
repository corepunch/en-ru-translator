-- Semantic regressions checked against the pre-refactor engine, including
-- annotations, alternate meanings and the links created by phrase expansion.
local engine = require 'core.engine'
local nodes = require 'core.nodes'
local senses = require 'core.senses'
local encode = require('core.encoding').encode
local state = engine.new_state('LTGOLD/BASE.RUS')
local function reading(source,value)
  local r = nodes.word(state,0x4E,encode(value))
  r.reading_state,r.previous_tag,r.source = 2,0x4E,source
  senses.choose(state,r)
  return r
end
local r = reading('party','NN.сторона{in a contract};партия{political};вечеринка{get together}')
assert(r.text == encode('сторона') and r.annotation == 'in a contract')
assert(r.paradigm == 3 and r.alternative_count == 2 and r.gender == 2)
assert(r.alternative.text == encode('партия') and r.alternative.annotation == 'political')
assert(r.alternative.alternative.text == encode('вечеринка'))
assert(r.alternative.alternative.annotation == 'get together')
assert(not r.next and not r.alternative.next)
local phrase = reading('shed light on','WVпроливать светPВна')
assert(phrase.text == encode('проливать') and phrase.marker == 0x77)
assert(phrase.next.text == encode('свет') and phrase.next.tag == 0x77)
assert(phrase.next.next.text == encode('на') and phrase.next.next.case_mask == 8)
assert(not phrase.next.next.next)
assert(r.text == encode('сторона') and r.alternative.text == encode('партия'))
print('senses_test: passed')
