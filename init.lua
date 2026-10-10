#!/usr/bin/env lua
-- UTF-8 command-line boundary for the single-sentence translator.
package.path = './?.lua;./?/init.lua;' .. package.path

local engine = require 'core.engine'
local usage = [[Usage: lua init.lua [--data DIR] [--dic FILE] [--rus FILE] [sentence]
       printf '%s' 'English sentence.' | lua init.lua [asset options]

--data selects runtime assets; dictionary/ (LTGOLD's dictionaries with our
changes) is used by default.
Input and output are UTF-8. The translator accepts one sentence;
--document translates a whole text (stdin, or the FILE given) as LTPRO
translates a file: sentences, paragraphs and meanings appendices.
Asset options accept paths.
Inline {~text~} preserves text; {~=text~} transliterates it.
{~\N starts a list with 1-10 words per row; {~\. returns to sentence mode.
--meanings appends a glossary of alternative meanings and annotations.
--trace writes the token tags, readings and matched rules to stderr.
--prefixes FILE supplies prefix data; --no-prefixes disables prefix analysis.
--topic NAME[,NAME] loads topic dictionaries by name (BUSINESS, COMPUTER), as
LTGOLD's /C chain; the first listed wins.
--dic-overlay FILE and --rus-overlay FILE add indexed binary dictionary records.
--domain LABEL prefers readings with that dictionary domain label (e.g. инф).
--formal addresses the reader as Вы (LTGOLD's own readings); the default is ты.
--names transliterates an unknown capitalized word as a name (Xylophornium ->
Ксилофорниум); LTPRO leaves it in Latin.
--base-only leaves out the add-ons BASE2.DIC/.RUS, BASE3 ... (dictionary/phrases.txt).
--original gives LTPRO's own output: no add-on, and LTPRO's behaviour where
this translator improves on it (prefixed words, gap phrases, list controls,
stacked contractions).
]]

local options, words = {}, {}
local trace, whole = false, false
local asset_options = {
  ['--data'] = 'data_dir',
  ['--dic'] = 'dictionary', ['--rus'] = 'russian',
  ['--prefixes'] = 'prefixes', ['--dic-overlay'] = 'dic_overlay', ['--topic'] = 'topic',
  ['--rus-overlay'] = 'rus_overlay',
  ['--domain'] = 'domain',
}
local end_options = false
local i = 1
while i <= #arg do
  local key = arg[i]
  if not end_options and (key == '--help' or key == '-h') then
    io.write(usage)
    os.exit(0)
  elseif not end_options and key == '--' then
    end_options = true
    i = i + 1
  elseif not end_options and key == '--meanings' then
    options.meanings = true
    i = i + 1
  elseif not end_options and key == '--document' then
    whole = true
    i = i + 1
  elseif not end_options and key == '--trace' then
    trace = true
    i = i + 1
  elseif not end_options and key == '--formal' then
    options.formal = true
    i = i + 1
  elseif not end_options and key == '--names' then
    options.proper_names = true
    i = i + 1
  elseif not end_options and key == '--base-only' then
    options.addons = false
    i = i + 1
  elseif not end_options and key == '--original' then
    options.original = true
    i = i + 1
  elseif not end_options and key == '--no-prefixes' then
    options.prefixes = false
    i = i + 1
  elseif not end_options and asset_options[key] then
    local value = arg[i + 1]
    assert(value and value ~= '', 'missing value after ' .. key)
    options[asset_options[key]] = value
    i = i + 2
  elseif not end_options and key:match('^%-%-[^=]+=') then
    local option, value = key:match('^(%-%-[^=]+)=(.*)$')
    assert(asset_options[option], 'unknown option: ' .. option)
    assert(value ~= '', 'missing value after ' .. option)
    options[asset_options[option]] = value
    i = i + 1
  elseif not end_options and key:sub(1, 1) == '-' then
    io.stderr:write('Unknown option: ', key, '\n', usage)
    os.exit(2)
  else
    words[#words + 1] = key
    i = i + 1
  end
end

if whole then
  local encoding = require 'core.encoding'
  local input
  if #words > 0 then
    local file = io.open(table.concat(words, ' '), 'rb')
    if not file then io.stderr:write('cannot read ', table.concat(words, ' '), '\n'); os.exit(2) end
    input = file:read('a'); file:close()
  else input = io.stdin:read('a') or '' end
  local ok, result = pcall(function()
    return require('core.document').translate(encoding.encode(input), options)
  end)
  if not ok then
    io.stderr:write(tostring(result), '\n')
    os.exit(1)
  end
  io.write((encoding.decode(result):gsub('\r\n', '\n')))
  os.exit(0)
end

local input
if #words > 0 then
  input = table.concat(words, ' ')
else
  input = io.stdin:read('*a') or ''
end
if not input:match('%S') then
  io.stderr:write(usage)
  os.exit(2)
end

local ok, result, state = pcall(engine.translate, input, options)
if not ok then
  io.stderr:write(tostring(result), '\n')
  os.exit(1)
end
io.write(result, '\n')
if trace then
  io.stderr:write(require('core.trace').format(result, state), '\n')
end
