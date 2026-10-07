local engine = require 'core.engine'
local lexicon = require 'core.lexicon'
local transliteration = require 'core.transliteration'
local encoding = require 'core.encoding'
assert(engine.translate('{~Keep  My TEXT!~}') == 'Keep  My TEXT!')
assert(engine.translate('{~' .. string.rep('long ', 30) .. '~}') == string.rep('long ', 30))
assert(engine.translate('{~=John Smith~}') == encoding.decode(transliteration.convert('John Smith', false)))
assert(engine.translate('{~a~} {~b~}.') == 'a b.')
assert(engine.translate('{~a~}{~b~}.') == 'ab.')
assert(engine.translate('{~a~}, {~b~}.') == 'a, b.')
local translated = engine.translate('Two books {~unchanged~}.')
assert(translated:find('unchanged', 1, true) and translated:find('книг', 1, true), translated)
assert(not pcall(engine.translate, '{~missing'))
assert(not pcall(engine.translate, '{~outer {~inner~}~}'))
local analyzed = lexicon.analyze(lexicon.from_bytes('word*Nслово\n'), '{~word~} word')
assert(analyzed.word_count == 1 and analyzed.vector[1].literal == 'word')
assert(analyzed.vector[2].reading == 'слово')
assert(engine.translate('{~Keep~}') == 'Keep', 'literal spans must not leak between calls')
print('directives_test: passed')
