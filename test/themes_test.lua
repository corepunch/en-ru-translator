-- Theme dictionaries (openrussian/themes/*.txt -> openrussian/*.DIC) load
-- after BASE.DIC with dic_overlay and override it for the same key, as
-- LTGOLD's chained BUSINESS.DIC and COMPUTER.DIC did.
local engine = require 'core.engine'
local function text(sentence, overlay)
  local _, info = engine.translate(sentence, {dic_overlay=overlay})
  return info.text
end
local plain = text('Advising bank.')
assert(not plain:find('Авизующий', 1, true), 'BASE.DIC already has the business reading: ' .. plain)
assert(text('Advising bank.', 'openrussian/BUSINESS.DIC') == 'Авизующий банк.', text('Advising bank.', 'openrussian/BUSINESS.DIC'))
assert(text('Cost benefit.', 'openrussian/BUSINESS.DIC') == 'Финансовые льготы.', text('Cost benefit.', 'openrussian/BUSINESS.DIC'))
assert(text('Alarm bell.', 'openrussian/COMPUTER.DIC') == 'Сигнальный звонок.', text('Alarm bell.', 'openrussian/COMPUTER.DIC'))
assert(text('Cost benefit.') ~= 'Финансовые льготы.', 'overlay must not leak into the shared dictionary')
print('themes_test: passed')
