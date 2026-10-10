-- The default dictionary says ты; --formal (formal = true) chains LTGOLD's
-- own Вы records back in, so a sentence addressing the reader translates
-- exactly as with LTGOLD's dictionaries.
local engine = require 'core.engine'
-- LTGOLD's English dictionary with our Russian side (dictionary/paradigms.txt).
local ltgold = {dictionary = 'LTGOLD/BASE.DIC', russian = 'dictionary/BASE.RUS'}
local sentences = {
  'Thank you.', 'Are you home?', 'Will you come?', 'Did you see it?', 'If you want, I will come.',
  'I will call you.', 'I will tell you.', 'You should go.', 'I want to see you.', 'I see your sister.',
  'Your letter is here.', 'I live in your house.', 'Glad to see you.', 'It is very kind of you to help.',
}
for _, sentence in ipairs(sentences) do
  local formal, original = engine.translate(sentence, {formal = true}), engine.translate(sentence, ltgold)
  assert(formal == original, sentence .. '\n  formal: ' .. formal .. '\n  LTGOLD: ' .. original)
  assert(engine.translate(sentence) ~= original, 'the default should say ты: ' .. sentence)
end
assert(engine.translate('I see your sister.') == 'Я вижу твою сестру.')
print('formal_test: passed')
