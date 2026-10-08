local lexicon = require 'core.lexicon'
local encoding = require 'core.encoding'
local engine = require 'core.engine'
local dictionary = lexicon.from_bytes(encoding.encode([[take*Vбрать
cat*Nкот
dog*Nсобака
take ~ home*WVнести~Dдомой
take home*Vотнести
as ~ please*Jкак~ угодно
keep ~ safe*Vхранить
a number of*WIмногоPР
article i*WNстатья#I
how often*WDкакDчасто
long wave*WAдлиннаяNволна/A.длинноволновый
black board*WАкласснаяNдоска
swiss army knife*WармейскийNнож
empathize with*WVвходитьPВв ~ положение
]]))
local function analyzed(input) return lexicon.analyze(dictionary,input) end
local literal = analyzed('take home')
assert(literal.vector[1].reading == encoding.encode('отнести'))
local captured = analyzed('take cat dog home')
assert(captured.vector[1].reading == encoding.encode('нести'))
assert(captured.vector[2].reading == encoding.encode('кот'))
assert(captured.vector[3].reading == encoding.encode('собака'))
assert(captured.vector[4].reading == encoding.encode('домой'))
assert(captured.vector[2] ~= captured.vector[3])
local derived = analyzed('takes cat dog home')
assert(derived.vector[1].reading == encoding.encode('нести'))
assert(derived.vector[2].source=='cat' and derived.vector[4].reading==encoding.encode('домой'))
local implicit = analyzed('keep cat safe')
assert(implicit.vector[1].reading == encoding.encode('хранить') and implicit.vector[2].source == 'cat')
local blocked = analyzed('take cat, dog home')
assert(blocked.vector[1].reading == encoding.encode('брать'), 'gaps cannot cross punctuation')
assert(analyzed('take {~cat~} home').vector[2].literal, 'gaps cannot consume literal spans')
assert(analyzed('a number of').vector[1].tag == string.byte('I'))
assert(analyzed('how often').vector[1].reading == encoding.encode('как'))
local article = analyzed('article i')
assert(article.vector[2].reading == 'I')
local alternative = lexicon.analyze(dictionary,'long wave',{phrase_reading=function(_, readings)
  assert(#readings==2);return 2
end})
assert(alternative.vector[1].reading == encoding.encode('.длинноволновый'))
assert(analyzed('long wave').vector[1].reading == encoding.encode('длинная'))
assert(analyzed('black board').vector[1].tag == string.byte('A'))
assert(analyzed('swiss army knife').vector[1].reading == encoding.encode('армейский'))
assert(analyzed('empathize with').count>2)
local translated = engine.translate('take cat dog home', {dictionary=dictionary.bytes, prefixes=false})
assert(translated:find('кот',1,true) and translated:find('собак',1,true) and translated:find('домой',1,true), translated)
print('phrase_patterns_test: passed')
