-- Theme dictionaries (LTGOLD/BUSINESS.DIC, COMPUTER.DIC) load
-- after BASE.DIC with dic_overlay and override it for the same key, as
-- LTGOLD's chained BUSINESS.DIC and COMPUTER.DIC did.
local engine = require 'core.engine'
local function text(sentence, overlay)
  local _, info = engine.translate(sentence, {dic_overlay=overlay})
  return info.text
end
local plain = text('Advising bank.')
assert(not plain:find('Авизующий', 1, true), 'BASE.DIC already has the business reading: ' .. plain)
assert(text('Advising bank.', 'LTGOLD/BUSINESS.DIC') == 'Авизующий Банк.', text('Advising bank.', 'LTGOLD/BUSINESS.DIC'))
assert(text('Cost benefit.', 'LTGOLD/BUSINESS.DIC') == 'Финансовые Льгота.', text('Cost benefit.', 'LTGOLD/BUSINESS.DIC'))
assert(text('Alarm bell.', 'LTGOLD/COMPUTER.DIC') == 'Сигнальный Звонок.', text('Alarm bell.', 'LTGOLD/COMPUTER.DIC'))
assert(text('Cost benefit.') ~= 'Финансовые Льгота.', 'overlay must not leak into the shared dictionary')
-- By name, as LTGOLD's /C chain; the first topic listed wins for a key.
local function topic(sentence, names) return (engine.translate(sentence, {topic = names})) end
assert(topic('Advising bank.', 'BUSINESS') == 'Авизующий Банк.')
assert(topic('Alarm bell.', 'computer') == 'Сигнальный Звонок.')
assert(topic('Advising bank.', 'BUSINESS,COMPUTER') == 'Авизующий Банк.')
assert(not pcall(engine.translate, 'Advising bank.', {topic = 'POLITICS'}))
print('themes_test: passed')
