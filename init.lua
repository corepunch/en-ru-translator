#!/usr/bin/env lua
-- UTF-8 command-line boundary for the single-sentence translator.
package.path = './?.lua;./?/init.lua;' .. package.path

local engine = require 'core.engine'
local usage = [[Usage: lua init.lua [--data DIR] [--exe FILE] [--dic FILE] [--rus FILE] [sentence]
       printf '%s' 'English sentence.' | lua init.lua [asset options]

--data selects runtime assets; OpenRussian dictionaries are used by default.
Input and output are UTF-8. The translator accepts one sentence;
it does not split multiple sentences. Asset options accept paths.
Inline {~text~} preserves text; {~=text~} transliterates it.
{~\N starts a list with 1-10 words per row; {~\. returns to sentence mode.
--meanings appends a glossary of alternative meanings and annotations.
--trace writes the token tags, readings and matched rules to stderr.
--prefixes FILE supplies prefix data; --no-prefixes disables prefix analysis.
--dic-overlay FILE and --rus-overlay FILE add indexed binary dictionary records.
--domain LABEL prefers readings with that dictionary domain label (e.g. инф).
]]

local options, words = {}, {}
local trace = false
local asset_options = {
  ['--data'] = 'data_dir', ['--exe'] = 'executable',
  ['--dic'] = 'dictionary', ['--rus'] = 'russian',
  ['--prefixes'] = 'prefixes', ['--dic-overlay'] = 'dic_overlay',
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
  elseif not end_options and key == '--trace' then
    trace = true
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
