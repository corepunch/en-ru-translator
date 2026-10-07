local lexicon = require 'core.lexicon'
local dictionary = lexicon.from_bytes('book*Nfirst\nbook*Nsecond\nalias*=book\n')
assert(#dictionary.by_key.book == 2)
assert(lexicon.analyze(dictionary, 'book').vector[1].reading == 'first')
local options = {dictionary_entry = function(key, entries)
  return key == 'book' and #entries or 1
end}
assert(lexicon.analyze(dictionary, 'book', options).vector[1].reading == 'second')
assert(lexicon.analyze(dictionary, 'alias', options).vector[1].reading == 'second')
assert(lexicon.analyze(dictionary, 'books', options).vector[1].reading == 'second')
assert(not pcall(lexicon.analyze, dictionary, 'book', {dictionary_entry = function() return 99 end}))
local cyclic = lexicon.from_bytes('one*=two\ntwo*=one\ntwo*Nsafe\n')
assert(not pcall(lexicon.analyze, cyclic, 'one'))
assert(lexicon.analyze(cyclic, 'one', {dictionary_entry = function(_, entries) return #entries end}).vector[1].reading == 'safe')
assert(dictionary.records[1].value == 'Nfirst', 'selection must preserve dictionary data')
print('dictionary_selection_test: passed')
