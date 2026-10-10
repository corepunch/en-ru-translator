-- LTPRO's grammar data, read from core/rules.lua (extracted from the data
-- segment by demo/extract_ltpro.lua). The engine still names each table and
-- string by its DS offset; an offset the file lacks is an error, never a
-- silent read. Sentence state consists exclusively of Lua values.
local rules = require 'core.rules'
local encoding = require 'core.encoding'
local assets = {}
assets.__index = assets

local function build()
  local strings, entries, paradigms = {}, {}, {}
  for at, value in pairs(rules.strings) do strings[at] = encoding.encode(value) end
  for base, list in pairs(rules.lists) do
    local count = 0
    while list[count] do entries[base + count * 4] = encoding.encode(list[count]); count = count + 1 end
    if list.terminated then entries[base + count * 4] = false end
  end
  for base, rows in pairs(rules.paradigms) do
    local table_rows = {}
    for id, row in pairs(rows) do table_rows[id] = {row[1], encoding.encode(row[2])} end
    paradigms[base] = table_rows
  end
  return {strings = strings, entries = entries, paradigms = paradigms, rulesets = {}}
end
local shared

function assets.new()
  shared = shared or build()
  return setmetatable({strings = shared.strings, entries = shared.entries, base_paradigms = shared.paradigms,
    rulesets = shared.rulesets}, assets)
end

function assets:word(offset)
  return rules.words[offset] or error(string.format('LTPRO word 0x%04X is not in core/rules.lua', offset))
end
function assets:string(offset)
  return self.strings[offset] or error(string.format('LTPRO string 0x%04X is not in core/rules.lua', offset))
end
-- A pointer-list entry (DS base + 4*i); nil past a terminated list's end.
function assets:entry(offset)
  local value = self.entries[offset]
  if value == nil then error(string.format('LTPRO list entry 0x%04X is not in core/rules.lua', offset)) end
  return value or nil
end
function assets:indirect(offset)
  return self:entry(offset) or error(string.format('LTPRO list entry 0x%04X is a terminator', offset))
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

-- Inflection tables. A dictionary directory may carry its own copy as text
-- (openrussian/paradigms.txt), which then takes precedence for the eight
-- inflection tables.
local sections = {[0x5A50]='verb-imperfective',[0x5E90]='verb-perfective',[0x5238]='noun-m',[0x5450]='noun-f',
  [0x55A6]='noun-n',[0x56D4]='adjective-m',[0x5770]='adjective-f',[0x580C]='adjective-n'}
assets.paradigm_sections = sections
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
function assets:paradigm(offset, id)
  local section = self.paradigm_tables and self.paradigm_tables[sections[offset]]
  local rows = section or self.base_paradigms[offset] or error(string.format('no inflection table 0x%04X', offset))
  local row = rows[id]
  if row then return row[1], row[2] end
  return 0, ''
end
return assets
