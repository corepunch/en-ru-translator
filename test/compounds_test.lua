local lexicon = require 'core.lexicon'
local dictionary = lexicon.from_bytes('cat*Nкот\ndog*Nсобака\nknown-word*Nцелое\n')
for _, separator in ipairs({'-', '/'}) do
  local analyzed = lexicon.analyze(dictionary, 'cat' .. separator .. 'dog')
  assert(analyzed.vector[1].reading == 'кот')
  assert(analyzed.vector[2].source == separator)
  assert(analyzed.vector[3].reading == 'собака')
  for _, ending in ipairs({'ness', 'ment', 'ion', 'ence', 'ity', 'or'}) do
    for _, source in ipairs({'foo' .. separator .. ending, ending .. separator .. 'foo'}) do
      local state = lexicon.analyze(dictionary, source)
      assert(state.count == 3 and state.vector[1].source == source)
      assert(state.vector[1].tag == string.byte('N'))
    end
  end
end
assert(lexicon.analyze(dictionary, 'known-word').vector[1].reading == 'целое')
local mixed = lexicon.analyze(dictionary, 'cat/xyzzy/dog')
assert(mixed.vector[1].reading == 'кот' and mixed.vector[3].source == 'xyzzy' and mixed.vector[5].reading == 'собака')
assert(lexicon.analyze(dictionary, 'ABC-123').vector[1].source == 'ABC-123')
local known=lexicon.from_bytes('ion*Nион\nage*Nвозраст\ncat*Nкот\n')
for _,ending in ipairs({'ion','age'}) do
  local state=lexicon.analyze(known,'foo-'..ending)
  assert(state.count==5 and state.vector[3].reading==known.by_key[ending][1].value:sub(2))
  state=lexicon.analyze(known,ending..'-foo')
  assert(state.count==5 and state.vector[1].reading==known.by_key[ending][1].value:sub(2))
end
assert(lexicon.analyze(known,'cat-ness').count==5, 'known components retain their dictionary reading')
print('compounds_test: passed')
