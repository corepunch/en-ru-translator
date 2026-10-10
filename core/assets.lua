-- LTPRO's grammar data from core/rules.lua, by name: literals, word lists,
-- inflection tables and rule tables, encoded to CP866 once. A name the file
-- lacks is an error. Sentence state consists exclusively of Lua values.
local rules = require 'core.rules'
local encoding = require 'core.encoding'
local assets = {}
assets.__index = assets

local function build()
  local strings, lists, paradigms = {}, {}, {}
  for name, value in pairs(rules.strings) do strings[name] = encoding.encode(value) end
  for name, list in pairs(rules.lists) do
    local encoded = {}
    for i, value in pairs(list) do encoded[i] = encoding.encode(value) end
    lists[name] = encoded
  end
  for name, rows in pairs(rules.paradigms) do
    local encoded = {}
    for id, row in pairs(rows) do encoded[id] = {row[1], encoding.encode(row[2])} end
    paradigms[name] = encoded
  end
  return {strings = strings, lists = lists, paradigms = paradigms, rulesets = {}}
end
local shared

function assets.new()
  shared = shared or build()
  return setmetatable({strings = shared.strings, lists = shared.lists, base_paradigms = shared.paradigms,
    rulesets = shared.rulesets}, assets)
end

function assets:string(name)
  return self.strings[name] or error('no LTPRO literal ' .. tostring(name) .. ' in core/rules.lua')
end
-- A word list, entries from 0.
function assets:list(name)
  return self.lists[name] or error('no LTPRO list ' .. tostring(name) .. ' in core/rules.lua')
end
function assets:value(name)
  return rules.values[name] or error('no LTPRO value ' .. tostring(name) .. ' in core/rules.lua')
end
-- A rule table by its core/rules.lua key: records of pattern, endpoint order and selector.
function assets:rules(key)
  if not self.rulesets[key] then
    local list = {}
    for i, record in ipairs(assert(rules[key], 'no rule table ' .. tostring(key))) do
      list[i] = {pattern = encoding.encode(record[2]), order = record.endpoint_order, selector = record[1]}
    end
    self.rulesets[key] = list
  end
  return self.rulesets[key]
end

-- Inflection tables by name (noun-m, verb-perfective, replacement, ...). A
-- dictionary directory may carry its own text copy of the eight inflection
-- tables (dictionary/paradigms.txt), which then takes precedence.
function assets:load_paradigms(text, encode)
  local tables, current = {}, nil
  for line in text:gmatch('[^\n]+') do
    local name = line:match('^## (%S+)')
    if name then current = {}; tables[name] = current
    elseif current and not line:match('^#') then
      local id, cut, endings = line:match('^(%d+)\t(%d+)\t(.*)$')
      if id then current[tonumber(id)] = {tonumber(cut), encode(endings)} end
    end
  end
  self.paradigm_tables = tables
end
function assets:paradigm(name, id)
  local rows = self.paradigm_tables and self.paradigm_tables[name] or self.base_paradigms[name]
    or error('no inflection table ' .. tostring(name))
  local row = rows[id]
  if row then return row[1], row[2] end
  return 0, ''
end
return assets
