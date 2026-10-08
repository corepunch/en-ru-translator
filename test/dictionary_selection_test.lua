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
for _,invalid in ipairs({false,0,-1,1.5,'1',99}) do
  assert(not pcall(lexicon.analyze,dictionary,'book',{dictionary_entry=function() return invalid end}))
end
assert(not pcall(lexicon.analyze,dictionary,'book',{dictionary_entry=function() end}))
assert(not pcall(lexicon.analyze,dictionary,'book',{dictionary_entry=true}))
local cyclic = lexicon.from_bytes('one*=two\ntwo*=one\ntwo*Nsafe\n')
assert(not pcall(lexicon.analyze, cyclic, 'one'))
assert(lexicon.analyze(cyclic, 'one', {dictionary_entry = function(_, entries) return #entries end}).vector[1].reading == 'safe')
assert(dictionary.records[1].value == 'Nfirst', 'selection must preserve dictionary data')
local aliases=lexicon.from_bytes('volume*=book\nbook*Nfirst\n')
assert(lexicon.lookup(aliases,'volumes').record==aliases.by_key.book[1])
assert(lexicon.analyze(aliases,'volumes').vector[1].reading=='first')
assert(not pcall(lexicon.lookup,cyclic,'ones'), 'suffix redirects need cycle detection too')
print('dictionary_selection_test: passed')
