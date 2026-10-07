local prefixes = require 'core.prefixes'
local lexicon = require 'core.lexicon'
local engine = require 'core.engine'
local encoding = require 'core.encoding'
local rows = prefixes.from_bytes(encoding.encode('non не\nsub под\nre вновь\n*ill плохо\n'))
assert(#rows == 3 and rows[1].source == 'non' and rows[3].text == encoding.encode('вновь '))
local dict = lexicon.from_bytes(encoding.encode('cat*Nкот\nstrong*Aсильный\nnoncat*Nособый\n'))
local options = {prefixes=rows}
local function analyze(source) return lexicon.analyze(dict, source, options).vector[1] end
assert(analyze('noncat').reading == encoding.encode('особый'), 'exact entry wins')
assert(analyze('subcat').reading == encoding.encode('кот'))
assert(analyze('subcat').derivation_prefix == encoding.encode('под'))
assert(analyze('non-strong').reading == encoding.encode('сильный'))
assert(analyze('subcats').number == 1, 'suffix analysis also applies to the stem')
assert(analyze('nonxyzzy').derivation_prefix == nil, 'unrecognized stems stay intact')
local translated, state = engine.translate('subcat', {dictionary=encoding.encode('cat*Nкот\n'), prefixes=rows})
assert(translated == 'подкот', translated)
assert(engine.translate('subcat', {dictionary=encoding.encode('cat*Nкот\n'), prefixes=false}) == 'subcat')
assert(state.root.next.next.derivation_prefix == encoding.encode('под'))
local supplied = {dictionary=encoding.encode('cat*Nкот\n'), prefixes=encoding.encode('sub под\n')}
engine.translate('subcat', supplied)
assert(type(supplied.prefixes) == 'string', 'do not replace caller options with parsed data')
assert(not pcall(engine.translate, 'cat', {prefixes='/missing/prefixes.pre'}))
local alternatives = engine.translate('subcat', {dictionary=encoding.encode('cat*Nкот;собака\n'), prefixes=rows})
assert(alternatives:find('подкот',1,true) and alternatives:find('подсобака',1,true), alternatives)
print('prefixes_test: passed')
