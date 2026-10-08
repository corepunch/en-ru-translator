local engine = require 'core.engine'
local encoding = require 'core.encoding'
local dict = encoding.encode('admission*Nдопущение;инф)доступ;тех)вход\n')
local plain = engine.translate('admission', {dictionary=dict, prefixes=false})
assert(plain:find('допущение', 1, true) == 1)
local preferred, state = engine.translate('admission', {dictionary=dict, prefixes=false, domain='инф', meanings=true})
assert(preferred:find('доступ', 1, true) == 1, preferred)
assert(preferred:find('допущение', 1, true) and preferred:find('вход', 1, true))
assert(state.root.next.next.domain == encoding.encode('инф'))
assert(engine.translate('admission', {dictionary=dict, domain='unknown', prefixes=false}) == plain)
assert(engine.translate('admission', {dictionary=dict, domain='тех', prefixes=false}):find('вход', 1, true) == 1)
assert(engine.translate('admission', {dictionary=dict, prefixes=false}) == plain, 'domain choices must not leak between calls')
print('domain_test: passed')
