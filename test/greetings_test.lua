local engine = require 'core.engine'
local lexicon = require 'core.lexicon'
local encoding = require 'core.encoding'
local file=assert(io.open('reference/openrussian/BASE.DIC','rb'))
local dictionary=lexicon.from_bytes(file:read('*a'));file:close()

local cases={
  {"What's up?",'Как дела?'}, {'What is up?','Как дела?'}, {'What’s up?','Как дела?'},
  {'How are you?','Как у тебя дела?'}, {"How're you?",'Как у тебя дела?'},
  {'How’re you?','Как у тебя дела?'}, {'  How   are\tyou?  ','Как у тебя дела?'},
  {'how are you?','как у тебя дела?'}, {'HOW ARE YOU?','КАК У ТЕБЯ ДЕЛА?'},
  {"WHAT'S UP?",'КАК ДЕЛА?'}, {'What is up.','Как дела.'},
  {'What is up!','Как дела!'}, {'What is up','Как дела'},
  {'what is up ?','как дела?'}, {'How is he?','Как у него дела?'},
  {'How is she?','Как у неё дела?'}, {"How's she?",'Как у неё дела?'},
  {'HOW IS SHE?','КАК У НЕЁ ДЕЛА?'},
  {"How's he?",'Как у него дела?'}, {'How’s she?','Как у неё дела?'},
  {'How are they?','Как у них дела?'}, {'How are we?','Как у нас дела?'},
  {'How am I?','Как у меня дела?'},
}
for _,case in ipairs(cases) do
  local input,expected=table.unpack(case)
  local actual,state=engine.translate(input)
  assert(actual==expected, input..' -> '..actual)
  local noun
  local word=state.root.next
  while word do
    if word.reading==encoding.encode('дело') then noun=word end
    word=word.next
  end
  assert(noun and noun.tag==string.byte('N') and noun.number==1 and noun.case_mask==0,
    'generate дела from a nominative plural noun')
  if input:lower():match('^%s*how') then
    local native_rule=false
    for _,event in ipairs(state.stages.T4.events) do
      if event.sub_rule and event.pattern=='XR[*]' then native_rule=true end
    end
    assert(native_rule, 'use the single native grammatical rule')
    local pronoun=state.lexical.vector[3]
    assert(pronoun.tag==string.byte('M') and pronoun.person>0 and pronoun.case_mask==2,
      'preserve pronoun grammatical fields through native T4 replacement')
  else
    local native_rule=false
    for _,event in ipairs(state.stages.T4.events) do
      if event.sub_rule and event.pattern=='<X>`up`[*]' then native_rule=true end
    end
    assert(native_rule, 'use the native T4 boundary subrule')
  end
end

-- Native T4 subsequently rewrites sentence-final it to это, overriding its
-- composite reading. Keep this known interaction visible, without introducing
-- a spelling-specific bypass of the native pipeline.
assert(engine.translate('How is it?')=='Как у это?')

-- Compare nearby inputs with the same dictionary minus the new entries. This
-- checks isolation without blessing the engine's existing awkward Russian.
local baseline={}
for _,record in ipairs(dictionary.records) do
  if record.key~='how XR[*]' and record.key~='what <X>`up`[*]' then
    baseline[#baseline+1]=record.raw
  end
end
baseline=table.concat(baseline,'\n')..'\n'
for _,input in ipairs({'How are you feeling?',"What's up there?",
    'How are {~you~}?','What {~is up~}?','How is he doing?',
    'How is she feeling?', 'How is the weather?', 'How are your parents?'}) do
  local actual=engine.translate(input)
  local expected=engine.translate(input,{dictionary=baseline})
  assert(actual==expected, input..': phrase changed an unrelated translation')
end
-- Original LTPRO's lexical context test also recognizes a one-word protected
-- source spelling. Preserve that captured native subrule behavior.
assert(engine.translate("What's {~up~}?")=='Как дела?')
assert(engine.translate('How are you.')=='Как у тебя дела.')
assert(engine.translate('How are you')=='Как у тебя дела')
-- The placeholder also accepts a newly added lexical pronoun reading. It must
-- not depend on enumerating English spellings or fixed Russian object forms.
local novel=engine.translate('How are thou?',{dictionary=dictionary.bytes..'thou*R021ты\n'})
assert(novel=='Как у тебя дела?',novel)
local formal=engine.translate('How are you?',{dictionary=dictionary.bytes..'you*R12'..encoding.encode('вы')..'\n',
  dictionary_entry=function(key,entries) return key=='you' and #entries or 1 end})
assert(formal=='Как у Вас дела?',formal)
-- Structural readings remain available outside this phrase, so ordinary
-- grammar rules can recognize auxiliaries and pronouns as X/R.
for _,case in ipairs({{'I am','*RX*'},{'You are','*RX*'},{'He is','*RX*'},
    {'She is','*RX*'},{'We are','*RX*'},{'They are','*RX*'},{'It is','*RX*'}}) do
  assert(lexicon.analyze(dictionary,case[1]).tags==case[2],case[1])
end
print('greetings_test: passed')
